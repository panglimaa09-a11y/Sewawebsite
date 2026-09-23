'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { requireRole } from '@/lib/auth';
import { createClient } from '@/lib/supabase/server';

/**
 * Server actions untuk /admin/settings (PRD #39, #34).
 * Semua aksi memverifikasi role ADMIN di server sebelum menulis.
 * RLS tetap aktif — action menulis via client server-side (bukan service role).
 */

const settingsSchema = z.object({
  platform_name: z.string().min(2).max(60),
  currency: z.string().min(3).max(6),
  timezone: z.string().min(3).max(40),
  support_email: z.string().email().or(z.literal('')),
  support_whatsapp: z.string().max(20).or(z.literal('')),
  email_provider_name: z.enum(['none', 'resend', 'smtp']),
  email_from: z.string().email().or(z.literal('')),
  email_reply_to: z.string().email().or(z.literal('')),
  reminder_days: z.string().regex(/^(\d+)(,\d+)*$/, 'Format: angka dipisah koma, mis. 7,3,1'),
  grace_period_days: z.coerce.number().int().min(0).max(30),
  expire_after_days: z.coerce.number().int().min(1).max(90),
  registration_enabled: z.boolean(),
  maintenance_mode: z.boolean(),
});

export type ActionState = { ok: boolean; message: string };

const SETTINGS_ID = '00000000-0000-0000-0000-000000000000';

export async function saveSettings(_prev: ActionState | null, formData: FormData): Promise<ActionState> {
  const staff = await requireRole('admin', '/admin/settings');
  const raw = Object.fromEntries(formData.entries());
  const parsed = settingsSchema.safeParse({
    ...raw,
    registration_enabled: formData.get('registration_enabled') === 'on',
    maintenance_mode: formData.get('maintenance_mode') === 'on',
  });
  if (!parsed.success) {
    return { ok: false, message: parsed.error.issues[0]?.message ?? 'Data tidak valid' };
  }

  const { reminder_days, ...rest } = parsed.data;
  const supabase = await createClient();
  const { error } = await supabase
    .from('system_settings')
    .update({
      ...rest,
      reminder_days: reminder_days.split(',').map((n) => parseInt(n.trim(), 10)),
      updated_at: new Date().toISOString(),
    })
    .eq('id', SETTINGS_ID);

  if (error) return { ok: false, message: error.message };

  await supabase.from('activity_logs').insert({
    actor_id: staff.id,
    actor_role: 'admin',
    action: 'admin_action',
    target_type: 'system_settings',
    target_id: SETTINGS_ID,
    metadata: { action: 'update_settings' },
  });

  revalidatePath('/admin/settings');
  return { ok: true, message: 'Pengaturan tersimpan.' };
}

const templateSchema = z.object({
  id: z.string().uuid(),
  kind: z.string().min(3).max(60),
  channel: z.enum(['dashboard', 'email', 'whatsapp']),
  subject: z.string().min(3).max(160),
  body: z.string().min(10).max(2000),
  is_active: z.boolean(),
});

export async function saveTemplate(_prev: ActionState | null, formData: FormData): Promise<ActionState> {
  const staff = await requireRole('admin', '/admin/settings');
  const parsed = templateSchema.safeParse({
    id: formData.get('id'),
    kind: formData.get('kind'),
    channel: formData.get('channel'),
    subject: formData.get('subject'),
    body: formData.get('body'),
    is_active: formData.get('is_active') === 'on',
  });
  if (!parsed.success) {
    return { ok: false, message: parsed.error.issues[0]?.message ?? 'Template tidak valid' };
  }
  const { id, ...data } = parsed.data;

  const supabase = await createClient();
  const { error } = await supabase
    .from('notification_templates')
    .update({ ...data, updated_by: staff.id, updated_at: new Date().toISOString() })
    .eq('id', id);
  if (error) return { ok: false, message: error.message };

  await supabase.from('activity_logs').insert({
    actor_id: staff.id,
    actor_role: 'admin',
    action: 'admin_action',
    target_type: 'notification_template',
    target_id: id,
    metadata: { action: 'update_template', kind: data.kind },
  });

  revalidatePath('/admin/settings');
  return { ok: true, message: `Template "${data.kind}" tersimpan.` };
}

/** Uji kirim email dengan template terpilih — via provider aktif. */
export async function sendTestEmail(_prev: ActionState | null, formData: FormData): Promise<ActionState> {
  await requireRole('admin', '/admin/settings');
  const to = String(formData.get('to') ?? '');
  const subject = String(formData.get('subject') ?? '');
  const body = String(formData.get('body') ?? '');
  if (!z.string().email().safeParse(to).success) {
    return { ok: false, message: 'Alamat email tujuan tidak valid.' };
  }

  const supabase = await createClient();
  const { data: settings } = await supabase.from('system_settings').select('*').limit(1).single();
  if (settings?.email_provider_name === 'none') {
    return { ok: false, message: 'Provider email belum diaktifkan (set ke resend atau smtp).' };
  }
  const from = settings?.email_from || 'noreply@sewawebmurah.com';

  try {
    if (settings?.email_provider_name === 'resend') {
      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${process.env.RESEND_API_KEY ?? ''}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ from, to, subject, html: `<p>${body.replace(/\n/g, '<br>')}</p>` }),
      });
      if (!res.ok) {
        return { ok: false, message: `Resend error: ${res.status}` };
      }
    } else {
      // SMTP: gunakan nodemailer + SMTP_URL env — sengaja disiapkan di Phase berikut
      return { ok: false, message: 'Kirim SMTP diaktifkan setelah nodemailer terpasang (README).' };
    }
  } catch (e) {
    return { ok: false, message: e instanceof Error ? e.message : 'Gagal mengirim' };
  }

  return { ok: true, message: `Email uji terkirim ke ${to}.` };
}