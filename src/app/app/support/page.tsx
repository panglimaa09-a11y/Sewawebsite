import { requireUser } from '@/lib/auth';
import { createClient } from '@/lib/supabase/server';
import SupportClient from './support-client';

export const metadata = { title: 'Support' };

type RawAttachment = { url?: string; path?: string };

export default async function UserSupportPage({
  searchParams,
}: {
  searchParams: Promise<{ prefill?: string }>;
}) {
  const { prefill } = await searchParams;
  await requireUser('/app/support');
  const supabase = await createClient();

  const [{ data: tickets }, { data: rawMessages }] = await Promise.all([
    supabase
      .from('tickets')
      .select('id, subject, category, status, created_at')
      .order('created_at', { ascending: false }),
    supabase
      .from('ticket_messages')
      .select('id, ticket_id, sender_id, is_staff, body, attachments, created_at')
      .order('created_at'),
  ]);

  // Bukti di bucket private — tampilkan via signed URL (1 jam)
  const raw = (rawMessages ?? []) as (typeof rawMessages extends null
    ? never
    : {
        id: string;
        ticket_id: string;
        sender_id: string;
        is_staff: boolean;
        body: string;
        attachments: RawAttachment[];
        created_at: string;
      })[];

  const messages = await Promise.all(
    raw.map(async (m) => ({
      id: m.id,
      ticket_id: m.ticket_id,
      sender_id: m.sender_id,
      is_staff: m.is_staff,
      body: m.body,
      created_at: m.created_at,
      attachments: await Promise.all(
        (m.attachments ?? []).map(async (a) => ({
          url:
            a.url ??
            (a.path
              ? (await supabase.storage.from('proofs').createSignedUrl(a.path, 3600)).data?.signedUrl ?? null
              : null),
        }))
      ),
    }))
  );

  return (
    <div className="mx-auto max-w-3xl">
      <h1 className="font-display text-2xl font-bold">Support</h1>
      <p className="mt-1 mb-6 text-sm text-muted">
        Buat tiket, kirim bukti pembayaran, dan pantau balasan tim support di sini.
      </p>
      <SupportClient
        tickets={tickets ?? []}
        messages={messages}
        prefillSubject={prefill ?? null}
      />
    </div>
  );
}
