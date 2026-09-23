'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { requireUser, requireStaff } from '@/lib/auth';
import { createClient } from '@/lib/supabase/server';

export type ActionState = { ok: boolean; message: string };

const ticketSchema = z.object({
  subject: z.string().min(4).max(120),
  category: z.enum(['general', 'payment', 'technical', 'domain']),
  message: z.string().min(5).max(2000),
  attachment_path: z.string().max(300).optional(),
});

/** User membuat tiket (termasuk bukti pembayaran manual, PRD #20/#35). */
export async function createTicket(_prev: ActionState | null, formData: FormData): Promise<ActionState> {
  const user = await requireUser('/app/support');
  const parsed = ticketSchema.safeParse(Object.fromEntries(formData.entries()));
  if (!parsed.success) {
    return { ok: false, message: parsed.error.issues[0]?.message ?? 'Data tiket tidak valid.' };
  }
  const { subject, category, message, attachment_path } = parsed.data;

  // Path bukti harus di folder Storage milik user sendiri (PRD #43) —
  // file sudah ter-upload langsung dari browser dengan RLS storage policy.
  const attachments: { path: string }[] = [];
  if (attachment_path && attachment_path.length > 0) {
    if (!attachment_path.startsWith(`proofs/${user.id}/`)) {
      return { ok: false, message: 'Path bukti tidak valid.' };
    }
    attachments.push({ path: attachment_path });
  }

  const supabase = await createClient();
  const { data: ticket, error } = await supabase
    .from('tickets')
    .insert({ user_id: user.id, subject, category, status: 'open' })
    .select('id')
    .single();
  if (error || !ticket) return { ok: false, message: error?.message ?? 'Gagal membuat tiket.' };

  const { error: e2 } = await supabase.from('ticket_messages').insert({
    ticket_id: ticket.id,
    sender_id: user.id,
    is_staff: false,
    body: message,
    attachments,
  });
  if (e2) return { ok: false, message: e2.message };

  revalidatePath('/app/support');
  // Trigger notify_admin_new_ticket sudah mengirim notifikasi broadcast ke staff.
  return { ok: true, message: 'Tiket terkirim — tim support akan membalas di sini.' };
}

/** User membalas tiketnya sendiri. */
export async function sendTicketMessage(_prev: ActionState | null, formData: FormData): Promise<ActionState> {
  const user = await requireUser('/app/support');
  const ticketId = String(formData.get('ticket_id') ?? '');
  const body = String(formData.get('body') ?? '').trim();
  if (!ticketId || body.length < 2) return { ok: false, message: 'Pesan minimal 2 karakter.' };

  const supabase = await createClient();
  const { error } = await supabase.from('ticket_messages').insert({
    ticket_id: ticketId, sender_id: user.id, is_staff: false, body, attachments: [],
  });
  if (error) return { ok: false, message: error.message };

  await supabase.from('tickets').update({ status: 'open' }).eq('id', ticketId);
  revalidatePath('/app/support');
  return { ok: true, message: 'Pesan terkirim.' };
}

/* ── Sisi admin ─────────────────────────────────────────────────── */

/** Admin membalas tiket user. */
export async function replyTicket(_prev: ActionState | null, formData: FormData): Promise<ActionState> {
  const staff = await requireStaff('/admin/tickets');
  const ticketId = String(formData.get('ticket_id') ?? '');
  const body = String(formData.get('body') ?? '').trim();
  if (!ticketId || body.length < 2) return { ok: false, message: 'Pesan minimal 2 karakter.' };

  const supabase = await createClient();
  const { error } = await supabase.from('ticket_messages').insert({
    ticket_id: ticketId, sender_id: staff.id, is_staff: true, body, attachments: [],
  });
  if (error) return { ok: false, message: error.message };

  await supabase.from('tickets').update({ status: 'pending' }).eq('id', ticketId);
  revalidatePath('/admin/tickets');
  return { ok: true, message: 'Balasan terkirim.' };
}

export async function setTicketStatus(_prev: ActionState | null, formData: FormData): Promise<ActionState> {
  await requireStaff('/admin/tickets');
  const ticketId = String(formData.get('ticket_id') ?? '');
  const status = String(formData.get('status') ?? '');
  if (!['open', 'pending', 'resolved', 'closed'].includes(status)) {
    return { ok: false, message: 'Status tidak valid.' };
  }
  const supabase = await createClient();
  const { error } = await supabase.from('tickets').update({ status }).eq('id', ticketId);
  if (error) return { ok: false, message: error.message };
  revalidatePath('/admin/tickets');
  return { ok: true, message: `Status tiket → ${status}.` };
}

/**
 * Verifikasi pembayaran manual — memanggil verify_manual_payment()
 * (security definer, cek is_staff di dalam SQL). Satu-satunya jalur
 * yang mengubah status pembayaran pada mode manual.
 */
export async function verifyPayment(_prev: ActionState | null, formData: FormData): Promise<ActionState> {
  await requireStaff('/admin/tickets');
  const paymentId = String(formData.get('payment_id') ?? '');
  const note = String(formData.get('note') ?? '').trim() || null;
  if (!paymentId) return { ok: false, message: 'ID pembayaran tidak ada.' };

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('verify_manual_payment', {
    p_payment_id: paymentId, p_note: note,
  });
  if (error) return { ok: false, message: error.message };
  const r = data as { ok: boolean; already?: boolean };
  if (!r.ok) return { ok: false, message: 'Pembayaran tidak ditemukan.' };

  revalidatePath('/admin/tickets');
  revalidatePath('/admin/payments');
  return { ok: true, message: r.already ? 'Pembayaran sudah diverifikasi sebelumnya.' : 'Pembayaran diverifikasi — langganan diperpanjang.' };
}