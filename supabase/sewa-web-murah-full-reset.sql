-- ═══════════════════════════════════════════════════════════════════
-- RESET: hapus objek lama agar file bisa dijalankan ulang dari kondisi
-- apa pun (project baru ATAU project yang gagal di tengah jalan).
-- PERINGATAN: menghapus data lama pada tabel-tabel ini. Hanya gunakan
-- pada project Supabase yang memang masih setup awal.
-- ═══════════════════════════════════════════════════════════════════

-- Storage policies (bucket proofs)
drop policy if exists "proofs: user upload own"    on storage.objects;
drop policy if exists "proofs: user read own or staff" on storage.objects;
drop policy if exists "proofs: user delete own"    on storage.objects;

-- Tabel (urutan tidak penting karena cascade)
drop table if exists
  public.activity_logs, public.media, public.analytics_events, public.analytics,
  public.ticket_messages, public.tickets, public.notifications,
  public.payment_methods, public.payments,
  public.invoice_items, public.invoices,
  public.subscription_items, public.subscriptions,
  public.ssl_certificates, public.domains,
  public.website_sections, public.website_pages, public.website_settings, public.websites,
  public.templates, public.template_categories,
  public.coupon_redemptions, public.coupons,
  public.plan_features, public.plans,
  public.user_roles, public.roles, public.profiles,
  public.system_settings, public.subscription_reminders,
  public.notification_templates, public.automation_runs
cascade;

-- Trigger di auth.users (profil otomatis)
drop trigger if exists on_auth_user_created on auth.users;

-- Fungsi (cascade ikut menghapus trigger/policy yang bergantung)
drop function if exists public.handle_new_user() cascade;
drop function if exists public.auth_uid() cascade;
drop function if exists public.is_staff() cascade;
drop function if exists public.has_role(public.user_role) cascade;
drop function if exists public.owns_website(uuid) cascade;
drop function if exists public.next_invoice_number() cascade;
drop function if exists public.touch_updated_at() cascade;
drop function if exists public.run_subscription_automation() cascade;
drop function if exists public.apply_template(text, jsonb) cascade;
drop function if exists public.validate_coupon(text, uuid, numeric) cascade;
drop function if exists public.create_checkout(uuid, public.billing_period, text) cascade;
drop function if exists public.verify_manual_payment(uuid, text) cascade;
drop function if exists public.notify_admin_new_ticket() cascade;

-- Enum types
drop type if exists
  public.user_role, public.website_status, public.template_status, public.page_status,
  public.billing_period, public.subscription_status, public.payment_status,
  public.invoice_status, public.coupon_type, public.domain_status, public.ssl_status,
  public.ticket_status, public.media_folder, public.section_type, public.notification_channel
cascade;


-- ═══════════════════════════════════════════════════════════════════
-- SKEMA + SEED + AUTOMATION + TEMPLATES + CHECKOUT + PAYMENT MANUAL + STORAGE
-- ═══════════════════════════════════════════════════════════════════


-- ────────────────────────── 00001_schema.sql ──────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- SEWA WEB MURAH — Database Schema + RLS (PRD #41, #42, #44)
-- Multi-tenant SaaS. Setiap user hanya dapat mengakses datanya sendiri:
-- Supabase Auth + PostgreSQL RLS + server-side authorization.
-- Jalankan: supabase db push  (atau jalankan via SQL Editor)
-- ═══════════════════════════════════════════════════════════════════

-- ── Extensions ────────────────────────────────────────────────────
create extension if not exists pgcrypto with schema extensions;

-- ── Enums ─────────────────────────────────────────────────────────
create type public.user_role          as enum ('user','admin','super_admin','support','finance');
create type public.website_status     as enum ('draft','active','payment_due','grace_period','suspended','expired');
create type public.template_status    as enum ('draft','published','archived');
create type public.page_status        as enum ('draft','published');
create type public.billing_period     as enum ('monthly','yearly');
create type public.subscription_status as enum ('trial','active','past_due','cancelled','expired','suspended');
create type public.payment_status     as enum ('pending','paid','failed','refunded','expired');
create type public.invoice_status     as enum ('draft','pending','paid','failed','refunded','cancelled');
create type public.coupon_type        as enum ('percentage','fixed_amount');
create type public.domain_status      as enum ('pending','verifying','active','failed','expired');
create type public.ssl_status         as enum ('pending','issued','expiring','failed','revoked');
create type public.ticket_status      as enum ('open','pending','resolved','closed');
create type public.media_folder       as enum ('images','videos','documents');
create type public.section_type       as enum
  ('hero','text','image','button','gallery','services','products','pricing','testimonials','faq','contact','map','video','social_links','cta','footer');
create type public.notification_channel as enum ('dashboard','email','whatsapp');

-- ═══════════════════════════════════════════════════════════════════
-- HELPER FUNCTIONS (security definer — dipakai kebijakan RLS)
-- ═══════════════════════════════════════════════════════════════════
create or replace function public.auth_uid() returns uuid
language sql stable as $$ select auth.uid() $$;

-- Staff = admin/super_admin/support/finance (PRD #4: role, bukan URL saja)
create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid()
      and r.name in ('admin','super_admin','support','finance')
  );
$$;

create or replace function public.has_role(_role public.user_role) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid() and r.name = _role
  );
