'use server';

import { requireUser } from '@/lib/auth';
import { createClient } from '@/lib/supabase/server';

export type ActionState = {
  ok: boolean;
  message: string;
  data?: { discount?: number; total?: number; code?: string; invoiceNumber?: string };
};

/** Pesan reason dari validate_coupon → teks ramah pengguna. */
const REASONS: Record<string, string> = {
  empty: 'Masukkan kode kupon terlebih dahulu.',
  not_found: 'Kode kupon tidak ditemukan.',
  inactive: 'Kupon ini tidak aktif.',
  not_started: 'Kupon ini belum mulai berlaku.',
  expired: 'Kupon ini sudah kedaluwarsa.',
  max_usage: 'Batas pemakaian kupon ini sudah tercapai.',
  plan_restriction: 'Kupon hanya berlaku untuk paket tertentu.',
  min_payment: 'Minimum pembayaran untuk kupon ini belum terpenuhi.',
};

async function baseAmount(planId: string, period: 'monthly' | 'yearly'): Promise<number | null> {
  const supabase = await createClient();
  const { data: plan } = await supabase
    .from('plans')
    .select('price_monthly, price_yearly')
    .eq('id', planId)
    .eq('is_active', true)
    .single();
  if (!plan) return null;
  return period === 'yearly'
    ? (plan.price_yearly ?? plan.price_monthly * 12)
    : plan.price_monthly;
}

/** Terapkan kupon → hitung diskon untuk kombinasi paket + periode ini. */
export async function checkCoupon(_prev: ActionState | null, formData: FormData): Promise<ActionState> {
  await requireUser('/checkout');
  const code = String(formData.get('code') ?? '').trim().toUpperCase();
  const planId = String(formData.get('plan_id') ?? '');
  const period = (String(formData.get('period') ?? 'monthly') === 'yearly' ? 'yearly' : 'monthly') as
    | 'monthly'
    | 'yearly';

  if (!code) return { ok: false, message: REASONS.empty };
  if (!planId) return { ok: false, message: 'Pilih paket terlebih dahulu.' };

  const base = await baseAmount(planId, period);
  if (base === null) return { ok: false, message: 'Paket tidak ditemukan.' };

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('validate_coupon', {
    p_code: code,
    p_plan_id: planId,
    p_amount: base,
  });
  if (error) return { ok: false, message: error.message };

  const r = data as { valid: boolean; reason?: string; discount?: number; min_payment?: number };
  if (!r.valid) {
    const msg =
      r.reason === 'min_payment' && r.min_payment
        ? `${REASONS.min_payment} (min. Rp${Number(r.min_payment).toLocaleString('id-ID')})`
        : REASONS[r.reason ?? ''] ?? 'Kupon tidak dapat digunakan.';
    return { ok: false, message: msg, data: { discount: 0, total: base } };
  }

  return {
    ok: true,
    message: `Kupon ${code} diterapkan — hemat Rp${Number(r.discount).toLocaleString('id-ID')}.`,
    data: { discount: Number(r.discount), total: base - Number(r.discount), code },
  };
}

/** Buat subscription + invoice + payment (dengan kupon bila ada). */
export async function submitCheckout(_prev: ActionState | null, formData: FormData): Promise<ActionState> {
  await requireUser('/checkout');
  const planId = String(formData.get('plan_id') ?? '');
  const period = (String(formData.get('period') ?? 'monthly') === 'yearly' ? 'yearly' : 'monthly') as
    | 'monthly'
    | 'yearly';
  const code = String(formData.get('code') ?? '').trim().toUpperCase() || null;

  if (!planId) return { ok: false, message: 'Pilih paket terlebih dahulu.' };

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('create_checkout', {
    p_plan_id: planId,
    p_billing_period: period,
    p_coupon_code: code,
  });
  if (error) {
    const msg =
      error.message === 'UNAUTHENTICATED'
        ? 'Sesi berakhir — silakan masuk kembali.'
        : error.message === 'PLAN_NOT_FOUND'
          ? 'Paket tidak tersedia.'
          : error.message;
    return { ok: false, message: msg };
  }

  const r = data as {
    ok: boolean;
    reason?: string;
    invoice_id?: string;
    total?: number;
    discount?: number;
  };
  if (!r.ok) {
    return { ok: false, message: REASONS[r.reason ?? ''] ?? 'Checkout gagal.' };
  }

  // Ambil nomor invoice (RLS: pemilik boleh baca invoice miliknya)
  const { data: inv } = await supabase
    .from('invoices')
    .select('number')
    .eq('id', r.invoice_id!)
    .single();

  return {
    ok: true,
    message: 'Checkout berhasil dibuat.',
    data: {
      invoiceNumber: inv?.number ?? '',
      total: r.total ?? 0,
      discount: r.discount ?? 0,
    },
  };
}