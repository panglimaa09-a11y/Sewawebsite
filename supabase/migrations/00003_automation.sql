-- ═══════════════════════════════════════════════════════════════════
-- AUTOMATION ENGINE (PRD #38, #45) — reminder perpanjangan & lifecycle
--
-- Alur (PRD #45):
--   CHECK SUBSCRIPTIONS → CHECK EXPIRATION → SEND REMINDER
--   → CHECK PAYMENT → SUSPEND EXPIRED WEBSITE → UPDATE STATUS
--
-- Reminder D-7 / D-3 / D-1 (PRD #38) — SEMUA ANGKA DIKONFIGURASI ADMIN
-- lewat tabel system_settings (PRD #39), bukan hardcoded.
--
-- IDEMPOTENT: aman dijalankan berulang — reminder dicatat di
-- subscription_reminders dengan unique key, status transisi hanya
-- bergerak maju dan tidak pernah memproses ulang baris yang sama.
-- ═══════════════════════════════════════════════════════════════════

-- ── System settings (PRD #39) ─────────────────────────────────────
create table public.system_settings (
  id                       uuid primary key default gen_random_uuid(),
  platform_name            text not null default 'Sewa Web Murah',
  logo_url                 text,
  favicon_url              text,
  currency                 text not null default 'IDR',
  timezone                 text not null default 'Asia/Jakarta',
  support_email            text,
  support_whatsapp         text,
  payment_gateway          text not null default 'midtrans',
  email_provider           text,
  default_plan_id          uuid references public.plans(id),
  -- PRD #38: reminder & grace — diubah admin dari /admin/settings
  reminder_days            int[] not null default '{7,3,1}',   -- D-7, D-3, D-1
  grace_period_days        int not null default 3,             -- D+3 → suspended
  expire_after_days        int not null default 14,            -- grace + 14 → expired
  registration_enabled     boolean not null default true,
  maintenance_mode         boolean not null default false,     -- PRD #40
  updated_at               timestamptz not null default now()
);

alter table public.system_settings enable row level security;
create policy "system_settings: staff all" on public.system_settings
  for all using (public.is_staff()) with check (public.is_staff());
-- Nilai non-rahasia (platform_name, maintenance_mode) dibaca publik:
create policy "system_settings: public read" on public.system_settings
  for select using (true);

-- Satu baris setting aktif
insert into public.system_settings (id) values ('00000000-0000-0000-0000-000000000000')
on conflict (id) do nothing;

-- ── Log reminder (kunci idempotensi) ──────────────────────────────
create table public.subscription_reminders (
  id              uuid primary key default gen_random_uuid(),
  subscription_id uuid not null references public.subscriptions(id) on delete cascade,
  website_id      uuid references public.websites(id) on delete cascade,
  reminder_key    text not null,           -- contoh: 'd7-20261025' (jenis + tanggal periode)
  kind            text not null,           -- d7 | d3 | d1 | due | grace | expired
  period_end      date not null,
  sent_at         timestamptz not null default now(),
  unique (subscription_id, reminder_key)
);
alter table public.subscription_reminders enable row level security;
-- Tulis hanya oleh engine (security definer / service role), baca oleh staff:
create policy "subscription_reminders: staff read" on public.subscription_reminders
  for select using (public.is_staff());

-- Log eksekusi engine
create table public.automation_runs (
  id           uuid primary key default gen_random_uuid(),
  started_at   timestamptz not null default now(),
  finished_at  timestamptz,
  reminders_sent int not null default 0,
  dues_marked    int not null default 0,
  suspended      int not null default 0,
  expired        int not null default 0,
  errors         jsonb not null default '[]'::jsonb
);
alter table public.automation_runs enable row level security;
create policy "automation_runs: staff read" on public.automation_runs
  for select using (public.is_staff());

-- ═══════════════════════════════════════════════════════════════════
-- ENGINE — satu fungsi, dipanggil cron harian
-- ═══════════════════════════════════════════════════════════════════
create or replace function public.run_subscription_automation() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cfg          record;
  run_id       uuid;
  r            record;
  n_reminders  int := 0;
  n_dues       int := 0;
  n_suspended  int := 0;
  n_expired    int := 0;
  errs         jsonb := '[]'::jsonb;
  target_date  date;
  rkey         text;
begin
  select * into cfg from public.system_settings limit 1;

  insert into public.automation_runs default values returning id into run_id;

  -- ── 1. REMINDERS: D-7 / D-3 / D-1 (PRD #38) ─────────────────────
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
        insert into public.notifications (user_id, title, body, type, channel)
        values (
          r.user_id,
          'Langganan berakhir dalam ' || target_date || ' hari',
          'Perpanjang sekarang agar website Anda tetap online. Jatuh tempo: ' ||
            to_char(r.current_period_end, 'DD Mon YYYY') || '.',
          'subscription_ending_d' || target_date,
          'dashboard'
        );
        -- TODO kanal email/WhatsApp: kirim via provider (email_provider settings)
        n_reminders := n_reminders + 1;
      end if;
    end loop;
  end loop;

  -- ── 2. DUE: periode berakhir hari ini → past_due + website payment_due ──
  for r in
    update public.subscriptions s
    set status = 'past_due', updated_at = now()
    where s.status in ('active','trial')
      and s.current_period_end < now()
    returning s.id, s.user_id, s.website_id
  loop
    if r.website_id is not null then
      update public.websites set status = 'payment_due', updated_at = now()
      where id = r.website_id and status = 'active';   -- PRD #17: masih aktif sementara
    end if;
    insert into public.subscription_reminders (subscription_id, website_id, reminder_key, kind, period_end)
    values (r.id, r.website_id, 'due-' || to_char(now(),'YYYYMMDD'), 'due', current_date)
    on conflict (subscription_id, reminder_key) do nothing;
    if found then
      insert into public.notifications (user_id, title, body, type, channel)
      values (r.user_id, 'Pembayaran diperlukan',
              'Masa langganan Anda telah berakhir. Website masih aktif sementara selama masa tenggang.',
              'payment_due', 'dashboard');
      n_dues := n_dues + 1;
    end if;
  end loop;

  -- ── 3. SUSPENDED: lewat masa tenggang (PRD #17: website tidak bisa diakses normal) ──
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
      insert into public.notifications (user_id, title, body, type, channel)
      values (r.user_id, 'Website disuspend',
              'Masa tenggang telah berakhir. Selesaikan pembayaran untuk mengaktifkan kembali website Anda.',
              'website_suspended', 'dashboard');
      n_suspended := n_suspended + 1;
    end if;
  end loop;

  -- ── 4. EXPIRED: lewat tenggang + expire_after_days (data disimpan — retention, PRD #17) ──
  for r in
    update public.subscriptions s
    set status = 'expired', cancelled_at = now(), updated_at = now()
    where s.status = 'suspended'
      and s.current_period_end < now() - ((cfg.grace_period_days + cfg.expire_after_days) || ' days')::interval
    returning s.id, s.user_id, s.website_id
  loop
    if r.website_id is not null then
      -- Website DINONAKTIFKAN, bukan dihapus (PRD #17)
      update public.websites set status = 'expired', updated_at = now()
      where id = r.website_id and status = 'suspended';
    end if;
    insert into public.subscription_reminders (subscription_id, website_id, reminder_key, kind, period_end)
    values (r.id, r.website_id, 'expired-' || to_char(now(),'YYYYMMDD'), 'expired', current_date)
    on conflict (subscription_id, reminder_key) do nothing;
    if found then
      insert into public.notifications (user_id, title, body, type, channel)
      values (r.user_id, 'Langganan berakhir',
              'Data website Anda tetap disimpan sesuai kebijakan retensi.',
              'subscription_expired', 'dashboard');
      n_expired := n_expired + 1;
    end if;
  end loop;

  -- ── 5. Audit (PRD #36) ──
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

-- ═══════════════════════════════════════════════════════════════════
-- PENJADWALAN — dua opsi, pilih salah satu (atau keduanya):
--
-- OPSI A — pg_cron di Supabase (aktifkan extension pg_cron di dashboard):
--   create extension if not exists pg_cron;
--   select cron.schedule('swm-automation', '5 2 * * *',
--     $$ select public.run_subscription_automation(); $$);
--   (02:05 UTC ≈ 09:05 WIB — jam sebelum jam sibuk)
--
-- OPSI B — cron eksternal (Vercel Cron / GitHub Actions) memanggil
--   GET /api/cron/automation dengan header Authorization: Bearer CRON_SECRET
--   (lihat src/app/api/cron/automation/route.ts + vercel.json)
--
-- Jalankan ulang aman: fungsi idempoten (unique subscription_reminders).
-- ═══════════════════════════════════════════════════════════════════
