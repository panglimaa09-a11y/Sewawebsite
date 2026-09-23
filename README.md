# Sewa Web Murah — Next.js + Supabase SaaS

Multi-tenant website-rental SaaS sesuai PRD (64 bagian). Kerangka ini mencakup
**Phase 1 (Foundation)** — auth, database, RLS, middleware, role — plus kerangka
rute Phase 2–5 yang siap diisi.

## Setup

```bash
cp .env.example .env.local   # isi kredensial Supabase & payment gateway
npm install
npx supabase login
npx supabase link --project-ref <ref>
npx supabase db push         # jalankan migrations: schema + RLS + seed
npm run db:types             # generate tipe database lengkap
npm run dev
```

## Struktur

- `supabase/migrations/00001_schema.sql` — 27 tabel (PRD #41), trigger, helper
  `is_staff()/has_role()/owns_website()`, RLS di SEMUA tabel (PRD #42, #44)
- `supabase/migrations/00002_seed.sql` — roles, 3 paket (Starter/Business/Pro),
  11 kategori template, 6 template contoh, 3 coupon
- `src/lib/auth.ts` — `requireUser` / `requireStaff` / `requireRole` (server-side)
- `middleware.ts` — refresh session + proteksi `/app/*` dan `/admin/*`
- `src/app/api/webhooks/payment/route.ts` — webhook terverifikasi signature,
  idempotent; update payment → invoice → subscription → website (PRD #20)

## Aturan keamanan (PRD #44)

- Service role key hanya di server (`src/lib/supabase/admin.ts` — `server-only`)
- Mutasi billing HANYA via webhook service role — client tidak punya policy insert
- `analytics_events` ditulis service role; `activity_logs` dibaca staff saja
- RLS default-deny; policy eksplisit per tabel

## Roadmap fase berikutnya (PRD #62)

Phase 3: dashboard user + editor block. Phase 4: integrasi gateway + cron renewal
(PRD #38 D-7/D-3/D-1). Phase 5: isi halaman admin. Phase 6: custom domain,
AI builder (PRD #46–#47).

## Automation Engine (PRD #38, #45)

Migrasi `00003_automation.sql` menambahkan:

- `system_settings` — reminder_days `{7,3,1}`, grace_period_days, expire_after_days
  (semua diubah admin dari /admin/settings, tidak hardcoded)
- `run_subscription_automation()` — engine idempoten:
  D-7/D-3/D-1 reminder → D+0 `past_due` + website `payment_due`
  → lewat grace `suspended` → lewat retensi `expired` (data disimpan, PRD #17)
- `subscription_reminders` (unique key) — jaminan tidak ada notifikasi ganda
- `automation_runs` + audit `activity_logs`

Dua opsi penjadwalan (pilih salah satu):

1. **pg_cron Supabase** — aktifkan extension lalu:
   `select cron.schedule('swm-automation','5 2 * * *', $$ select public.run_subscription_automation(); $$);`
2. **Vercel Cron** — sudah terkonfigurasi di `vercel.json`, memanggil
   `GET /api/cron/automation` dengan header `Authorization: Bearer $CRON_SECRET`
   (set `CRON_SECRET` di `.env.local`).

## Admin Settings & Template Notifikasi (PRD #34, #39)

Migrasi `00004_notification_templates.sql` menambahkan:

- Kolom email provider di `system_settings` (`email_provider_name`, `email_from`,
  `email_reply_to`) — kredensial tetap di env (`RESEND_API_KEY` / `SMTP_URL`)
- Tabel `notification_templates` (6 template ter-seed) + fungsi `apply_template()`
- Engine `run_subscription_automation()` di-upgrade: semua notifikasi kini dirender
  dari template aktif dengan fallback teks default — ubah teks dari
  `/admin/settings` tanpa deploy ulang

Halaman `/admin/settings` (server action + RLS admin):
tab Umum / Email / Jadwal Reminder / Template Notifikasi, preview variabel
`{{nama}}` dst., dan tombol kirim email uji (Resend aktif; SMTP menyusul).

## Admin Coupons (PRD #22)

Halaman `/admin/coupons`: ringkasan (total/aktif/penebusan), form create & edit
(kode, tipe %/nominal, minimum pembayaran, maks. pemakaian, batas paket, expiry),
toggle aktif/nonaktif, dan penghapusan aman — kupon yang sudah pernah ditebus
hanya dinonaktifkan agar riwayat transaksi tetap utuh. Semua aksi divalidasi
Zod + `requireStaff` dan tercatat di `activity_logs`.

## Checkout + Kupon (PRD #20, #22)

Migrasi `00005_checkout.sql`:

- `validate_coupon(code, plan_id, amount)` — security definer; cek aktif,
  kedaluwarsa, batas pemakaian, batas paket, minimum pembayaran; mengembalikan
  verdict + jumlah diskon (nominal tidak melebihi total). User tidak membaca
  tabel `coupons` langsung (RLS staff-only).
- `create_checkout(plan_id, period, coupon_code)` — satu transaksi DB:
  subscription (jendela pembayaran 3 hari) → invoice dengan diskon →
  payment pending → `coupon_redemptions` + increment `used_count` → audit log.
  Webhook memperpanjang langganan penuh setelah bayar; tidak dibayar =
  automation memindahkan ke past_due → suspended (lifecycle PRD #17).

Halaman `/checkout`: pilih paket + periode (bulanan/tahunan), input kupon
dengan validasi server-side dan pesan reason berbahasa Indonesia, ringkasan
subtotal/diskon/total, dan layar sukses bernomor invoice.

### Uji Validasi Kode (admin)

Tab "Uji Validasi Kode" di `/admin/coupons`: admin mensimulasikan
`validate_coupon` terhadap paket + periode tertentu tanpa membuat invoice —
menampilkan verdict (valid/tidak + alasan) dan rincian subtotal/diskon/total.

### Grafik Penebusan Kupon (admin)

`/admin/coupons` menampilkan grafik batang SVG (tanpa dependensi) penebusan
harian 30 hari terakhir — agregasi dihitung di server component — plus
peringkat kupon terpopuler (jumlah + total diskon) dan tooltip per batang.

## Pembayaran Manual (PRD #20 — fase tanpa payment gateway)

Migrasi `00006_manual_payment.sql`:

- `system_settings` + kolom instruksi manual (bank, nomor rekening, a/n,
  instruksi) — nilai awal DANA 082336939662 a/n Angga Bayu Setyawan;
  diubah admin dari `/admin/settings` (tabel system_settings).
- `create_checkout()` kini membuat payment dengan gateway `manual`.
- Trigger `ticket_created_notify` — tiket baru = notifikasi broadcast ke staff.
- `verify_manual_payment(payment_id, note)` — security definer dengan cek
  `is_staff()`; satu-satunya jalur yang melunasi payment: update payment →
  invoice → perpanjang subscription + website → notifikasi user (template
  PRD #34) → audit log.

Alur user: checkout → invoice + instruksi transfer → tombol "Kirim Bukti via
Support" membuka tiket berkategori payment (subjek otomatis berisi nomor
invoice, tempel URL gambar bukti). Alur admin: `/admin/tickets` → panel
"Pembayaran Manual Menunggu Verifikasi" → tombol Verifikasi Diterima.

Saat gateway provider nanti diaktifkan, webhook `route.ts` yang ada tetap
kompatibel (gateway_ref unik); cukup kembalikan create_checkout ke gateway
provider + buat Snap/Invoice URL.

### Upload Bukti Pembayaran ke Storage (PRD #43)

Migrasi `00007_proof_storage.sql`: bucket private `proofs` (maks 5MB,
PNG/JPG/WebP) + RLS storage policy — user hanya bisa upload/baca/hapus di
folder `{user_id}/…`, staff bisa membaca semua untuk verifikasi. Upload
langsung dari browser (`/app/support`), path disimpan di lampiran tiket;
user & admin melihat bukti via signed URL 1 jam yang dibuat server-side.

## Troubleshooting: Login "memuat" terus / tidak masuk

1. **Loading abadi di tombol Masuk** → diperbaiki: form kini try/finally
   (loading selalu mati) + error ditampilkan jelas. Penyebab paling umum:
   env `NEXT_PUBLIC_SUPABASE_URL`/`ANON_KEY` belum terisi di Vercel.
2. **"Email belum dikonfirmasi"** → Supabase mengaktifkan konfirmasi email
   secara default. Dua pilihan:
   - Development / segera aktif: Dashboard → Authentication → Sign In /
     Providers → Email → matikan **Confirm email**; ATAU
   - Biarkan aktif: user klik tautan di inbox. Redirect konfirmasi diarahkan
     ke `{SITE_URL}/auth/callback` (route sudah tersedia) — daftarkan URL itu
     di **Authentication → URL Configuration → Redirect URLs**.
3. Setelah mengisi/mengubah env di Vercel → **Redeploy** (env baru hanya
   aktif saat deploy ulang).
