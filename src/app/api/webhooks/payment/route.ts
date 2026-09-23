import { NextRequest, NextResponse } from 'next/server';
import { createAdminClient } from '@/lib/supabase/admin';
import crypto from 'crypto';

/**
 * Webhook payment gateway (Midtrans/Xendit/Duitku).
 * Prinsip PRD #20:
 *  1. Verifikasi signature — JANGAN percaya body mentah.
 *  2. Cek order_id ke tabel payments (idempotent).
 *  3. Update payment → invoice → extend subscription — semua via service role.
 * Return 200 hanya setelah diproses; gateway akan retry jika gagal.
 */
export async function POST(req: NextRequest) {
  const secret = process.env.PAYMENT_WEBHOOK_SECRET!;
  const signature = req.headers.get('x-signature') ?? '';
  const raw = await req.text();

  const expected = crypto.createHmac('sha256', secret).update(raw).digest('hex');
  if (!signature || !crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) {
    return NextResponse.json({ error: 'invalid signature' }, { status: 401 });
  }

  const event = JSON.parse(raw) as {
    gateway_ref: string;
    status: 'paid' | 'failed' | 'expired' | 'refunded';
    payment_method?: string;
  };

  const admin = createAdminClient();

  // 1. Temukan payment — idempotent
  const { data: payment, error: e1 } = await admin
    .from('payments')
    .select('id, user_id, invoice_id, subscription_id, status, amount')
    .eq('gateway_ref', event.gateway_ref)
    .single();
  if (e1 || !payment) return NextResponse.json({ error: 'payment not found' }, { status: 404 });
  if (payment.status === 'paid') return NextResponse.json({ ok: true, already: true });

  // 2. Update payment
  await admin.from('payments').update({
    status: event.status,
    payment_method: event.payment_method ?? null,
    paid_at: event.status === 'paid' ? new Date().toISOString() : null,
  }).eq('id', payment.id);

  if (event.status === 'paid') {
    // 3. Tandai invoice lunas
    if (payment.invoice_id) {
      await admin.from('invoices').update({ status: 'paid', paid_at: new Date().toISOString() })
        .eq('id', payment.invoice_id);
    }
    // 4. Perpanjang subscription + website
    if (payment.subscription_id) {
      const { data: sub } = await admin.from('subscriptions')
        .select('id, current_period_end, billing_period, website_id').eq('id', payment.subscription_id).single();
      if (sub) {
        const days = sub.billing_period === 'yearly' ? 365 : 30;
        const base = new Date(sub.current_period_end) > new Date() ? new Date(sub.current_period_end) : new Date();
        const nextEnd = new Date(base.getTime() + days * 86400000).toISOString();
        await admin.from('subscriptions').update({
          status: 'active', current_period_start: new Date().toISOString(), current_period_end: nextEnd,
        }).eq('id', sub.id);
        if (sub.website_id) {
          await admin.from('websites').update({ status: 'active', expires_at: nextEnd }).eq('id', sub.website_id);
        }
      }
    }
    // 5. Notifikasi + audit log
    await admin.from('notifications').insert({
      user_id: payment.user_id ?? undefined, title: 'Pembayaran Berhasil',
      body: 'Langganan Anda telah diperpanjang.', type: 'payment_success',
    } as never);
    await admin.from('activity_logs').insert({
      action: 'payment_paid', target_type: 'payment', target_id: payment.id,
      metadata: { amount: payment.amount },
    } as never);
  }

  return NextResponse.json({ ok: true });
}
