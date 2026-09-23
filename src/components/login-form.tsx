'use client';

import { useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import { useRouter } from 'next/navigation';

/** Pesan error Supabase → kalimat yang bisa dipahami pengguna. */
export function friendlyAuthError(msg: string): string {
  if (/email not confirmed/i.test(msg))
    return 'Email belum dikonfirmasi. Cek inbox/spam Anda dan klik tautan konfirmasi — atau konfirmasi manual: Supabase Dashboard → Authentication → Users → pilih akun → Confirm.';
  if (/invalid login credentials/i.test(msg))
    return 'Email atau password salah. Coba lagi, atau daftar ulang jika akun belum dibuat.';
  if (/user not found/i.test(msg)) return 'Akun dengan email ini tidak ditemukan.';
  if (/failed to fetch|fetch failed|NetworkError|ERR_NAME/i.test(msg))
    return 'Tidak dapat menghubungi Supabase — periksa NEXT_PUBLIC_SUPABASE_URL di environment, lalu redeploy.';
  if (/invalid url|not configured|supabaseurl is required/i.test(msg))
    return 'Konfigurasi Supabase belum lengkap — isi NEXT_PUBLIC_SUPABASE_URL dan NEXT_PUBLIC_SUPABASE_ANON_KEY di environment, lalu redeploy.';
  if (/rate limit|too many/i.test(msg))
    return 'Terlalu banyak percobaan. Tunggu sebentar lalu coba lagi.';
  return msg;
}

/** Form login — Supabase Auth (PRD #9). Validasi & UI mengikuti login.html. */
export default function LoginForm() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      const supabase = createClient();
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) {
        setError(friendlyAuthError(error.message));
        return; // finally tetap mematikan loading
      }
      router.push('/app/dashboard');
      router.refresh();
    } catch (e) {
      // env hilang/URL rusak → createClient melempar; jangan biarkan loading abadi
      setError(friendlyAuthError(e instanceof Error ? e.message : 'Terjadi kesalahan.'));
    } finally {
      setLoading(false);
    }
  }

  return (
    <form onSubmit={onSubmit} className="flex flex-col gap-4">
      <label className="text-sm text-muted" htmlFor="email">Email</label>
      <input id="email" type="email" required value={email} onChange={(e) => setEmail(e.target.value)}
        className="rounded-xl border border-white/20 bg-white/5 px-4 py-3 outline-none focus:border-neon-cyan" />
      <label className="text-sm text-muted" htmlFor="password">Password</label>
      <input id="password" type="password" required minLength={8} value={password}
        onChange={(e) => setPassword(e.target.value)}
        className="rounded-xl border border-white/20 bg-white/5 px-4 py-3 outline-none focus:border-neon-cyan" />
      {error && <p className="rounded-xl border border-rose-400/30 bg-rose-400/5 px-4 py-3 text-sm text-rose-300">{error}</p>}
      <button disabled={loading} type="submit"
        className="rounded-xl bg-gradient-to-r from-neon-cyan to-neon-violet py-3 font-semibold text-navy disabled:opacity-60">
        {loading ? 'Memproses…' : 'Masuk'}
      </button>
    </form>
  );
}