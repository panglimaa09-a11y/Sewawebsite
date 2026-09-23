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
