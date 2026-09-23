import { requireUser } from '@/lib/auth';

export default async function UserAppLayout({ children }: { children: React.ReactNode }) {
  await requireUser(); // otorisasi server-side (PRD #42)
  return <div className="min-h-screen bg-navy p-6">{children}</div>;
}
