import { requireUser } from '@/lib/auth';
import { createClient } from '@/lib/supabase/server';
import CheckoutClient from './checkout-client';

export const metadata = { title: 'Checkout' };

export default async function CheckoutPage({
  searchParams,
}: {
  searchParams: Promise<{ plan?: string }>;
}) {
  await requireUser('/checkout');
  const { plan } = await searchParams;
  const supabase = await createClient();
  const { data: plans } = await supabase
    .from('plans')
    .select('id, name, description, price_monthly, price_yearly')
    .eq('is_active', true)
    .order('sort_order');

  return (
    <main className="min-h-screen bg-navy p-8">
      <div className="mx-auto max-w-5xl">
        <h1 className="font-display text-3xl font-bold">Checkout</h1>
        <p className="mt-2 mb-8 text-muted">
          Pilih paket dan periode, terapkan kupon bila ada, lalu bayar.
        </p>
        <CheckoutClient plans={plans ?? []} defaultPlanId={plan ?? null} />
      </div>
    </main>
  );
}
