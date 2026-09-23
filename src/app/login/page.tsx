import Link from 'next/link';
import LoginForm from '@/components/login-form';

export const metadata = { title: 'Masuk' };

export default function LoginPage() {
  return (
    <main className="flex min-h-screen items-center justify-center bg-navy p-6">
      <div className="w-full max-w-md rounded-2xl border border-white/10 bg-navy-3/80 p-8 backdrop-blur">
        <h1 className="mb-2 font-display text-2xl font-bold">Masuk ke akun Anda</h1>
        <p className="mb-6 text-sm text-muted">
          Belum punya akun? <Link href="/register" className="text-neon-cyan">Daftar sekarang</Link>
        </p>
        <LoginForm />
      </div>
    </main>
  );
}
