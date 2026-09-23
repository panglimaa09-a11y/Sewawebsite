-- ═══════════════════════════════════════════════════════════════════
-- CHECKOUT + COUPON REDEMPTION (PRD #20, #22)
--
-- Tabel coupons dikunci RLS (staff-only), jadi user TIDAK bisa membaca
-- daftar kupon. Validasi dilakukan lewat fungsi security definer yang
-- hanya mengembalikan verdict (valid/reason/discount) — bukan isi tabel.
--
-- create_checkout() membuat SELURUH transaksi dalam satu transaksi DB:
-- subscription → invoice (diskon) → payment pending → coupon_redemptions
-- ═══════════════════════════════════════════════════════════════════

-- ── Validasi kupon ────────────────────────────────────────────────
-- Dipanggil sebelum bayar (tombol "Terapkan") dan di dalam create_checkout.
create or replace function public.validate_coupon(
  p_code text,
  p_plan_id uuid,
  p_amount numeric default null
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  c    record;
  disc numeric := 0;
  base numeric := coalesce(p_amount, 0);
begin
  if p_code is null or btrim(p_code) = '' then
    return jsonb_build_object('valid', false, 'reason', 'empty');
  end if;

  select * into c from public.coupons where upper(code) = upper(btrim(p_code));
  if not found then
    return jsonb_build_object('valid', false, 'reason', 'not_found');
  end if;
  if not c.is_active then
    return jsonb_build_object('valid', false, 'reason', 'inactive');
  end if;
  if c.starts_at is not null and c.starts_at > now() then
    return jsonb_build_object('valid', false, 'reason', 'not_started');
  end if;
  if c.expires_at is not null and c.expires_at < now() then
    return jsonb_build_object('valid', false, 'reason', 'expired');
  end if;
  if c.max_usage is not null and c.used_count >= c.max_usage then
    return jsonb_build_object('valid', false, 'reason', 'max_usage');
  end if;
  if c.plan_restriction is not null and c.plan_restriction <> p_plan_id then
    return jsonb_build_object('valid', false, 'reason', 'plan_restriction');
  end if;
  if c.min_payment > 0 and base < c.min_payment then
    return jsonb_build_object('valid', false, 'reason', 'min_payment', 'min_payment', c.min_payment);
  end if;

  disc := case
    when c.type = 'percentage' then round(base * c.value / 100)
    else least(c.value, base)   -- nominal diskon tidak melebihi total
  end;

  return jsonb_build_object(
    'valid', true, 'coupon_id', c.id, 'code', c.code,
    'type', c.type, 'value', c.value, 'discount', disc);
end;
$$;

-- ── Buat checkout lengkap ─────────────────────────────────────────
-- Pemanggil: user yang login (auth.uid() dipakai; cek di awal).
-- Subscription dibuat 'active' dengan jendela pembayaran 3 hari —
-- webhook pembayaran (PRD #20) memperpanjang penuh setelah bayar;
-- jika tidak dibayar, automation engine memindahkan ke past_due →
-- suspended sesuai lifecycle PRD #17. (Sesuai desain: status pembayaran
-- TIDAK pernah diubah dari client — hanya webhook terverifikasi.)
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

  -- Validasi kupon (fungsi di atas — satu sumber kebenaran)
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
    (v_user, v_sub, 'pending', now() + interval '1 day', base, disc, base - disc)
  returning id into v_inv;

  insert into public.payments
    (user_id, invoice_id, subscription_id, amount, currency, gateway, status, metadata)
  values
    (v_user, v_inv, v_sub, base - disc, p.currency, 'midtrans', 'pending',
     jsonb_build_object('plan', p.slug, 'period', p_billing_period,
                        'coupon', coalesce(vc->>'code', null)))
  returning id into v_pay;

  -- Catat penebusan + increment counter batas pemakaian
  if (vc->>'coupon_id') is not null then
    insert into public.coupon_redemptions
      (coupon_id, user_id, subscription_id, invoice_id, discount_amount)
    values
      ((vc->>'coupon_id')::uuid, v_user, v_sub, v_inv, disc);
    update public.coupons set used_count = used_count + 1
    where id = (vc->>'coupon_id')::uuid;
  end if;

  -- Audit (PRD #36)
  insert into public.activity_logs (actor_id, action, target_type, target_id, metadata)
  values (v_user, 'checkout_created', 'subscription', v_sub,
          jsonb_build_object('plan', p.slug, 'period', p_billing_period, 'discount', disc));

  return jsonb_build_object(
    'ok', true,
    'subscription_id', v_sub, 'invoice_id', v_inv, 'payment_id', v_pay,
    'subtotal', base, 'discount', disc, 'total', base - disc);
end;
$$;
