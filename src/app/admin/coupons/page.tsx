import { requireStaff } from '@/lib/auth';
import { createClient } from '@/lib/supabase/server';
import CouponsClient from './coupons-client';

export const metadata = { title: 'Kupon' };

export default async function AdminCouponsPage() {
  await requireStaff('/admin/coupons');
  const supabase = await createClient();

  const [{ data: coupons }, { data: plans }, { data: redemptions }] = await Promise.all([
    supabase
      .from('coupons')
      .select('id, code, type, value, min_payment, max_usage, used_count, plan_restriction, expires_at, is_active, created_at')
      .order('created_at', { ascending: false }),
    supabase.from('plans').select('id, name').eq('is_active', true).order('sort_order'),
    supabase
      .from('coupon_redemptions')
      .select('id, coupon_id, user_id, discount_amount, redeemed_at')
      .order('redeemed_at', { ascending: false })
      .limit(50),
  ]);

  return (
    <div className="mx-auto max-w-5xl">
      <h1 className="font-display text-2xl font-bold">Kupon &amp; Promo</h1>
      <p className="mt-1 mb-6 text-sm text-muted">
        Kelola kode diskon: persentase atau nominal, batas pemakaian, minimum pembayaran, dan batas paket (PRD #22).
      </p>
      <CouponsClient
        coupons={coupons ?? []}
        plans={plans ?? []}
        redemptions={redemptions ?? []}
      />
    </div>
  );
}
