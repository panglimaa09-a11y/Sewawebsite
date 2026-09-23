import { requireStaff } from '@/lib/auth';

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  await requireStaff(); // role check server-side, bukan URL saja (PRD #4)
  return <div className="min-h-screen bg-navy p-6">{children}</div>;
}
