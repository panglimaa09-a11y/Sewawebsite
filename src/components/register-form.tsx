'use client';

import { useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import { useRouter } from 'next/navigation';
import { friendlyAuthError } from './login-form';

/** Form register — Supabase Auth (PRD #9): nama, email, password. */
export default function RegisterForm() {
  const router = useRouter();
  const [fullName, setFullName] = useState('');
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
      const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: { data: { full_name: fullName } },
      });
      if (error) {
        setError(friendlyAuthError(error.message));
        return;
      }
      if (data.session) {
        // Konfirmasi email nonaktif → langsung lanjut
        router.push('/checkout');
        router.refresh();
        return;
      }
      // Konfirmasi email aktif → session null
      setError(
        'Pendaftaran berhasil! Cek inbox/spam Anda dan klik tautan konfirmasi untuk mengaktifkan akun, lalu masuk.'
      );
    } catch (e) {
      setError(friendlyAuthError(e instanceof Error ? e.message : 'Terjadi kesalahan.'));
    } finally {
      setLoading(false);
    }
  }

  return (
    <form onSubmit={onSubmit} className="flex flex-col gap-4">
      <label className="text-sm text-muted" htmlFor="name">Nama lengkap</label>
      <input id="name" required minLength={3} value={fullName} onChange={(e) => setFullName(e.target.value)}
        className="rounded-xl border border-white/20 bg-white/5 px-4 py-3 outline-none focus:border-neon-cyan" />
      <label className="text-sm text-muted" htmlFor="email">Email</label>
      <input id="email" type="email" required value={email} onChange={(e) => setEmail(e.target.value)}
        className="rounded-xl border border-white/20 bg-white/5 px-4 py-3 outline-none focus:border-neon-cyan" />
      <label className="text-sm text-muted" htmlFor="password">Password</label>
      <input id="password" type="password" required minLength={8} value={password}
        onChange={(e) => setPassword(e.target.value)}
        className="rounded-xl border border-white/20 bg-white/5 px-4 py-3 outline-none focus:border-neon-cyan" />
      {error && <p className="rounded-xl border border-neon-cyan/30 bg-neon-cyan/5 px-4 py-3 text-sm text-muted">{error}</p>}
      <button disabled={loading} type="submit"
        className="rounded-xl bg-gradient-to-r from-neon-cyan to-neon-violet py-3 font-semibold text-navy disabled:opacity-60">
        {loading ? 'Membuat akun…' : 'Daftar Sekarang'}
      </button>
    </form>
  );
}