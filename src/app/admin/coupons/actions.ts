'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { requireStaff } from '@/lib/auth';
import { createClient } from '@/lib/supabase/server';

export type ActionState = {
  ok: boolean;
  message: string;
  data?: { base?: number; discount?: number; total?: number };
};

/**
 * Kelola kupon (PRD #22). Role: admin/super_admin/finance (RLS staff policy
 * sudah menegakkan; requireStaff menegaskan lagi server-side).
 * Validasi bisnis PRD #22: tipe percentage/fixed_amount, discount, expiry,
 * max_usage, minimum_payment, plan_restriction.
 */

const couponSchema = z
  .object({
    id: z.string().uuid().optional().or(z.literal('')),
    code: z
      .string()
      .min(3)
      .max(24)
      .regex(/^[A-Z0-9_-]+$/, 'Kode: huruf besar, angka, - atau _ saja'),
    type: z.enum(['percentage', 'fixed_amount']),
    value: z.coerce.number().positive('Nilai diskon harus > 0'),
    min_payment: z.coerce.number().min(0).default(0),
    max_usage: z.coerce.number().int().min(1).max(100000).optional().or(z.literal('')),
    plan_restriction: z.string().uuid().optional().or(z.literal('')),
    expires_at: z.string().optional().or(z.literal('')), // datetime-local
    is_active: z.boolean(),
  })
  .refine((d) => d.type !== 'percentage' || d.value <= 100, {
    message: 'Diskon persentase maksimal 100',
    path: ['value'],
  });

function toDatetimeLocal(iso: string | null | undefined): string {
  if (!iso) return '';
  return iso.slice(0, 16); // "2026-09-30T23:59"
}

export async function loadCouponForEdit(id: string) {
  await requireStaff('/admin/coupons');
  const supabase = await createClient();
  const { data } = await supabase
    .from('coupons')
    .select('id, code, type, value, min_payment, max_usage, plan_restriction, expires_at, is_active')
    .eq('id', id)
    .single();
  if (!data) return null;
  return { ...data, expires_at: toDatetimeLocal(data.expires_at as string | null) };
}

export async function saveCoupon(_prev: ActionState | null, formData: FormData): Promise<ActionState> {
  const staff = await requireStaff('/admin/coupons');
  const parsed = couponSchema.safeParse({
    ...Object.fromEntries(formData.entries()),
    is_active: formData.get('is_active') === 'on',
  });
  if (!parsed.success) {
    return { ok: false, message: parsed.error.issues[0]?.message ?? 'Data kupon tidak valid' };
  }
  const { id, max_usage, plan_restriction, expires_at, ...rest } = parsed.data;

  const supabase = await createClient();

  // Kode harus unik (kecuali baris yang sedang diedit)
  const { data: dupe } = await supabase
    .from('coupons')
    .select('id')
    .eq('code', rest.code)
    .neq('id', id || '00000000-0000-0000-0000-000000000000')
    .maybeSingle();
  if (dupe) return { ok: false, message: `Kode ${rest.code} sudah dipakai kupon lain.` };

  const payload = {
    ...rest,
    max_usage: max_usage === '' ? null : max_usage,
    plan_restriction: plan_restriction === '' ? null : plan_restriction,
    expires_at: expires_at ? new Date(expires_at as string).toISOString() : null,
  };

  let error;
  if (id) {
    ({ error } = await supabase.from('coupons').update(payload).eq('id', id));
  } else {
    ({ error } = await supabase.from('coupons').insert({
      ...payload,
      created_by: staff.id,
    }));
  }
  if (error) return { ok: false, message: error.message };

  await supabase.from('activity_logs').insert({
    actor_id: staff.id,
    actor_role: 'admin',
    action: 'admin_action',
    target_type: 'coupon',
    target_id: id || null,
    metadata: { action: id ? 'update_coupon' : 'create_coupon', code: rest.code },
  });

  revalidatePath('/admin/coupons');
  return { ok: true, message: `Kupon ${rest.code} ${id ? 'diperbarui' : 'dibuat'}.` };
}

