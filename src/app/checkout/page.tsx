import { requireUser } from '@/lib/auth';
import { createClient } from '@/lib/supabase/server';

export const metadata = { title: 'Checkout' };

export default async function CheckoutPage() {
  await requireUser('/checkout');
  const supabase = await createClient();
  const { data: plans } = await supabase
    .from('plans')
    .select('id, name, price_monthly, price_yearly, description')
    .eq('is_active', true)
    .order('sort_order');

  return (
    <main className="min-h-screen bg-navy p-8">
      <h1 className="font-display text-3xl font-bold">Checkout</h1>
      <p className="mt-2 mb-6 text-muted">Pilih paket, buat website, publish. (PRD #20)</p>
      <div className="grid max-w-4xl gap-4 md:grid-cols-3">
        {(plans ?? []).map((p) => (
          <div key={p.id} className="rounded-2xl border border-white/10 bg-navy-3 p-6">
            <h2 className="font-display text-xl font-bold">{p.name}</h2>
            <p className="mt-1 text-sm text-muted">{p.description}</p>
            <p className="mt-4 font-display text-2xl">
              Rp{p.price_monthly.toLocaleString('id-ID')}<span className="text-sm text-muted">/bulan</span>
            </p>
            {/* TODO: integrasi payment gateway → buat invoice + payment (service role) */}
          </div>
        ))}
      </div>
    </main>
  );
}
