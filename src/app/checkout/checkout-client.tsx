'use client';

import { useActionState, useEffect, useState } from 'react';
import { checkCoupon, submitCheckout, type ActionState } from './actions';

type PlanOption = {
  id: string;
  name: string;
  description: string | null;
  price_monthly: number;
  price_yearly: number | null;
};

type Period = 'monthly' | 'yearly';

const cardCls =
  'cursor-pointer rounded-2xl border p-5 text-left transition';
const inputCls =
  'w-full rounded-xl border border-white/20 bg-white/5 px-3 py-2.5 text-sm text-ink outline-none focus:border-neon-cyan';

function fmt(n: number) {
  return 'Rp' + Number(n).toLocaleString('id-ID');
}

function Notice({ state }: { state: ActionState | null }) {
  if (!state) return null;
  return (
    <p className={`mt-2 text-xs ${state.ok ? 'text-neon-mint' : 'text-rose-400'}`}>
      {state.message}
    </p>
  );
}

export default function CheckoutClient({
  plans,
  defaultPlanId,
  manual,
}: {
  plans: PlanOption[];
  defaultPlanId: string | null;
  manual: { enabled: boolean; bank: string; account: string; holder: string; instructions: string };
}) {
  const [planId, setPlanId] = useState<string>(defaultPlanId ?? plans[0]?.id ?? '');
  const [period, setPeriod] = useState<Period>('monthly');
  const [code, setCode] = useState('');
  const [applied, setApplied] = useState<{ code: string; discount: number } | null>(null);

  const [couponState, couponAction] = useActionState<ActionState | null, FormData>(checkCoupon, null);
  const [checkoutState, checkoutAction] = useActionState<ActionState | null, FormData>(submitCheckout, null);

  const plan = plans.find((p) => p.id === planId);
  const base = plan
    ? period === 'yearly'
      ? (plan.price_yearly ?? plan.price_monthly * 12)
      : plan.price_monthly
    : 0;
  // Diskon tampil segera setelah server memvalidasi kupon
  const discount = couponState?.ok && couponState.data?.discount ? couponState.data.discount : 0;
  const total = applied && applied.code === code.trim().toUpperCase() ? base - applied.discount : base;

  // Simpan hasil validasi kupon yang berhasil
  useEffect(() => {
    if (couponState?.ok && couponState.data?.code) {
      setApplied({ code: couponState.data.code, discount: couponState.data.discount ?? 0 });
    }
  }, [couponState]);

  // Kupon dibatalkan otomatis saat paket/periode berubah (validasi bergantung keduanya)
  useEffect(() => {
    setApplied(null);
  }, [planId, period]);

  const done = checkoutState?.ok && checkoutState.data?.invoiceNumber;

  if (done) {
    return (
      <div className="mx-auto max-w-lg rounded-2xl border border-neon-mint/30 bg-navy-3/70 p-8 text-center">
        <div className="mx-auto mb-4 grid h-14 w-14 place-items-center rounded-full bg-neon-mint/10">
          <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#5CF2C4" strokeWidth="2.4">
            <path d="M20 6 9 17l-5-5" />
          </svg>
        </div>
        <h2 className="font-display text-xl font-bold">Checkout berhasil dibuat</h2>
        <p className="mt-1 text-sm text-muted">
          Invoice <b className="font-mono text-ink">{checkoutState.data?.invoiceNumber}</b> menunggu pembayaran
          sebesar <b className="text-ink">{fmt(checkoutState.data?.total ?? 0)}</b>.
        </p>

        {manual.enabled && (
          <div className="mt-5 rounded-xl border border-dashed border-neon-cyan/40 bg-neon-cyan/5 p-4 text-left text-sm">
            <p className="mb-2 font-mono text-[10px] uppercase tracking-wider text-neon-cyan">Instruksi Pembayaran</p>
            <p className="text-muted">{manual.instructions}</p>
            <div className="mt-3 flex flex-wrap items-center justify-between gap-2 rounded-lg bg-white/5 px-3 py-2.5">
              <div>
                <b className="font-display">{manual.bank}</b>
                <p className="font-mono text-base text-ink">{manual.account}</p>
                <p className="text-xs text-dim">a/n {manual.holder}</p>
              </div>
              <b className="font-display text-lg">{fmt(checkoutState.data?.total ?? 0)}</b>
            </div>
            <a
              href={`/app/support?prefill=${encodeURIComponent('Bukti Pembayaran ' + (checkoutState.data?.invoiceNumber ?? ''))}`}
              className="mt-3 block w-full rounded-xl bg-gradient-to-r from-neon-cyan to-neon-violet py-2.5 text-center text-sm font-semibold text-navy"
            >
              Kirim Bukti via Support
            </a>
            <p className="mt-2 text-center text-[11px] text-dim">
              Admin memverifikasi bukti Anda, lalu langganan aktif otomatis.
            </p>
          </div>
        )}
        <a href="/app/billing" className="mt-5 inline-block rounded-xl border border-white/20 px-6 py-2.5 text-sm text-muted hover:text-ink">
          Lihat tagihan di Billing
        </a>
      </div>
    );
  }

  return (
    <div className="grid gap-6 lg:grid-cols-[1fr_360px]">
      {/* pilihan paket */}
      <div>
        <h2 className="mb-3 text-xs font-semibold uppercase tracking-wider text-dim">1 · Pilih paket</h2>
        <div className="grid gap-3 sm:grid-cols-3">
          {plans.map((p) => (
            <button
              key={p.id}
              type="button"
              onClick={() => setPlanId(p.id)}
              className={`${cardCls} ${planId === p.id ? 'border-neon-cyan/60 bg-neon-cyan/5' : 'border-white/10 bg-navy-3/70 hover:border-white/25'}`}
            >
              <b className="font-display text-lg">{p.name}</b>
              <p className="mt-1 text-[11px] leading-snug text-dim">{p.description}</p>
              <p className="mt-3 font-display text-xl font-bold">
                {fmt(p.price_monthly)}
                <span className="text-xs font-normal text-dim">/bln</span>
              </p>
            </button>
          ))}
        </div>

        <h2 className="mb-3 mt-6 text-xs font-semibold uppercase tracking-wider text-dim">2 · Periode</h2>
        <div className="flex gap-2">
          {(['monthly', 'yearly'] as Period[]).map((per) => (
            <button
              key={per}
              type="button"
              onClick={() => setPeriod(per)}
              className={`rounded-full border px-4 py-2 text-xs font-semibold transition ${
                period === per
                  ? 'border-transparent bg-gradient-to-r from-neon-cyan to-neon-violet text-navy'
                  : 'border-white/20 text-muted hover:text-ink'
              }`}
            >
              {per === 'monthly' ? 'Bulanan' : 'Tahunan (hemat 2 bulan)'}
            </button>
          ))}
        </div>
      </div>

      {/* ringkasan + kupon */}
      <form action={checkoutAction} className="h-fit rounded-2xl border border-white/10 bg-navy-3/70 p-6">
        <h2 className="mb-4 text-xs font-semibold uppercase tracking-wider text-dim">Ringkasan pesanan</h2>
        <input type="hidden" name="plan_id" value={planId} />
        <input type="hidden" name="period" value={period} />
        <input type="hidden" name="code" value={applied?.code ?? ''} />

        <div className="mb-4 flex items-center justify-between text-sm">
          <span className="text-muted">
            {plan?.name} · {period === 'monthly' ? 'Bulanan' : 'Tahunan'}
          </span>
          <span>{fmt(base)}</span>
        </div>

        {/* kupon */}
        <div className="mb-4">
          <label className="mb-1.5 block text-xs font-semibold text-muted" htmlFor="coupon">Kode kupon</label>
          {applied ? (
            <div className="flex items-center justify-between rounded-xl border border-neon-mint/30 bg-neon-mint/5 px-3 py-2.5 text-sm">
              <span className="font-mono text-neon-mint">{applied.code}</span>
              <button
                type="button"
                onClick={() => {
                  setApplied(null);
                  setCode('');
                }}
                className="text-xs text-dim hover:text-rose-300"
              >
                Hapus
              </button>
            </div>
          ) : (
            <div className="flex gap-2">
              <input
                id="coupon"
                value={code}
                onChange={(e) => setCode(e.target.value.toUpperCase())}
                placeholder="WELCOME50"
                className={`${inputCls} font-mono uppercase`}
              />
              <button
                formAction={couponAction}
                name="plan_id"
                value={planId}
                className="whitespace-nowrap rounded-xl border border-neon-cyan/40 bg-neon-cyan/10 px-4 py-2.5 text-sm font-semibold text-neon-cyan"
              >
                Terapkan
              </button>
            </div>
          )}
          {/* hidden inputs agar server tahu konteks validasi */}
          {applied && <input type="hidden" name="code_check" value={applied.code} />}
          <input type="hidden" name="period_check" value={period} />
          <Notice state={couponState} />
        </div>

        <div className="mb-5 border-t border-white/10 pt-4 text-sm">
          <div className="flex justify-between text-muted">
            <span>Subtotal</span>
            <span>{fmt(base)}</span>
          </div>
          <div className="mt-2 flex justify-between text-muted">
            <span>Diskon {applied ? `(${applied.code})` : ''}</span>
            <span className={discount ? 'text-neon-mint' : ''}>
              {discount ? `−${fmt(discount)}` : 'Rp0'}
            </span>
          </div>
          <div className="mt-3 flex justify-between font-display text-lg font-bold">
            <span>Total</span>
            <span>{fmt(total)}</span>
          </div>
        </div>

        <button
          type="submit"
          className="w-full rounded-xl bg-gradient-to-r from-neon-cyan to-neon-violet py-3 text-sm font-semibold text-navy"
        >
          Bayar Sekarang
        </button>
        <Notice state={checkoutState} />
        <p className="mt-3 text-center text-[11px] text-dim">
          Pembayaran manual — transfer lalu kirim bukti via Support. Status diverifikasi admin
          (server-side, PRD #20).
        </p>
      </form>
    </div>
  );
}