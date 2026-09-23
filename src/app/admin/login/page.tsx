import LoginForm from '@/components/login-form';

export const metadata = { title: 'Admin Login' };

export default function AdminLoginPage() {
  return (
    <main className="flex min-h-screen items-center justify-center bg-navy p-6">
      <div className="w-full max-w-md rounded-2xl border border-white/10 bg-navy-3/80 p-8">
        <h1 className="mb-6 font-display text-2xl font-bold">Admin Login</h1>
        <LoginForm />
      </div>
    </main>
  );
}
