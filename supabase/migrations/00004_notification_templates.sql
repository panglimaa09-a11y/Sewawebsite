-- ═══════════════════════════════════════════════════════════════════
-- NOTIFICATION TEMPLATES + EMAIL PROVIDER (PRD #34, #39)
-- Admin mengelola dari /admin/settings. Engine (PRD #38/#45) memakai
-- template ini lewat apply_template() — teks tidak lagi hardcoded.
-- ═══════════════════════════════════════════════════════════════════

-- ── Kolom email provider di system_settings ───────────────────────
-- Kredensial rahasia (API key / SMTP password) TIDAK disimpan di DB —
-- tetap di environment variable (PRD #44: secret management).
alter table public.system_settings
  add column if not exists email_provider_name text not null default 'none', -- none | resend | smtp
  add column if not exists email_from          text,
  add column if not exists email_reply_to      text;

-- ── Tabel template notifikasi ─────────────────────────────────────
create table public.notification_templates (
  id         uuid primary key default gen_random_uuid(),
  kind       text not null unique,     -- payment_success | subscription_ending | payment_due | website_suspended | subscription_expired | support_reply
  channel    public.notification_channel not null default 'dashboard',
  subject    text not null,
  body       text not null,             -- mendukung {{variabel}}
  variables  jsonb not null default '[]'::jsonb,  -- dokumentasi variabel tersedia
  is_active  boolean not null default true,
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now()
);

alter table public.notification_templates enable row level security;
create policy "notification_templates: staff all" on public.notification_templates
  for all using (public.is_staff()) with check (public.is_staff());

-- ── Seed template (PRD #34 + #38) ─────────────────────────────────
insert into public.notification_templates (kind, channel, subject, body, variables) values
('payment_success','dashboard',
 'Pembayaran Berhasil',
 'Halo {{nama}}, pembayaran sebesar {{jumlah}} untuk invoice {{invoice}} telah kami terima. Website {{website}} aktif hingga {{tanggal}}.',
 '["nama","jumlah","invoice","website","tanggal"]'),
('subscription_ending','dashboard',
 'Langganan berakhir dalam {{jumlah_hari}} hari',
 'Website {{website}} akan berakhir pada {{tanggal_jatuh_tempo}}. Perpanjang sekarang agar tetap online.',
 '["nama","website","jumlah_hari","tanggal_jatuh_tempo"]'),
('payment_due','dashboard',
 'Pembayaran diperlukan',
 'Masa langganan {{website}} telah berakhir pada {{tanggal_jatuh_tempo}}. Website masih aktif sementara selama masa tenggang {{grace_hari}} hari. Segera lakukan pembayaran.',
 '["nama","website","tanggal_jatuh_tempo","grace_hari"]'),
('website_suspended','dashboard',
 'Website disuspend',
 'Masa tenggang untuk {{website}} telah berakhir. Website sementara tidak dapat diakses. Selesaikan pembayaran untuk mengaktifkan kembali.',
 '["nama","website"]'),
('subscription_expired','dashboard',
 'Langganan berakhir',
 'Langganan {{website}} telah berakhir. Data website Anda tetap disimpan sesuai kebijakan retensi.',
 '["nama","website"]'),
('support_reply','dashboard',
 'Balasan baru pada tiket {{tiket}}',
 'Tim support membalas tiket "{{subjek}}". Buka dashboard untuk membaca balasan.',
 '["nama","tiket","subjek"]')
on conflict (kind) do nothing;

-- ═══════════════════════════════════════════════════════════════════
-- apply_template(kind, vars) — render subject/body dari template aktif.
-- Dipakai engine automation & webhook pembayaran. Return NULL jika
-- template tidak ada/nonaktif → pemanggil fallback ke teks default.
-- ═══════════════════════════════════════════════════════════════════
create or replace function public.apply_template(
  p_kind text,
  p_vars jsonb default '{}'::jsonb
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  t record;
  s text;
  b text;
  k text;
  v text;
begin
  select * into t from public.notification_templates nt
    where nt.kind = p_kind and nt.is_active limit 1;
  if not found then
    return null;
  end if;

  s := t.subject;
  b := t.body;
  for k, v in select * from jsonb_each_text(p_vars) loop
    s := replace(s, '{{' || k || '}}', coalesce(v, '-'));
    b := replace(b, '{{' || k || '}}', coalesce(v, '-'));
  end loop;

  return jsonb_build_object('subject', s, 'body', b, 'channel', t.channel);
end;
$$;

-- ═══════════════════════════════════════════════════════════════════
-- UPGRADE ENGINE: run_subscription_automation kini memakai template
-- (create or replace — menggantikan versi 00003 dengan fallback teks
-- default bila template nonaktif/tidak ada).
-- ═══════════════════════════════════════════════════════════════════
create or replace function public.run_subscription_automation() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cfg          record;
  tpl          jsonb;
  run_id       uuid;
  r            record;
  n_reminders  int := 0;
  n_dues       int := 0;
  n_suspended  int := 0;
  n_expired    int := 0;
  errs         jsonb := '[]'::jsonb;
  target_date  int;
  rkey         text;
  v_nama       text;
  v_website    text;
begin
  select * into cfg from public.system_settings limit 1;
  insert into public.automation_runs default values returning id into run_id;

  -- 1. REMINDERS D-7 / D-3 / D-1 (angka dari cfg.reminder_days, PRD #38)
  foreach target_date in array cfg.reminder_days loop
    for r in
      select s.id, s.user_id, s.website_id, s.current_period_end
      from public.subscriptions s
      where s.status in ('active','trial')
        and s.current_period_end::date = (now() + (target_date || ' days')::interval)::date
    loop
      rkey := 'd' || target_date || '-' || to_char(r.current_period_end, 'YYYYMMDD');
      insert into public.subscription_reminders (subscription_id, website_id, reminder_key, kind, period_end)
      values (r.id, r.website_id, rkey, 'd' || target_date, r.current_period_end::date)
      on conflict (subscription_id, reminder_key) do nothing;

      if found then
        select full_name into v_nama from public.profiles where id = r.user_id;
        select coalesce(subdomain, name) into v_website from public.websites where id = r.website_id;
        tpl := public.apply_template('subscription_ending', jsonb_build_object(
          'nama', v_nama, 'website', v_website, 'jumlah_hari', target_date,
          'tanggal_jatuh_tempo', to_char(r.current_period_end, 'DD Mon YYYY')));
        insert into public.notifications (user_id, title, body, type, channel)
        values (
          r.user_id,
          coalesce(tpl->>'subject', 'Langganan berakhir dalam ' || target_date || ' hari'),
          coalesce(tpl->>'body',
            'Perpanjang sekarang agar website Anda tetap online. Jatuh tempo: ' ||
            to_char(r.current_period_end, 'DD Mon YYYY') || '.'),
          'subscription_ending_d' || target_date,
          coalesce(tpl->>'channel', 'dashboard')
        );
        n_reminders := n_reminders + 1;
      end if;
    end loop;
  end loop;

  -- 2. DUE (D+0): past_due + website payment_due
  for r in
    update public.subscriptions s
    set status = 'past_due', updated_at = now()
    where s.status in ('active','trial') and s.current_period_end < now()
    returning s.id, s.user_id, s.website_id
  loop
    if r.website_id is not null then
      update public.websites set status = 'payment_due', updated_at = now()
      where id = r.website_id and status = 'active';
    end if;
    insert into public.subscription_reminders (subscription_id, website_id, reminder_key, kind, period_end)
    values (r.id, r.website_id, 'due-' || to_char(now(),'YYYYMMDD'), 'due', current_date)
    on conflict (subscription_id, reminder_key) do nothing;
    if found then
      select full_name into v_nama from public.profiles where id = r.user_id;
      select coalesce(subdomain, name) into v_website from public.websites where id = r.website_id;
      tpl := public.apply_template('payment_due', jsonb_build_object(
        'nama', v_nama, 'website', v_website,
        'tanggal_jatuh_tempo', to_char(now(), 'DD Mon YYYY'),
        'grace_hari', cfg.grace_period_days));
      insert into public.notifications (user_id, title, body, type, channel)
      values (
        r.user_id,
        coalesce(tpl->>'subject', 'Pembayaran diperlukan'),
        coalesce(tpl->>'body', 'Masa langganan Anda telah berakhir. Website masih aktif sementara.'),
        'payment_due',
        coalesce(tpl->>'channel', 'dashboard')
      );
      n_dues := n_dues + 1;
    end if;
  end loop;

  -- 3. SUSPENDED: lewat masa tenggang
  for r in
    update public.subscriptions s
    set status = 'suspended', updated_at = now()
    where s.status = 'past_due'
      and s.current_period_end < now() - (cfg.grace_period_days || ' days')::interval
    returning s.id, s.user_id, s.website_id
  loop
    if r.website_id is not null then
      update public.websites set status = 'suspended', updated_at = now()
      where id = r.website_id and status in ('active','payment_due');
    end if;
    insert into public.subscription_reminders (subscription_id, website_id, reminder_key, kind, period_end)
    values (r.id, r.website_id, 'grace-' || to_char(now(),'YYYYMMDD'), 'grace', current_date)
    on conflict (subscription_id, reminder_key) do nothing;
    if found then
      select full_name into v_nama from public.profiles where id = r.user_id;
      select coalesce(subdomain, name) into v_website from public.websites where id = r.website_id;
      tpl := public.apply_template('website_suspended', jsonb_build_object('nama', v_nama, 'website', v_website));
      insert into public.notifications (user_id, title, body, type, channel)
      values (
        r.user_id,
        coalesce(tpl->>'subject', 'Website disuspend'),
        coalesce(tpl->>'body', 'Masa tenggang telah berakhir. Selesaikan pembayaran untuk mengaktifkan kembali.'),
        'website_suspended',
        coalesce(tpl->>'channel', 'dashboard')
      );
      n_suspended := n_suspended + 1;
    end if;
  end loop;

  -- 4. EXPIRED: lewat tenggang + expire_after_days (data disimpan, PRD #17)
  for r in
    update public.subscriptions s
    set status = 'expired', cancelled_at = now(), updated_at = now()
    where s.status = 'suspended'
      and s.current_period_end < now() - ((cfg.grace_period_days + cfg.expire_after_days) || ' days')::interval
    returning s.id, s.user_id, s.website_id
  loop
    if r.website_id is not null then
      update public.websites set status = 'expired', updated_at = now()
      where id = r.website_id and status = 'suspended';
    end if;
    insert into public.subscription_reminders (subscription_id, website_id, reminder_key, kind, period_end)
    values (r.id, r.website_id, 'expired-' || to_char(now(),'YYYYMMDD'), 'expired', current_date)
    on conflict (subscription_id, reminder_key) do nothing;
    if found then
      select full_name into v_nama from public.profiles where id = r.user_id;
      select coalesce(subdomain, name) into v_website from public.websites where id = r.website_id;
      tpl := public.apply_template('subscription_expired', jsonb_build_object('nama', v_nama, 'website', v_website));
      insert into public.notifications (user_id, title, body, type, channel)
      values (
        r.user_id,
        coalesce(tpl->>'subject', 'Langganan berakhir'),
        coalesce(tpl->>'body', 'Data website Anda tetap disimpan sesuai kebijakan retensi.'),
        'subscription_expired',
        coalesce(tpl->>'channel', 'dashboard')
      );
      n_expired := n_expired + 1;
    end if;
  end loop;

  -- 5. Audit (PRD #36)
  insert into public.activity_logs (action, target_type, target_id, metadata)
  values ('automation_run', 'automation_run', run_id,
          jsonb_build_object('reminders', n_reminders, 'dues', n_dues,
                             'suspended', n_suspended, 'expired', n_expired));

  update public.automation_runs
  set finished_at = now(), reminders_sent = n_reminders, dues_marked = n_dues,
      suspended = n_suspended, expired = n_expired, errors = errs
  where id = run_id;

  return jsonb_build_object('run_id', run_id, 'reminders', n_reminders,
    'dues', n_dues, 'suspended', n_suspended, 'expired', n_expired);
end;
$$;
