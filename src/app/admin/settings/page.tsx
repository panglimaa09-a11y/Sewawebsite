import { requireRole } from '@/lib/auth';
import { createClient } from '@/lib/supabase/server';
import SettingsClient from './settings-client';

export const metadata = { title: 'Pengaturan Sistem' };

export default async function AdminSettingsPage() {
  await requireRole('admin', '/admin/settings');
  const supabase = await createClient();

  const [{ data: settings }, { data: templates }] = await Promise.all([
    supabase.from('system_settings').select('*').limit(1).single(),
    supabase
      .from('notification_templates')
      .select('id, kind, channel, subject, body, variables, is_active, updated_at')
      .order('kind'),
  ]);

  return (
    <div className="mx-auto max-w-4xl">
      <h1 className="font-display text-2xl font-bold">Pengaturan Sistem</h1>
      <p className="mt-1 mb-6 text-sm text-muted">
        Kelola identitas platform, provider email, jadwal reminder (PRD #38), dan template notifikasi (PRD #34).
      </p>
      <SettingsClient
        settings={settings ?? null}
        templates={templates ?? []}
      />
    </div>
  );
}
