import { requireStaff } from '@/lib/auth';
import { createClient } from '@/lib/supabase/server';
import TicketsClient from './tickets-client';

export const metadata = { title: 'Tiket Support' };

export default async function AdminTicketsPage() {
  await requireStaff('/admin/tickets');
  const supabase = await createClient();

  const [{ data: tickets }, { data: messages }, { data: pendingPayments }] = await Promise.all([
    supabase
      .from('tickets')
      .select('id, user_id, subject, category, status, created_at, profiles(full_name)')
      .order('created_at', { ascending: false }),
    supabase
      .from('ticket_messages')
      .select('id, ticket_id, sender_id, is_staff, body, attachments, created_at')
      .order('created_at'),
    supabase
      .from('payments')
      .select('id, user_id, invoice_id, amount, currency, status, created_at, invoices(number)')
      .eq('status', 'pending')
      .eq('gateway', 'manual')
      .order('created_at', { ascending: false }),
  ]);

  return (
    <div className="mx-auto max-w-5xl">
      <h1 className="font-display text-2xl font-bold">Tiket Support</h1>
      <p className="mt-1 mb-6 text-sm text-muted">
        Balas tiket pelanggan dan verifikasi pembayaran manual (bukti transfer via tiket).
      </p>
      <TicketsClient
        tickets={tickets ?? []}
        messages={messages ?? []}
        pendingPayments={pendingPayments ?? []}
      />
    </div>
  );
}
