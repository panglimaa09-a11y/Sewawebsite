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