export async function toggleCoupon(_prev: ActionState | null, formData: FormData): Promise<ActionState> {
  const staff = await requireStaff('/admin/coupons');
  const id = String(formData.get('id') ?? '');
  const nextActive = formData.get('next_active') === 'true';
  if (!id) return { ok: false, message: 'ID kupon tidak ada.' };

  const supabase = await createClient();
  const { error } = await supabase
    .from('coupons')
    .update({ is_active: nextActive })
    .eq('id', id);
  if (error) return { ok: false, message: error.message };

  await supabase.from('activity_logs').insert({
    actor_id: staff.id,
    actor_role: 'admin',
    action: 'admin_action',
    target_type: 'coupon',
    target_id: id,
    metadata: { action: nextActive ? 'activate_coupon' : 'deactivate_coupon' },
  });

  revalidatePath('/admin/coupons');
  return { ok: true, message: nextActive ? 'Kupon diaktifkan.' : 'Kupon dinonaktifkan.' };
}

export async function deleteCoupon(_prev: ActionState | null, formData: FormData): Promise<ActionState> {
  const staff = await requireStaff('/admin/coupons');
  const id = String(formData.get('id') ?? '');
  if (!id) return { ok: false, message: 'ID kupon tidak ada.' };

  const supabase = await createClient();
  // Hard delete hanya jika belum ada penebusan; jika sudah dipakai, nonaktifkan saja
  const { count } = await supabase
    .from('coupon_redemptions')
    .select('id', { count: 'exact', head: true })
    .eq('coupon_id', id);

  if (count && count > 0) {
    const { error } = await supabase.from('coupons').update({ is_active: false }).eq('id', id);
    if (error) return { ok: false, message: error.message };
    revalidatePath('/admin/coupons');
    return {
      ok: false,
      message: `Kupon sudah dipakai ${count}× — dinonaktifkan alih-alih dihapus agar riwayat transaksi tetap utuh.`,
    };
  }

  const { error } = await supabase.from('coupons').delete().eq('id', id);
  if (error) return { ok: false, message: error.message };

  await supabase.from('activity_logs').insert({
    actor_id: staff.id,
    actor_role: 'admin',
    action: 'admin_action',
    target_type: 'coupon',
    target_id: id,
    metadata: { action: 'delete_coupon' },
  });

  revalidatePath('/admin/coupons');
  return { ok: true, message: 'Kupon dihapus.' };
}
/** Simulasi validasi kode (PRD #22) — admin cek kode tanpa checkout nyata. */
export async function testCoupon(_prev: ActionState | null, formData: FormData): Promise<ActionState> {
  await requireStaff('/admin/coupons');
  const code = String(formData.get('test_code') ?? '').trim().toUpperCase();
  const planId = String(formData.get('test_plan') ?? '');
  const period = String(formData.get('test_period') ?? 'monthly') === 'yearly' ? 'yearly' : 'monthly';
  if (!code) return { ok: false, message: 'Masukkan kode yang mau diuji.' };
  if (!planId) return { ok: false, message: 'Pilih paket untuk simulasi.' };

  const supabase = await createClient();
  const { data: plan } = await supabase
    .from('plans')
    .select('name, price_monthly, price_yearly')
    .eq('id', planId)
    .single();
  if (!plan) return { ok: false, message: 'Paket tidak ditemukan.' };

  const base =
    period === 'yearly' ? (plan.price_yearly ?? plan.price_monthly * 12) : plan.price_monthly;

  const { data, error } = await supabase.rpc('validate_coupon', {
    p_code: code,
    p_plan_id: planId,
    p_amount: base,
  });
  if (error) return { ok: false, message: error.message };

  const r = data as {
    valid: boolean;
    reason?: string;
    discount?: number;
    min_payment?: number;
    type?: string;
    value?: number;
  };
  if (!r.valid) {
    const msg =
      r.reason === 'min_payment' && r.min_payment
        ? `TIDAK VALID — minimum pembayaran Rp${Number(r.min_payment).toLocaleString('id-ID')} belum terpenuhi (total simulasi Rp${base.toLocaleString('id-ID')}).`
        : `TIDAK VALID — ${r.reason ?? 'alasan tidak diketahui'}.`;
    return { ok: false, message: msg, data: { base, discount: 0, total: base } };
  }

  return {
    ok: true,
    message: `VALID — diskon ${r.type === 'percentage' ? `${r.value}%` : `Rp${Number(r.value).toLocaleString('id-ID')}`} diterapkan.`,
    data: { base, discount: Number(r.discount), total: base - Number(r.discount) },
  };
}
