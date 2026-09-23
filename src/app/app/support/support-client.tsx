'use client';

import { useActionState, useState } from 'react';
import { createTicket, sendTicketMessage, type ActionState } from '@/lib/support-actions';

type Ticket = { id: string; subject: string; category: string; status: string; created_at: string };
type Message = {
  id: string;
  ticket_id: string;
  sender_id: string;
  is_staff: boolean;
  body: string;
  attachments: { url: string }[];
  created_at: string;
};

const inputCls =
  'w-full rounded-xl border border-white/20 bg-white/5 px-3 py-2.5 text-sm text-ink outline-none focus:border-neon-cyan';
const labelCls = 'mb-1.5 block text-xs font-semibold text-muted';

const STATUS_CLS: Record<string, string> = {
  open: 'bg-neon-cyan/10 text-neon-cyan',
  pending: 'bg-amber-400/10 text-amber-300',
  resolved: 'bg-neon-mint/10 text-neon-mint',
  closed: 'bg-white/5 text-dim',
};

function Notice({ state }: { state: ActionState | null }) {
  if (!state) return null;
  return <p className={`mt-2 text-xs ${state.ok ? 'text-neon-mint' : 'text-rose-400'}`}>{state.message}</p>;
}

export default function SupportClient({
  tickets,
  messages,
  prefillSubject,
}: {
  tickets: Ticket[];
  messages: Message[];
  prefillSubject: string | null;
}) {
  const [openId, setOpenId] = useState<string | null>(tickets[0]?.id ?? null);
  const [newState, newAction] = useActionState<ActionState | null, FormData>(createTicket, null);
  const [msgState, msgAction] = useActionState<ActionState | null, FormData>(sendTicketMessage, null);

  return (
    <div className="grid gap-6 lg:grid-cols-[1fr_360px]">
      {/* daftar tiket */}
      <div>
        {tickets.length === 0 && (
          <div className="rounded-2xl border border-dashed border-white/15 bg-navy-3/50 p-8 text-center text-sm text-muted">
            Belum ada tiket. Buat tiket pertama Anda di panel sebelah kanan.
          </div>
        )}
        <div className="flex flex-col gap-3">
          {tickets.map((t) => {
            const msgs = messages.filter((m) => m.ticket_id === t.id);
            const open = openId === t.id;
            return (
              <div key={t.id} className="overflow-hidden rounded-2xl border border-white/10 bg-navy-3/70">
                <button
                  onClick={() => setOpenId(open ? null : t.id)}
                  className="flex w-full items-center justify-between gap-3 px-5 py-4 text-left"
                >
                  <div>
                    <b className="text-sm">{t.subject}</b>
                    <p className="text-[11px] text-dim">
                      {t.category} · {new Date(t.created_at).toLocaleDateString('id-ID', { day: 'numeric', month: 'short', year: 'numeric' })} · {msgs.length} pesan
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
                              Lihat lampiran (bukti pembayaran)
                            </a>
                          )}
                          <p className="mt-1 text-[10px] text-dim">
                            {m.is_staff ? 'Support' : 'Anda'} · {new Date(m.created_at).toLocaleString('id-ID', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}
                          </p>
                        </div>
                      ))}
                    </div>
                    <form action={msgAction} className="flex gap-2 border-t border-white/10 px-5 py-3">
                      <input type="hidden" name="ticket_id" value={t.id} />
                      <input name="body" placeholder="Tulis balasan…" className={inputCls} required minLength={2} />
                      <button className="whitespace-nowrap rounded-xl bg-gradient-to-r from-neon-cyan to-neon-violet px-4 py-2.5 text-sm font-semibold text-navy">
                        Kirim
                      </button>
                    </form>
                    <div className="px-5 pb-3"><Notice state={openId === t.id ? msgState : null} /></div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>

      {/* tiket baru */}
      <form action={newAction} className="h-fit rounded-2xl border border-white/10 bg-navy-3/70 p-6">
        <h2 className="mb-4 text-xs font-semibold uppercase tracking-wider text-dim">Tiket baru</h2>
        <div className="mb-3">
          <label className={labelCls} htmlFor="subject">Subjek</label>
          <input id="subject" name="subject" key={prefillSubject ?? 's'} defaultValue={prefillSubject ?? ''} placeholder="mis. Bukti Pembayaran INV-202609-001" className={inputCls} required minLength={4} />
        </div>
        <div className="mb-3">
          <label className={labelCls} htmlFor="category">Kategori</label>
          <select id="category" name="category" defaultValue={prefillSubject ? 'payment' : 'general'} className={inputCls}>
            <option value="general">Umum</option>
            <option value="payment">Pembayaran</option>
            <option value="technical">Teknis</option>
            <option value="domain">Domain</option>
          </select>
        </div>
        <div className="mb-3">
          <label className={labelCls} htmlFor="message">Pesan</label>
          <textarea id="message" name="message" rows={4} placeholder="Jelaskan kebutuhan Anda. Untuk pembayaran manual: tulis nominal + tanggal transfer, lalu tempel tautan gambar bukti di kolom lampiran." className={`${inputCls} leading-relaxed`} required minLength={5} />
        </div>
        <div className="mb-4">
          <label className={labelCls} htmlFor="attachment_url">Tautan bukti (URL gambar, opsional)</label>
          <input id="attachment_url" name="attachment_url" type="url" placeholder="https://…/bukti-transfer.jpg" className={inputCls} />
        </div>
        <button className="w-full rounded-xl bg-gradient-to-r from-neon-cyan to-neon-violet py-3 text-sm font-semibold text-navy">
          Kirim Tiket
        </button>
        <p className="mt-2 text-[11px] text-dim">Tiket baru otomatis memberi notifikasi ke admin.</p>
        <Notice state={newState} />
      </form>
    </div>
  );
}