$$;

-- Pemilik website (untuk tabel turunan: pages, sections, domains, media, ...)
create or replace function public.owns_website(_website_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.websites w
    where w.id = _website_id and w.user_id = auth.uid()
  );
$$;

-- ═══════════════════════════════════════════════════════════════════
-- IDENTITY: profiles, roles, user_roles (PRD #41)
-- ═══════════════════════════════════════════════════════════════════
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text,
  avatar_url  text,
  phone       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table public.roles (
  id   smallserial primary key,
  name public.user_role not null unique
);

create table public.user_roles (
  user_id  uuid not null references public.profiles(id) on delete cascade,
  role_id  smallint not null references public.roles(id) on delete cascade,
  granted_by uuid references public.profiles(id),
  granted_at timestamptz not null default now(),
  primary key (user_id, role_id)
);
create index on public.user_roles (role_id);

-- Auto-create profile saat user mendaftar via Supabase Auth
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, avatar_url)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1)), new.raw_user_meta_data->>'avatar_url');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ═══════════════════════════════════════════════════════════════════
-- BILLING CATALOG: plans, plan_features, coupons (PRD #8, #22, #27)
-- Harga TIDAK di-hardcode — admin kelola dari /admin/plans
-- ═══════════════════════════════════════════════════════════════════
create table public.plans (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  slug          text not null unique,
  description   text,
  price_monthly numeric(12,2) not null check (price_monthly >= 0),
  price_yearly  numeric(12,2),
  currency      text not null default 'IDR',
  storage_mb    int not null default 1024,
  max_pages     int not null default 10,          -- null = unlimited
  custom_domain boolean not null default false,
  analytics     boolean not null default false,
  seo_tools     boolean not null default false,
  support_level text not null default 'standard',
  is_active     boolean not null default true,
  sort_order    int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table public.plan_features (
  id         uuid primary key default gen_random_uuid(),
  plan_id    uuid not null references public.plans(id) on delete cascade,
  feature    text not null,
  sort_order int not null default 0
);
create index on public.plan_features (plan_id);

create table public.coupons (
  id               uuid primary key default gen_random_uuid(),
  code             text not null unique,
  type             public.coupon_type not null,
  value            numeric(12,2) not null check (value > 0),
  min_payment      numeric(12,2) not null default 0,
  max_usage        int,
  used_count       int not null default 0,
  plan_restriction uuid references public.plans(id),
  starts_at        timestamptz,
  expires_at       timestamptz,
  is_active        boolean not null default true,
  created_by       uuid references public.profiles(id),
  created_at       timestamptz not null default now()
);

-- ═══════════════════════════════════════════════════════════════════
-- TEMPLATE MARKETPLACE (PRD #7, #26)
-- ═══════════════════════════════════════════════════════════════════
create table public.template_categories (
  id   uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique
);

create table public.templates (
  id               uuid primary key default gen_random_uuid(),
  name             text not null,
  slug             text not null unique,
  description      text,
  category_id      uuid references public.template_categories(id),
  thumbnail_url    text,
  preview_url      text,
  required_plan_id uuid references public.plans(id),
  status           public.template_status not null default 'draft',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index on public.templates (category_id, status);

-- ═══════════════════════════════════════════════════════════════════
-- WEBSITES + content (PRD #11-#15, #52) — multi-tenant core
-- ═══════════════════════════════════════════════════════════════════
create table public.websites (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  template_id uuid references public.templates(id),
  name        text not null,
  slug        text not null unique,
  subdomain   text not null unique,               -- {slug}.sewawebmurah.com
  status      public.website_status not null default 'draft',
  theme       jsonb not null default '{}'::jsonb, -- warna, font, logo
  expires_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index on public.websites (user_id);
create index on public.websites (status, expires_at);

create table public.website_settings (
  website_id       uuid primary key references public.websites(id) on delete cascade,
  meta_title       text,
  meta_description text,
  og_image_url     text,
  favicon_url      text,
  canonical_url    text,
  whatsapp_number  text,
  settings         jsonb not null default '{}'::jsonb,
  updated_at       timestamptz not null default now()
);

create table public.website_pages (
  id         uuid primary key default gen_random_uuid(),
  website_id uuid not null references public.websites(id) on delete cascade,
  title      text not null,
  slug       text not null,
  is_home    boolean not null default false,
  status     public.page_status not null default 'draft',
  seo        jsonb not null default '{}'::jsonb,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (website_id, slug)
);
create index on public.website_pages (website_id, status);

-- Editor berbasis block/section (PRD #12)
create table public.website_sections (
  id         uuid primary key default gen_random_uuid(),
  page_id    uuid not null references public.website_pages(id) on delete cascade,
  type       public.section_type not null,
  content    jsonb not null default '{}'::jsonb,  -- teks, gambar, item
  style      jsonb not null default '{}'::jsonb,  -- font, warna, spacing (PRD #13)
  sort_order int not null default 0,
  is_visible boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.website_sections (page_id, sort_order);

-- ═══════════════════════════════════════════════════════════════════
-- DOMAINS + SSL (PRD #16, #31)
-- ═══════════════════════════════════════════════════════════════════
create table public.domains (
  id              uuid primary key default gen_random_uuid(),
  website_id      uuid not null references public.websites(id) on delete cascade,
  domain          text not null unique,
  is_primary      boolean not null default false,
  status          public.domain_status not null default 'pending',
  dns_token       text not null default encode(gen_random_bytes(16),'hex'),
  verified_at     timestamptz,
  last_checked_at timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index on public.domains (website_id);

create table public.ssl_certificates (
  id         uuid primary key default gen_random_uuid(),
  domain_id  uuid not null references public.domains(id) on delete cascade,
  provider   text not null default 'letsencrypt',
  status     public.ssl_status not null default 'pending',
  issued_at  timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

-- ═══════════════════════════════════════════════════════════════════
-- SUBSCRIPTIONS (PRD #19) + INVOICES (PRD #21) + PAYMENTS (PRD #20)
-- ═══════════════════════════════════════════════════════════════════
create table public.subscriptions (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null references public.profiles(id) on delete cascade,
  website_id           uuid references public.websites(id) on delete set null,
  plan_id              uuid not null references public.plans(id),
  coupon_id            uuid references public.coupons(id),
  status               public.subscription_status not null default 'trial',
  billing_period       public.billing_period not null default 'monthly',
  start_date           timestamptz not null default now(),
  current_period_start timestamptz not null default now(),
  current_period_end   timestamptz not null,
  cancel_at_period_end boolean not null default false,
  cancelled_at         timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
create index on public.subscriptions (user_id, status);
create index on public.subscriptions (current_period_end) where status in ('active','trial','past_due');

create table public.subscription_items (
  id              uuid primary key default gen_random_uuid(),
  subscription_id uuid not null references public.subscriptions(id) on delete cascade,
  description     text not null,
  amount          numeric(12,2) not null,
  currency        text not null default 'IDR',
  quantity        int not null default 1
);

create table public.invoices (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id) on delete cascade,
  subscription_id uuid references public.subscriptions(id) on delete set null,
  number          text not null unique,           -- INV-YYYYMM-XXX (dibuat trigger)
  status          public.invoice_status not null default 'draft',
  issue_date      timestamptz not null default now(),
  due_date        timestamptz not null,
  paid_at         timestamptz,
  subtotal        numeric(12,2) not null default 0,
  discount        numeric(12,2) not null default 0,
  total           numeric(12,2) not null default 0,
  currency        text not null default 'IDR',
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index on public.invoices (user_id, status);

create table public.invoice_items (
  id          uuid primary key default gen_random_uuid(),
  invoice_id  uuid not null references public.invoices(id) on delete cascade,
  description text not null,
  quantity    int not null default 1,
  unit_amount numeric(12,2) not null,
  amount      numeric(12,2) not null
);
create index on public.invoice_items (invoice_id);

-- Nomor invoice otomatis: INV-202609-001
create or replace function public.next_invoice_number() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  prefix text := 'INV-' || to_char(now(),'YYYYMM') || '-';
  seq int;
begin
  select coalesce(max(substring(number from '[0-9]+$')::int), 0) + 1 into seq
  from public.invoices where number like prefix || '%';
  new.number := prefix || lpad(seq::text, 3, '0');
  return new;
end;
$$;

create trigger invoice_number_gen
  before insert on public.invoices
  for each row when (new.number is null or new.number = '')
  execute function public.next_invoice_number();

create table public.payments (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id) on delete cascade,
  invoice_id      uuid references public.invoices(id) on delete set null,
  subscription_id uuid references public.subscriptions(id) on delete set null,
  amount          numeric(12,2) not null,
  currency        text not null default 'IDR',
  gateway         text not null default 'midtrans',   -- midtrans | xendit | duitku
  gateway_ref     text unique,                        -- transaction id dari gateway
  payment_method  text,                               -- va_bca, qris, ewallet, ...
  status          public.payment_status not null default 'pending',
  paid_at         timestamptz,
  metadata        jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index on public.payments (user_id, status);
create index on public.payments (gateway_ref);

create table public.payment_methods (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  type       text not null,
  provider   text not null,
  token      text,                                  -- tokenized, bukan data mentah
  label      text,
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.coupon_redemptions (
  id              uuid primary key default gen_random_uuid(),
  coupon_id       uuid not null references public.coupons(id) on delete cascade,
  user_id         uuid not null references public.profiles(id) on delete cascade,
  subscription_id uuid references public.subscriptions(id) on delete set null,
  invoice_id      uuid references public.invoices(id) on delete set null,
  discount_amount numeric(12,2) not null,
  redeemed_at     timestamptz not null default now()
);
create index on public.coupon_redemptions (coupon_id, user_id);

-- ═══════════════════════════════════════════════════════════════════
-- PLATFORM: notifications, tickets, analytics, media, activity_logs
-- (PRD #34, #35, #32, #15, #36)
-- ═══════════════════════════════════════════════════════════════════
create table public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid references public.profiles(id) on delete cascade, -- null = broadcast
  title      text not null,
  body       text,
  type       text not null default 'info',        -- payment_success, payment_failed, d7, d3, d1, ...
  channel    public.notification_channel not null default 'dashboard',
  is_read    boolean not null default false,
  read_at    timestamptz,
  metadata   jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index on public.notifications (user_id, is_read, created_at desc);

create table public.tickets (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  website_id  uuid references public.websites(id) on delete set null,
  subject     text not null,
  category    text not null default 'general',    -- general, billing, technical, domain
  status      public.ticket_status not null default 'open',
  priority    text not null default 'normal',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  resolved_at timestamptz
);
create index on public.tickets (user_id, status);

create table public.ticket_messages (
  id         uuid primary key default gen_random_uuid(),
  ticket_id  uuid not null references public.tickets(id) on delete cascade,
  sender_id  uuid not null references public.profiles(id),
  is_staff   boolean not null default false,
  body       text not null,
  attachments jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);
create index on public.ticket_messages (ticket_id, created_at);

-- Agregat harian (dihitung cron dari analytics_events)
create table public.analytics (
  id             uuid primary key default gen_random_uuid(),
  website_id     uuid not null references public.websites(id) on delete cascade,
  date           date not null,
  visitors       int not null default 0,
  unique_visitors int not null default 0,
  page_views     int not null default 0,
  leads          int not null default 0,
  sources        jsonb not null default '{}'::jsonb,
  top_pages      jsonb not null default '{}'::jsonb,
  devices        jsonb not null default '{}'::jsonb,
  countries      jsonb not null default '{}'::jsonb,
  unique (website_id, date)
);

-- Event mentah — ditulis lewat server route (service role), bukan dari client
create table public.analytics_events (
  id         uuid primary key default gen_random_uuid(),
  website_id uuid not null references public.websites(id) on delete cascade,
  page_id    uuid references public.website_pages(id) on delete set null,
  session_id text,
  event_type text not null default 'pageview',    -- pageview | lead | click
  path       text,
  referrer   text,
  device     text,
  country    text,
  created_at timestamptz not null default now()
);
create index on public.analytics_events (website_id, created_at);

create table public.media (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  website_id uuid references public.websites(id) on delete cascade,
  folder     public.media_folder not null default 'images',
  path       text not null,      -- /user/{user_id}/images/... (PRD #43)
  filename   text not null,
  mime_type  text not null,
  size_bytes bigint not null,
  created_at timestamptz not null default now()
);
create index on public.media (user_id, folder);

create table public.activity_logs (
  id          uuid primary key default gen_random_uuid(),
  actor_id    uuid references public.profiles(id) on delete set null,
  actor_role  text,
  action      text not null,   -- login, payment, plan_change, website_published, admin_action, ...
  target_type text,
  target_id   uuid,
  ip          inet,
  metadata    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);
create index on public.activity_logs (actor_id, created_at desc);

-- ═══════════════════════════════════════════════════════════════════
-- updated_at otomatis
-- ═══════════════════════════════════════════════════════════════════
create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at = now(); return new; end; $$;

do $$
declare t text;
begin
  foreach t in array array['profiles','plans','templates','websites','website_settings',
    'website_pages','website_sections','domains','subscriptions','invoices','payments']
  loop
    execute format('create trigger touch_%s before update on public.%I
      for each row execute function public.touch_updated_at()', t, t);
  end loop;
end $$;

-- ═══════════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY — aktif di SEMUA tabel (PRD #42, #44)
-- Prinsip: default deny → buka hanya yang eksplisit.
-- ═══════════════════════════════════════════════════════════════════
alter table public.profiles            enable row level security;
alter table public.roles               enable row level security;
alter table public.user_roles          enable row level security;
alter table public.plans               enable row level security;
alter table public.plan_features       enable row level security;
alter table public.coupons             enable row level security;
alter table public.coupon_redemptions  enable row level security;
alter table public.template_categories enable row level security;
alter table public.templates           enable row level security;
alter table public.websites            enable row level security;
alter table public.website_settings    enable row level security;
alter table public.website_pages       enable row level security;
alter table public.website_sections    enable row level security;
alter table public.domains             enable row level security;
alter table public.ssl_certificates    enable row level security;
alter table public.subscriptions       enable row level security;
alter table public.subscription_items  enable row level security;
alter table public.invoices            enable row level security;
alter table public.invoice_items       enable row level security;
alter table public.payments            enable row level security;
alter table public.payment_methods     enable row level security;
alter table public.notifications       enable row level security;
alter table public.tickets             enable row level security;
alter table public.ticket_messages     enable row level security;
alter table public.analytics           enable row level security;
alter table public.analytics_events    enable row level security;
alter table public.media               enable row level security;
alter table public.activity_logs       enable row level security;

-- ── profiles ──
create policy "profiles: read own or staff" on public.profiles
  for select using (id = auth_uid() or public.is_staff());
create policy "profiles: update own" on public.profiles
  for update using (id = auth_uid());
create policy "profiles: staff update" on public.profiles
  for update using (public.is_staff());

-- ── roles: hanya staff yang boleh melihat ──
create policy "roles: staff read" on public.roles
  for select using (public.is_staff());
create policy "user_roles: staff read" on public.user_roles
  for select using (user_id = auth_uid() or public.is_staff());
-- Pemberian role HANYA via service role / dashboard admin — tidak ada policy insert untuk client.

-- ── plans & features: publik boleh baca yang aktif, staff full ──
create policy "plans: public read active" on public.plans
  for select using (is_active or public.is_staff());
create policy "plans: staff write" on public.plans
  for all using (public.is_staff()) with check (public.is_staff());
create policy "plan_features: public read" on public.plan_features
  for select using (
    exists (select 1 from public.plans p where p.id = plan_id and (p.is_active or public.is_staff()))
  );
create policy "plan_features: staff write" on public.plan_features
  for all using (public.is_staff()) with check (public.is_staff());

-- ── coupons: kode divalidasi server-side; client hanya staff ──
create policy "coupons: staff all" on public.coupons
  for all using (public.is_staff()) with check (public.is_staff());
create policy "coupon_redemptions: owner or staff" on public.coupon_redemptions
  for select using (user_id = auth_uid() or public.is_staff());

-- ── templates: publik baca yang published; staff kelola (PRD #26) ──
create policy "templates: public read published" on public.templates
  for select using (status = 'published' or public.is_staff());
create policy "templates: staff write" on public.templates
  for all using (public.is_staff()) with check (public.is_staff());
create policy "template_categories: public read" on public.template_categories
  for select using (true);
create policy "template_categories: staff write" on public.template_categories
  for all using (public.is_staff()) with check (public.is_staff());

-- ── websites: pemilik penuh, staff kelola (PRD #42: USER A ≠ WEBSITE B) ──
create policy "websites: owner or staff" on public.websites
  for all using (user_id = auth_uid() or public.is_staff())
  with check (user_id = auth_uid() or public.is_staff());

create policy "website_settings: owner or staff" on public.website_settings
  for all using (public.owns_website(website_id) or public.is_staff())
  with check (public.owns_website(website_id) or public.is_staff());

create policy "website_pages: owner or staff" on public.website_pages
  for all using (public.owns_website(website_id) or public.is_staff())
  with check (public.owns_website(website_id) or public.is_staff());

create policy "website_sections: owner or staff" on public.website_sections
  for all using (
    exists (select 1 from public.website_pages p where p.id = page_id
            and (public.owns_website(p.website_id) or public.is_staff()))
  ) with check (
    exists (select 1 from public.website_pages p where p.id = page_id
            and (public.owns_website(p.website_id) or public.is_staff()))
  );

create policy "domains: owner or staff" on public.domains
  for all using (public.owns_website(website_id) or public.is_staff())
  with check (public.owns_website(website_id) or public.is_staff());

create policy "ssl_certificates: owner or staff" on public.ssl_certificates
  for select using (
    exists (select 1 from public.domains d join public.websites w on w.id = d.website_id
            where d.id = domain_id and (w.user_id = auth_uid() or public.is_staff()))
  );
-- Verifikasi SSL ditulis oleh cron/service role.

-- ── billing: pemilik baca; mutasi via service role (webhook terverifikasi) ──
create policy "subscriptions: owner or staff read" on public.subscriptions
  for select using (user_id = auth_uid() or public.is_staff());
create policy "subscription_items: owner or staff read" on public.subscription_items
  for select using (
    exists (select 1 from public.subscriptions s
            where s.id = subscription_id and (s.user_id = auth_uid() or public.is_staff()))
  );

create policy "invoices: owner or staff read" on public.invoices
  for select using (user_id = auth_uid() or public.is_staff());
create policy "invoice_items: owner or staff read" on public.invoice_items
  for select using (
    exists (select 1 from public.invoices i
            where i.id = invoice_id and (i.user_id = auth_uid() or public.is_staff()))
  );

create policy "payments: owner or staff read" on public.payments
  for select using (user_id = auth_uid() or public.is_staff());
create policy "payment_methods: owner" on public.payment_methods
  for all using (user_id = auth_uid()) with check (user_id = auth_uid());

-- Status pembayaran TIDAK pernah diubah dari client — hanya webhook terverifikasi
-- lewat service role (PRD #20: validasi pembayaran server-side).

-- ── notifications: milik user (broadcast staff-only) ──
create policy "notifications: own or broadcast read" on public.notifications
  for select using (user_id = auth_uid() or (user_id is null and public.is_staff()));
create policy "notifications: mark own read" on public.notifications
  for update using (user_id = auth_uid()) with check (user_id = auth_uid());
create policy "notifications: staff write" on public.notifications
  for insert with check (public.is_staff());

-- ── support tickets (PRD #35) ──
create policy "tickets: owner or support staff" on public.tickets
  for all using (user_id = auth_uid() or public.is_staff())
  with check (user_id = auth_uid() or public.is_staff());
create policy "ticket_messages: participant or staff" on public.ticket_messages
  for all using (
    public.is_staff() or
    exists (select 1 from public.tickets t
            where t.id = ticket_id and (t.user_id = auth_uid() or sender_id = auth_uid()))
  ) with check (
    public.is_staff() or
    exists (select 1 from public.tickets t
            where t.id = ticket_id and (t.user_id = auth_uid() or sender_id = auth_uid()))
  );

-- ── analytics: pemilik baca; event ditulis service role ──
create policy "analytics: owner or staff read" on public.analytics
  for select using (public.owns_website(website_id) or public.is_staff());
create policy "analytics: staff write" on public.analytics
  for all using (public.is_staff()) with check (public.is_staff());
create policy "analytics_events: owner or staff read" on public.analytics_events
  for select using (public.owns_website(website_id) or public.is_staff());

-- ── media: pemilik (PRD #43: /user/{user_id}/...) ──
create policy "media: owner or staff" on public.media
  for all using (user_id = auth_uid() or public.is_staff())
  with check (user_id = auth_uid() or public.is_staff());

-- ── activity logs: staff baca; tulis hanya service role (PRD #36, #44 audit) ──
create policy "activity_logs: staff read" on public.activity_logs
  for select using (public.is_staff());

-- ═══════════════════════════════════════════════════════════════════
-- STORAGE (PRD #43): bucket per kategori + path /user/{user_id}/...
-- Jalankan manual di dashboard Storage atau via script admin.
-- ═══════════════════════════════════════════════════════════════════
-- Bucket: user-media (public read), templates (public read), backups (private)
-- Policy storage.objects (contoh bucket user-media):
--   insert: bucket_id='user-media' and (storage.foldername(name))[1] = auth.uid()::text
--   select: idem + staff; update/delete: idem
-- Batas file: gambar ≤ 5MB, video ≤ 100MB, dokumen ≤ 10MB (validasi di server route).


-- ────────────────────────── 00002_seed.sql ──────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- SEED — roles, paket (PRD #8), kategori & template contoh (PRD #7)
-- Harga di sini = nilai awal; admin bisa mengubahnya dari /admin/plans
-- ═══════════════════════════════════════════════════════════════════
insert into public.roles (name) values
  ('user'), ('admin'), ('super_admin'), ('support'), ('finance')
on conflict (name) do nothing;

-- ── Paket ──
insert into public.plans (name, slug, description, price_monthly, price_yearly, storage_mb, max_pages, custom_domain, analytics, seo_tools, support_level, sort_order) values
  ('Starter',  'starter',  'Untuk memulai kehadiran online',        49000,  490000,  1024,  5,   false, false, false, 'standard', 1),
  ('Business', 'business', 'Untuk bisnis yang serius online',       99000,  990000,  5120,  null, true,  true,  true,  'standard', 2),
  ('Pro',      'pro',      'Untuk kebutuhan lanjutan',             199000, 1990000, 15360,  null, true,  true,  true,  'priority', 3)
on conflict (slug) do nothing;

insert into public.plan_features (plan_id, feature, sort_order)
select p.id, f.feature, f.ord
from public.plans p
join (values
  ('starter',  '1 Website', 1),
  ('starter',  'Subdomain sewawebmurah.com', 2),
  ('starter',  'SSL & Hosting termasuk', 3),
  ('starter',  'Template Basic', 4),
  ('starter',  'Basic Editor & Analytics', 5),
  ('business', '1 Website + Custom Domain', 1),
  ('business', 'Premium Template', 2),
  ('business', 'Unlimited Pages & SEO Tools', 3),
  ('business', 'Analytics + Tombol WhatsApp', 4),
  ('business', 'Contact Form & Media Manager', 5),
  ('business', 'Backup otomatis', 6),
  ('pro',      'Semua fitur Business', 1),
  ('pro',      'Advanced Editor & Custom Sections', 2),
  ('pro',      'Advanced Analytics', 3),
  ('pro',      'Advanced Integrations', 4),
  ('pro',      'Priority Support', 5)
) as f(slug, feature, ord) on f.slug = p.slug;

-- ── Kategori template (PRD #6/#7) ──
insert into public.template_categories (name, slug) values
  ('UMKM','umkm'), ('Restaurant','restaurant'), ('Toko','toko'),
  ('Portfolio','portfolio'), ('Company Profile','company-profile'), ('Agency','agency'),
  ('Personal Brand','personal-brand'), ('Event','event'), ('Jasa','jasa'),
  ('Sekolah','sekolah'), ('Landing Page','landing-page')
on conflict (slug) do nothing;

-- ── Template contoh (status published; ganti thumbnail/preview via /admin/templates) ──
insert into public.templates (name, slug, description, category_id, required_plan_id, status)
select v.name, v.slug, v.descr, c.id, p.id, 'published'
from (values
  ('Restaurant Pro',     'restaurant-pro',     'Template restoran lengkap dengan menu, galeri, dan reservasi.', 'restaurant',      'business'),
  ('Toko UMKM',          'toko-umkm',          'Showcase produk UMKM dengan tombol WhatsApp dan katalog.',      'toko',            'starter'),
  ('Portfolio Kreatif',  'portfolio-kreatif',  'Portfolio minimalis untuk kreator, desainer, dan fotografer.',  'portfolio',       'business'),
  ('Company Sejahtera',  'company-sejahtera',  'Company profile korporat dengan layanan dan testimoni.',        'company-profile', 'pro'),
  ('Agency Bold',        'agency-bold',        'Landing page agency modern dengan showcase karya.',             'agency',          'pro'),
  ('Jasa & Servis',      'jasa-servis',        'Template jasa dengan daftar layanan, harga, dan kontak.',       'jasa',            'starter')
) as v(name, slug, descr, cat_slug, plan_slug)
left join public.template_categories c on c.slug = v.cat_slug
left join public.plans p on p.slug = v.plan_slug
on conflict (slug) do nothing;

-- ── Coupon contoh (PRD #22) ──
insert into public.coupons (code, type, value, max_usage, expires_at)
values
  ('WELCOME50',  'percentage',    50, 1000, now() + interval '90 days'),
  ('NEWUSER',    'fixed_amount', 25000, 500, now() + interval '90 days'),
  ('BUSINESS10', 'percentage',    10, null, now() + interval '30 days')
on conflict (code) do nothing;


-- ────────────────────────── 00003_automation.sql ──────────────────────────

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


-- ────────────────────────── 00004_notification_templates.sql ──────────────────────────

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


-- ────────────────────────── 00005_checkout.sql ──────────────────────────

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


-- ────────────────────────── 00006_manual_payment.sql ──────────────────────────

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


-- ────────────────────────── 00007_proof_storage.sql ──────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- STORAGE: bucket bukti pembayaran (PRD #43, #20)
--
-- Bucket 'proofs' (private) — path: {user_id}/{timestamp}-{namafile}
-- Validasi: tipe image (png/jpg/webp), maks 5MB — di-enforce di bucket
-- DAN di client upload; path user di-enforce oleh RLS storage policy.
-- Staff membaca semua bukti untuk verifikasi manual (PRD #20).
-- ═══════════════════════════════════════════════════════════════════

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('proofs', 'proofs', false, 5242880,
        array['image/png','image/jpeg','image/webp'])
on conflict (id) do nothing;

-- ── RLS storage.objects ──
-- Upload: hanya ke folder sendiri ({user_id}/...)
create policy "proofs: user upload own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'proofs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Baca: folder sendiri, atau staff (verifikasi bukti)
create policy "proofs: user read own or staff" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'proofs'
    and ((storage.foldername(name))[1] = auth.uid()::text or public.is_staff())
  );

-- Hapus: folder sendiri (ganti file salah upload)
create policy "proofs: user delete own" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'proofs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

