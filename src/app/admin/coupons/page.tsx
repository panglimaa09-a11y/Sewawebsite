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
      .order('redeemed_at', { ascending: false }),
  ]);

  // Agregasi grafik — di server, tipe aman
  const rows = (redemptions ?? []) as {
    id: string;
    coupon_id: string;
    user_id: string;
    discount_amount: number;
    redeemed_at: string;
  }[];

  // Tren harian 30 hari terakhir (hari kosong = 0)
  const days: { date: string; count: number; discount: number }[] = [];
  const byDay = new Map<string, { count: number; discount: number }>();
  for (const r of rows) {
    const d = r.redeemed_at.slice(0, 10);
    const cur = byDay.get(d) ?? { count: 0, discount: 0 };
    cur.count++;
    cur.discount += Number(r.discount_amount);
    byDay.set(d, cur);
  }
  for (let i = 29; i >= 0; i--) {
    const dt = new Date(Date.now() - i * 86400000);
    const key = dt.toISOString().slice(0, 10);
    const cur = byDay.get(key) ?? { count: 0, discount: 0 };
    days.push({ date: key, ...cur });
  }

  // Per kupon: jumlah penebusan + total diskon
  const perCoupon = new Map<string, { count: number; discount: number }>();
  for (const r of rows) {
    const cur = perCoupon.get(r.coupon_id) ?? { count: 0, discount: 0 };
    cur.count++;
    cur.discount += Number(r.discount_amount);
    perCoupon.set(r.coupon_id, cur);
  }
  const topCoupons = [...perCoupon.entries()]
    .map(([coupon_id, v]) => ({ coupon_id, ...v }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 6);

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
        daily={days}
        topCoupons={topCoupons}
      />
    </div>
  );
}
