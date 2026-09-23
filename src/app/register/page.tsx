import Link from 'next/link';
import RegisterForm from '@/components/register-form';

export const metadata = { title: 'Daftar' };

export default function RegisterPage() {
  return (
    <main className="flex min-h-screen items-center justify-center bg-navy p-6">
      <div className="w-full max-w-md rounded-2xl border border-white/10 bg-navy-3/80 p-8 backdrop-blur">
        <h1 className="mb-2 font-display text-2xl font-bold">Buat akun Anda</h1>
        <p className="mb-6 text-sm text-muted">
          Sudah punya akun? <Link href="/login" className="text-neon-cyan">Masuk di sini</Link>
        </p>
        <RegisterForm />
      </div>
    </main>
  );
}
