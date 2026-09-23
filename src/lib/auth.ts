import 'server-only';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';

export type SessionUser = {
  id: string;
  email: string;
};

async function getSessionUser(): Promise<SessionUser | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user?.email) return null;
  return { id: user.id, email: user.email };
}

/** Wajib login — redirect jika belum. Dipanggil dari Server Component. */
export async function requireUser(next = '/app/dashboard'): Promise<SessionUser> {
  const user = await getSessionUser();
  if (!user) redirect(`/login?next=${encodeURIComponent(next)}`);
  return user;
}

/** Wajib login + role staff (admin/super_admin/support/finance). */
export async function requireStaff(next = '/admin/dashboard') {
  const user = await requireUser(next);
  const supabase = await createClient();
  const { data } = await supabase
    .from('user_roles')
    .select('roles!inner(name)')
    .eq('user_id', user.id);
  const roles = ((data ?? []) as { roles: { name: string }[] }[]).flatMap((r) =>
    r.roles.map((x) => x.name)
  );
  const isStaff = roles.some((r: string) =>
    ['admin', 'super_admin', 'support', 'finance'].includes(r)
  );
  if (!isStaff) redirect('/app/dashboard'); // bukan staff → keluar dari /admin
  return { ...user, roles };
}

/** Wajib role spesifik (mis. finance untuk /admin/billing). */
export async function requireRole(role: string, next = '/admin/dashboard') {
  const staff = await requireStaff(next);
  if (!staff.roles.includes(role) && !staff.roles.includes('super_admin')) {
    redirect('/admin/dashboard');
  }
  return staff;
}
