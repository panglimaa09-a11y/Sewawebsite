'use client';

import { useActionState, useState } from 'react';
import { replyTicket, setTicketStatus, verifyPayment, type ActionState } from '@/lib/support-actions';

type Ticket = {
  id: string;
  user_id: string;
  subject: string;
  category: string;
  status: string;
  created_at: string;
  profiles: { full_name: string | null }[] | null;
};
type Message = {
  id: string;
  ticket_id: string;
  sender_id: string;
  is_staff: boolean;
  body: string;
  attachments: { url: string }[];
  created_at: string;
};
type PendingPayment = {
  id: string;
  user_id: string;
  invoice_id: string | null;
  amount: number;
  currency: string;
  status: string;
  created_at: string;
  invoices: { number: string }[] | null;
};

const inputCls =
  'w-full rounded-xl border border-white/20 bg-white/5 px-3 py-2.5 text-sm text-ink outline-none focus:border-neon-cyan';

const STATUS_CLS: Record<string, string> = {
  open: 'bg-neon-cyan/10 text-neon-cyan',
  pending: 'bg-amber-400/10 text-amber-300',
  resolved: 'bg-neon-mint/10 text-neon-mint',
  closed: 'bg-white/5 text-dim',
};

function fmt(n: number) {
  return 'Rp' + Number(n).toLocaleString('id-ID');
}
function Notice({ state }: { state: ActionState | null }) {
  if (!state) return null;
  return <p className={`mt-2 text-xs ${state.ok ? 'text-neon-mint' : 'text-rose-400'}`}>{state.message}</p>;
}

export default function TicketsClient({
  tickets,
  messages,
  pendingPayments,
}: {
  tickets: Ticket[];
  messages: Message[];
  pendingPayments: PendingPayment[];
}) {
  const [openId, setOpenId] = useState<string | null>(tickets[0]?.id ?? null);
  const [replyState, replyAction] = useActionState<ActionState | null, FormData>(replyTicket, null);
  const [statusState, statusAction] = useActionState<ActionState | null, FormData>(setTicketStatus, null);
  const [verifyState, verifyAction] = useActionState<ActionState | null, FormData>(verifyPayment, null);

  return (
    <div className="flex flex-col gap-8">
      {/* pembayaran menunggu verifikasi */}
      <div>
        <h2 className="mb-3 font-display text-sm font-semibold uppercase tracking-wider text-dim">
          Pembayaran Manual Menunggu Verifikasi ({pendingPayments.length})
        </h2>
        {pendingPayments.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-white/15 bg-navy-3/50 p-6 text-center text-sm text-muted">
            Tidak ada pembayaran pending.
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            {pendingPayments.map((p) => (
              <form key={p.id} action={verifyAction} className="flex flex-wrap items-center gap-3 rounded-2xl border border-white/10 bg-navy-3/70 px-5 py-4">
                <div className="mr-auto">
                  <b className="font-mono text-sm">{p.invoices?.[0]?.number ?? '—'}</b>
                  <p className="text-[11px] text-dim">
                    user {p.user_id.slice(0, 8)}… · dibuat {new Date(p.created_at).toLocaleDateString('id-ID', { day: 'numeric', month: 'short' })}
                  </p>
                </div>
                <b className="font-display text-lg">{fmt(p.amount)}</b>
                <input name="note" placeholder="Catatan (opsional)" className={`${inputCls} max-w-[220px]`} />
                <button className="rounded-xl bg-gradient-to-r from-neon-cyan to-neon-violet px-5 py-2.5 text-sm font-semibold text-navy">
                  Verifikasi Diterima
                </button>
              </form>
            ))}
          </div>
        )}
        <Notice state={verifyState} />
      </div>

      {/* daftar tiket */}
      <div>
        <h2 className="mb-3 font-display text-sm font-semibold uppercase tracking-wider text-dim">
          Semua Tiket ({tickets.length})
        </h2>
        {tickets.length === 0 && (
          <div className="rounded-2xl border border-dashed border-white/15 bg-navy-3/50 p-6 text-center text-sm text-muted">
            Belum ada tiket masuk.
          </div>
        )}
        <div className="flex flex-col gap-3">
          {tickets.map((t) => {
            const msgs = messages.filter((m) => m.ticket_id === t.id);
            const open = openId === t.id;
            return (
              <div key={t.id} className="overflow-hidden rounded-2xl border border-white/10 bg-navy-3/70">
                <button onClick={() => setOpenId(open ? null : t.id)} className="flex w-full items-center justify-between gap-3 px-5 py-4 text-left">
                  <div>
                    <b className="text-sm">{t.subject}</b>
                    <p className="text-[11px] text-dim">
                      {t.profiles?.[0]?.full_name ?? t.user_id.slice(0, 8)} · {t.category} · {msgs.length} pesan
                    </p>
                  </div>
                  <span className={`rounded-full px-2.5 py-1 text-[11px] font-semibold ${STATUS_CLS[t.status] ?? STATUS_CLS.closed}`}>
                    {t.status}
                  </span>
                </button>
                {open && (
                  <div className="border-t border-white/10">
                    <div className="flex flex-col gap-3 px-5 py-4">
                      {msgs.map((m) => (
                        <div key={m.id} className={`max-w-[85%] rounded-2xl px-4 py-2.5 text-sm ${m.is_staff ? 'self-end bg-neon-cyan/10' : 'self-start bg-white/5'}`}>
                          <p className="whitespace-pre-wrap">{m.body}</p>
                          {m.attachments?.length > 0 && (
                            <a href={m.attachments[0].url} target="_blank" rel="noreferrer" className="mt-1 block text-xs text-neon-cyan underline">
                              Lihat lampiran
                            </a>
                          )}
                          <p className="mt-1 text-[10px] text-dim">
                            {m.is_staff ? 'Support' : 'Pelanggan'} · {new Date(m.created_at).toLocaleString('id-ID', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}
                          </p>
                        </div>
                      ))}
                    </div>
                    <form action={replyAction} className="flex gap-2 border-t border-white/10 px-5 py-3">
                      <input type="hidden" name="ticket_id" value={t.id} />
                      <input name="body" placeholder="Tulis balasan…" className={inputCls} required minLength={2} />
                      <button className="whitespace-nowrap rounded-xl bg-gradient-to-r from-neon-cyan to-neon-violet px-4 py-2.5 text-sm font-semibold text-navy">
                        Balas
                      </button>
                    </form>
                    <div className="flex flex-wrap items-center gap-2 px-5 pb-4">
                      {(['pending', 'resolved', 'closed'] as const).map((s) => (
                        <button key={s} formAction={statusAction} name="status" value={s}
                          className="rounded-lg border border-white/15 px-3 py-1.5 text-xs text-muted hover:text-ink">
                          Tandai {s}
                        </button>
                      ))}
                      <div className="ml-auto"><Notice state={openId === t.id ? replyState ?? statusState : null} /></div>
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}