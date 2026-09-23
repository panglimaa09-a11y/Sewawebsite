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
