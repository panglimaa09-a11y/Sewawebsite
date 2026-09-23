# Checklist Setup .env.local — Sewa Web Murah

Salin `.env.example` → `.env.local`, lalu isi berdasar checklist ini.
Tabel ✅ = wajib diisi sebelum `npm run dev` jalan; ⭕ = boleh dikosongkan dulu.

## 1. Supabase (3 variabel — WAJIB)

Sumber: **Supabase Dashboard → pilih project → ⚙️ Project Settings → API**

| # | Variabel | Contoh / Cara ambil | Status |
|---|----------|--------------------|--------|
| 1 | `NEXT_PUBLIC_SUPABASE_URL` | `https://abcdefgh.supabase.co` — kolom **Project URL** | ✅ |
| 2 | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | kolom **Project API Keys → anon / public** — mulai dengan `eyJ...` | ✅ |
| 3 | `SUPABASE_SERVICE_ROLE_KEY` | kolom **service_role** — mulai dengan `eyJ...`. ⚠️ RAHASIA: hanya server, jangan pernah di-commit atau dipasang di client | ✅ |

Catatan: Supabase telah mengganti API keys lama menjadi **Publishable key (sb_publishable_...)** dan **Secret keys (sb_secret_...)** di beberapa project — jika dashboard Anda menampilkan format baru: publishable → isi ke `NEXT_PUBLIC_SUPABASE_ANON_KEY`, secret → `SUPABASE_SERVICE_ROLE_KEY`.

Prasyarat database: `sewa-web-murah-full-reset.sql` sudah di-run di SQL Editor ✅ (tabel `websites`, `plans`, `system_settings` muncul di Table Editor).

## 2. App (2 variabel)

| # | Variabel | Nilai | Status |
|---|----------|-------|--------|
| 4 | `NEXT_PUBLIC_SITE_URL` | `http://localhost:3000` saat development; nanti domain produksi saat deploy | ✅ |
| 5 | `NEXT_PUBLIC_ROOT_DOMAIN` | `sewawebmurah.com` (domain untuk subdomain pelanggan, PRD #51) | ✅ |

## 3. Cron automation (1 variabel — WAJIB)

| # | Variabel | Cara isi | Status |
|---|----------|----------|--------|
| 6 | `CRON_SECRET` | string acak panjang. Terminal: `openssl rand -hex 32` — salin hasilnya | ✅ |

Dipakai oleh `GET /api/cron/automation` (header `Authorization: Bearer <CRON_SECRET>`).

## 4. Pembayaran manual (0 variabel — sudah jalan)

Tidak ada yang diisi di env. Rekening DANA **082336939662 a/n Angga Bayu Setyawan** tersimpan di database (`system_settings`) dan bisa diubah kapan saja dari **/admin/settings → tab Umum/Email** tanpa deploy ulang.

## 5. Payment Gateway provider (4 variabel — ⭕ KOSONGKAN DULU)

Belum dipakai (mode manual aktif). Isi hanya saat fase integrasi Midtrans/Xendit/Duitku:

- ⭕ `PAYMENT_GATEWAY` — kosong
- ⭕ `PAYMENT_SERVER_KEY` / `PAYMENT_CLIENT_KEY` — dari dashboard provider
- ⭕ `PAYMENT_WEBHOOK_SECRET` — untuk verifikasi signature webhook
- ⭕ `PAYMENT_WEBHOOK_URL` — `https://domain/api/webhooks/payment`

## 6. Email provider (3 variabel — ⭕ KOSONGKAN DULU)

Notifikasi saat ini hanya masuk dashboard user & admin. Isi saat siap kirim email (reminder D-7/3/1, bukti pembayaran):

- ⭕ `RESEND_API_KEY` — daftar resend.com → API Keys (paling mudah, gratis 100 email/hari)
- ⭕ `SMTP_URL` — alternatif SMTP: `smtp://user:password@smtp.host:587`
- ⭕ `EMAIL_FROM` — `noreply@sewawebmurah.com` (perlu domain terverifikasi di provider)

Setelah terisi: **/admin/settings → tab Email** → pilih provider → simpan → uji dengan tombol "Kirim Uji".

## 7. Verifikasi akhir

```bash
npm install
npm run dev
```

- [ ] `http://localhost:3000` terbuka tanpa error di terminal
- [ ] `/register` → daftar akun → cek Table Editor: baris baru muncul di `profiles` (trigger jalan)
- [ ] Jadikan admin (SQL Editor):
  ```sql
  insert into user_roles (user_id, role_id)
  select (select id from auth.users where email='EMAIL-ANDA'), id from roles where name='admin';
  ```
- [ ] `/checkout` → pilih Starter → kupon `WELCOME50` diterapkan → Bayar → invoice muncul
- [ ] `/app/support` → kirim tiket "Bukti Pembayaran" + upload gambar bukti
- [ ] Login sebagai user itu di `/admin/login` → `/admin/tickets` → Verifikasi Diterima
- [ ] `/app/billing` → langganan aktif, tanggal diperpanjang

## 8. Keamanan (PRD #44)

- [ ] `.env.local` MASUK `.gitignore` (sudah — jangan pernah commit)
- [ ] `service_role` tidak pernah dipakai di file client (`'use client'`)
- [ ] PAT GitHub yang pernah ditempel di chat → **revoke** di Developer settings
- [ ] Saat deploy Vercel: semua variabel di atas diisi ulang di Project Settings → Environment Variables (nilai sama, tempel manual)
