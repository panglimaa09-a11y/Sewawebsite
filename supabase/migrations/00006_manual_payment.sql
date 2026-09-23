-- ═══════════════════════════════════════════════════════════════════
-- MANUAL PAYMENT (PRD #20 — fase manual, tanpa payment gateway)
--
-- Alur:
--   Checkout → invoice PENDING + instruksi transfer (DANA, diatur admin)
--   → user kirim bukti via Support ticket
--   → trigger memberi notifikasi broadcast ke staff
--   → admin klik "Verifikasi" → verify_manual_payment() memperpanjang
--     langganan + website + notifikasi user (semua server-side)
--
-- Status pembayaran tetap TIDAK pernah diubah dari client:
-- hanya fungsi security-definer yang memeriksa is_staff().
-- ═══════════════════════════════════════════════════════════════════

-- ── Instruksi pembayaran manual di system_settings (diubah admin) ──
alter table public.system_settings
  add column if not exists manual_payment_enabled  boolean not null default true,
  add column if not exists manual_bank_name        text not null default 'Bank Transfer',
  add column if not exists manual_account_number   text not null default '',
  add column if not exists manual_account_holder   text not null default '',
  add column if not exists manual_instructions     text not null default
    'Transfer sesuai nominal invoice, lalu kirim bukti pembayaran (screenshot) melalui menu Support.';

-- Nilai awal sesuai konfigurasi pemilik platform
update public.system_settings set
  manual_bank_name      = 'DANA',
  manual_account_number = '082336939662',
  manual_account_holder = 'Angga Bayu Setyawan'
where id = '00000000-0000-0000-0000-000000000000';

-- ── create_checkout: gateway 'manual' (tanpa provider eksternal) ──
create or replace function public.create_checkout(
  p_plan_id uuid,
  p_billing_period public.billing_period default 'monthly',
  p_coupon_code text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  p      record;
  vc     jsonb;
  disc   numeric := 0;
  base   numeric;
  v_sub  uuid;
  v_inv  uuid;
  v_pay  uuid;
begin
  if v_user is null then
    raise exception 'UNAUTHENTICATED';
  end if;

  select * into p from public.plans where id = p_plan_id and is_active;
  if not found then
    raise exception 'PLAN_NOT_FOUND';
  end if;

  base := case
    when p_billing_period = 'yearly' then coalesce(p.price_yearly, p.price_monthly * 12)
    else p.price_monthly
  end;

  if p_coupon_code is not null and btrim(p_coupon_code) <> '' then
    vc := public.validate_coupon(p_coupon_code, p_plan_id, base);
    if not coalesce((vc->>'valid')::boolean, false) then
      return jsonb_build_object('ok', false, 'reason', vc->>'reason');
    end if;
    disc := (vc->>'discount')::numeric;
  end if;

  insert into public.subscriptions
    (user_id, plan_id, coupon_id, status, billing_period, current_period_start, current_period_end)
  values
    (v_user, p_plan_id, (vc->>'coupon_id')::uuid, 'active', p_billing_period, now(), now() + interval '3 days')
  returning id into v_sub;

  insert into public.invoices
    (user_id, subscription_id, status, due_date, subtotal, discount, total)
  values
    (v_user, v_sub, 'pending', now() + interval '3 days', base, disc, base - disc)
  returning id into v_inv;

  insert into public.payments
    (user_id, invoice_id, subscription_id, amount, currency, gateway, status, metadata)
  values
    (v_user, v_inv, v_sub, base - disc, p.currency, 'manual', 'pending',
     jsonb_build_object('plan', p.slug, 'period', p_billing_period,
                        'coupon', coalesce(vc->>'code', null)))
  returning id into v_pay;

  if (vc->>'coupon_id') is not null then
    insert into public.coupon_redemptions
      (coupon_id, user_id, subscription_id, invoice_id, discount_amount)
    values
      ((vc->>'coupon_id')::uuid, v_user, v_sub, v_inv, disc);
    update public.coupons set used_count = used_count + 1
    where id = (vc->>'coupon_id')::uuid;
  end if;

  insert into public.activity_logs (actor_id, action, target_type, target_id, metadata)
  values (v_user, 'checkout_created', 'subscription', v_sub,
          jsonb_build_object('plan', p.slug, 'period', p_billing_period,
                             'discount', disc, 'gateway', 'manual'));

  return jsonb_build_object(
    'ok', true,
    'subscription_id', v_sub, 'invoice_id', v_inv, 'payment_id', v_pay,
    'subtotal', base, 'discount', disc, 'total', base - disc);
end;
$$;

-- ── Notifikasi admin saat ticket baru masuk (broadcast) ──────────
create or replace function public.notify_admin_new_ticket() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (user_id, title, body, type, channel)
  values (null, -- broadcast: staff membaca via policy "own or broadcast read"
    'Tiket baru: ' || coalesce(new.subject, '-'),
    'Kategori: ' || coalesce(new.category, 'general') || '. Buka /admin/tickets untuk membalas.',
    'ticket_new', 'dashboard');
  return new;
end;
$$;

create trigger ticket_created_notify
  after insert on public.tickets
  for each row execute function public.notify_admin_new_ticket();

-- ── Verifikasi pembayaran manual oleh admin ───────────────────────
-- Satu-satunya jalur client yang boleh mengubah status pembayaran:
-- fungsi ini menolak jika pemanggil bukan staff.
create or replace function public.verify_manual_payment(
  p_payment_id uuid,
  p_note text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  pm  record;
  sub record;
  inv record;
  tpl jsonb;
  v_nama text;
  v_website text;
begin
  if not public.is_staff() then
    raise exception 'FORBIDDEN';  -- hanya staff
  end if;

  select * into pm from public.payments where id = p_payment_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  if pm.status = 'paid' then
    return jsonb_build_object('ok', true, 'already', true);
  end if;

  -- 1. Payment + invoice lunas
  update public.payments set status = 'paid', paid_at = now(), updated_at = now()
    where id = p_payment_id;
  if pm.invoice_id is not null then
    update public.invoices set status = 'paid', paid_at = now(), updated_at = now()
      where id = pm.invoice_id
    returning * into inv;
  end if;

  -- 2. Perpanjang subscription + website
  if pm.subscription_id is not null then
    select * into sub from public.subscriptions where id = pm.subscription_id;
    if found then
      declare
        days int := case when sub.billing_period = 'yearly' then 365 else 30 end;
        base timestamptz := greatest(sub.current_period_end, now());
      begin
        update public.subscriptions
          set status = 'active',
              current_period_start = now(),
              current_period_end = base + (days || ' days')::interval,
              updated_at = now()
          where id = sub.id;
        if sub.website_id is not null then
          update public.websites
            set status = 'active', expires_at = base + (days || ' days')::interval, updated_at = now()
            where id = sub.website_id;
          select coalesce(subdomain, name) into v_website from public.websites where id = sub.website_id;
        end if;
      end;
    end if;
  end if;

  -- 3. Notifikasi user (dari template PRD #34, fallback teks)
  select full_name into v_nama from public.profiles where id = pm.user_id;
  tpl := public.apply_template('payment_success', jsonb_build_object(
    'nama', v_nama, 'jumlah', to_char(pm.amount, 'FM999999999'),
    'invoice', coalesce(inv.number, '-'), 'website', coalesce(v_website, '-'),
    'tanggal', to_char(now(), 'DD Mon YYYY')));
  insert into public.notifications (user_id, title, body, type, channel)
  values (pm.user_id,
    coalesce(tpl->>'subject', 'Pembayaran Berhasil'),
    coalesce(tpl->>'body', 'Pembayaran Anda telah diverifikasi. Langganan diperpanjang.'),
    'payment_success', 'dashboard');

  -- 4. Audit
  insert into public.activity_logs (actor_id, actor_role, action, target_type, target_id, metadata)
  values (auth.uid(), 'staff', 'payment_verified_manual', 'payment', p_payment_id,
          jsonb_build_object('amount', pm.amount, 'note', p_note));

  return jsonb_build_object('ok', true, 'already', false);
end;
$$;
