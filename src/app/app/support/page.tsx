import { requireUser } from '@/lib/auth';
import { createClient } from '@/lib/supabase/server';
import SupportClient from './support-client';

export const metadata = { title: 'Support' };

export default async function UserSupportPage({
  searchParams,
}: {
  searchParams: Promise<{ prefill?: string }>;
}) {
  const { prefill } = await searchParams;
  await requireUser('/app/support');
  const supabase = await createClient();

  const [{ data: tickets }, { data: messages }] = await Promise.all([
    supabase
      .from('tickets')
      .select('id, subject, category, status, created_at')
      .order('created_at', { ascending: false }),
    supabase
      .from('ticket_messages')
      .select('id, ticket_id, sender_id, is_staff, body, attachments, created_at')
      .order('created_at'),
  ]);

  return (
    <div className="mx-auto max-w-3xl">
      <h1 className="font-display text-2xl font-bold">Support</h1>
      <p className="mt-1 mb-6 text-sm text-muted">
        Buat tiket, kirim bukti pembayaran, dan pantau balasan tim support di sini.
      </p>
      <SupportClient
        tickets={tickets ?? []}
        messages={messages ?? []}
        prefillSubject={prefill ?? null}
      />
    </div>
  );
}
