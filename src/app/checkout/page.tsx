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
  const [{ data: plans }, { data: settings }] = await Promise.all([
    supabase
      .from('plans')
      .select('id, name, description, price_monthly, price_yearly')
      .eq('is_active', true)
      .order('sort_order'),
    supabase
      .from('system_settings')
      .select('manual_payment_enabled, manual_bank_name, manual_account_number, manual_account_holder, manual_instructions')
      .limit(1)
      .single(),
  ]);

  return (
    <main className="min-h-screen bg-navy p-8">
      <div className="mx-auto max-w-5xl">
        <h1 className="font-display text-3xl font-bold">Checkout</h1>
        <p className="mt-2 mb-8 text-muted">
          Pilih paket dan periode, terapkan kupon bila ada, lalu bayar.
        </p>
        <CheckoutClient
          plans={plans ?? []}
          defaultPlanId={plan ?? null}
          manual={{
            enabled: settings?.manual_payment_enabled ?? false,
            bank: settings?.manual_bank_name ?? 'Bank Transfer',
            account: settings?.manual_account_number ?? '',
            holder: settings?.manual_account_holder ?? '',
            instructions: settings?.manual_instructions ?? '',
          }}
        />
      </div>
    </main>
  );
}
