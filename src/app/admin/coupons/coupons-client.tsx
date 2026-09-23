'use client';

import { useActionState, useEffect, useState } from 'react';
import { saveCoupon, toggleCoupon, deleteCoupon, testCoupon, type ActionState } from './actions';

type Coupon = {
  id: string;
  code: string;
  type: 'percentage' | 'fixed_amount';
  value: number;
  min_payment: number;
  max_usage: number | null;
  used_count: number;
  plan_restriction: string | null;
  expires_at: string | null;
  is_active: boolean;
  created_at: string;
};

type Plan = { id: string; name: string };
type Redemption = {
  id: string;
  coupon_id: string;
  user_id: string;
  discount_amount: number;
  redeemed_at: string;
};

type DailyPoint = { date: string; count: number; discount: number };
type TopCoupon = { coupon_id: string; count: number; discount: number };

/** Grafik batang SVG penebusan harian 30 hari — tanpa dependensi. */
function RedemptionsChart({ daily }: { daily: DailyPoint[] }) {
  const max = Math.max(1, ...daily.map((d) => d.count));
  const W = 640, H = 140, PAD_B = 18;
  const bw = W / daily.length;
  const fmtDay = (iso: string) =>
    new Date(iso + 'T00:00:00').toLocaleDateString('id-ID', { day: 'numeric', month: 'short' });
  const totalRedemptions = daily.reduce((s, d) => s + d.count, 0);
  const totalDiscount = daily.reduce((s, d) => s + d.discount, 0);

  return (
    <div className="mb-8 rounded-2xl border border-white/10 bg-navy-3/70 p-5">
      <div className="mb-3 flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="font-display text-sm font-semibold uppercase tracking-wider text-dim">
          Penebusan 30 Hari Terakhir
        </h2>
        <p className="text-xs text-muted">
          <b className="text-ink">{totalRedemptions}</b> penebusan · diskon{' '}
          <b className="text-neon-mint">{fmtIDR(totalDiscount)}</b>
        </p>
      </div>
      <svg viewBox={`0 0 ${W} ${H + PAD_B}`} className="h-auto w-full" role="img" aria-label="Grafik penebusan kupon harian">
        <defs>
          <linearGradient id="barGrad" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#4DE3FF" />
            <stop offset="100%" stopColor="#8B7CFF" />
          </linearGradient>
        </defs>
        {daily.map((d, i) => {
          const h = d.count === 0 ? 0 : Math.max(3, (d.count / max) * (H - 8));
          const x = i * bw + bw * 0.15;
          const y = H - h;
          return (
            <g key={d.date}>
              <rect x={x} y={y} width={bw * 0.7} height={h} rx={Math.min(3, bw * 0.3)} fill="url(#barGrad)" opacity={d.count ? 1 : 0.25}>
                <title>{`${fmtDay(d.date)}: ${d.count} penebusan (diskon ${fmtIDR(d.discount)})`}</title>
              </rect>
            </g>
          );
        })}
        {/* garis dasar + label awal/akhir */}
        <line x1="0" y1={H} x2={W} y2={H} stroke="rgba(140,160,220,.25)" strokeWidth="1" />
        <text x="0" y={H + 13} fill="#5C6A93" fontSize="9">{fmtDay(daily[0].date)}</text>
        <text x={W} y={H + 13} fill="#5C6A93" fontSize="9" textAnchor="end">{fmtDay(daily[daily.length - 1].date)}</text>
      </svg>
      <p className="mt-1 text-[11px] text-dim">Arahkan kursor ke batang untuk rincian harian.</p>
    </div>
  );
}

/** Peringkat kupon berdasarkan penebusan. */
function TopCoupons({ top, codes }: { top: TopCoupon[]; codes: Map<string, string> }) {
  if (top.length === 0) return null;
  const max = Math.max(...top.map((t) => t.count));
  return (
    <div className="mb-8 rounded-2xl border border-white/10 bg-navy-3/70 p-5">
      <h2 className="mb-3 font-display text-sm font-semibold uppercase tracking-wider text-dim">
        Kupon Terpopuler
      </h2>
      <div className="flex flex-col gap-2.5">
        {top.map((t) => (
          <div key={t.coupon_id} className="flex items-center gap-3 text-sm">
            <span className="w-32 shrink-0 truncate font-mono text-xs font-semibold">{codes.get(t.coupon_id) ?? '—'}</span>
            <span className="h-2.5 flex-1 overflow-hidden rounded-full bg-white/5">
              <span
                className="block h-full rounded-full bg-gradient-to-r from-neon-cyan to-neon-violet"
                style={{ width: `${Math.max(4, (t.count / max) * 100)}%` }}
              />
            </span>
            <span className="w-24 shrink-0 text-right text-xs text-muted">
              {t.count}× · <span className="text-neon-mint">{fmtIDR(t.discount)}</span>
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

const inputCls =
  'w-full rounded-xl border border-white/20 bg-white/5 px-3 py-2.5 text-sm text-ink outline-none focus:border-neon-cyan';
const labelCls = 'mb-1.5 block text-xs font-semibold text-muted';

function fmtIDR(n: number) {
  return 'Rp' + n.toLocaleString('id-ID');
}
function fmtDate(iso: string | null) {
  if (!iso) return '—';
  return new Date(iso).toLocaleDateString('id-ID', { day: 'numeric', month: 'short', year: 'numeric' });
}
function expired(iso: string | null) {
  return !!iso && new Date(iso) < new Date();
}

function Notice({ state }: { state: ActionState | null }) {
  if (!state) return null;
  return <p className={`mt-2 text-xs ${state.ok ? 'text-neon-mint' : 'text-amber-400'}`}>{state.message}</p>;
}

type FormCoupon = Omit<Coupon, 'expires_at'> & { expires_at: string };

const EMPTY: FormCoupon = {
  id: '',
  code: '',
  type: 'percentage',
  value: 10,
  min_payment: 0,
  max_usage: null,
  used_count: 0,
  plan_restriction: null,
  expires_at: '',
  is_active: true,
  created_at: '',
};

export default function CouponsClient({
  coupons,
  plans,
  redemptions,
  daily,
  topCoupons,
}: {
  coupons: Coupon[];
  plans: Plan[];
  redemptions: Redemption[];
  daily: DailyPoint[];
  topCoupons: TopCoupon[];
}) {
  const [form, setForm] = useState<FormCoupon>(EMPTY);
  const [mode, setMode] = useState<'form' | 'list' | 'test'>('list');
  const [couponState, couponAction] = useActionState<ActionState | null, FormData>(saveCoupon, null);
  const [toggleState, toggleAction] = useActionState<ActionState | null, FormData>(toggleCoupon, null);
  const [deleteState, deleteAction] = useActionState<ActionState | null, FormData>(deleteCoupon, null);
  const [testState, testAction] = useActionState<ActionState | null, FormData>(testCoupon, null);
  const [testCode, setTestCode] = useState('');

  useEffect(() => {
    if (couponState?.ok) {
      setMode('list');
      setForm(EMPTY);
    }
  }, [couponState]);

  const planName = (id: string | null) => plans.find((p) => p.id === id)?.name ?? 'Semua paket';
  const activeCount = coupons.filter((c) => c.is_active && !expired(c.expires_at)).length;

  return (
    <div>
      {/* ringkasan */}
      <div className="mb-6 grid grid-cols-3 gap-3">
        {[
          { label: 'Total kupon', v: coupons.length },
          { label: 'Aktif', v: activeCount },
          { label: 'Penebusan terbaru', v: redemptions.length },
        ].map((s) => (
          <div key={s.label} className="rounded-2xl border border-white/10 bg-navy-3/70 p-4">
            <b className="font-display text-2xl">{s.v}</b>
            <p className="text-xs text-dim">{s.label}</p>
          </div>
        ))}
      </div>

      <div className="mb-4 flex gap-2">
        <button
          onClick={() => {
            setForm(EMPTY);
            setMode('form');
          }}
          className={`rounded-full border px-4 py-2 text-xs font-semibold ${
            mode === 'form'
              ? 'border-transparent bg-gradient-to-r from-neon-cyan to-neon-violet text-navy'
              : 'border-white/20 text-muted hover:text-ink'
          }`}
        >
          + Kupon Baru
        </button>
        <button
          onClick={() => setMode('list')}
          className={`rounded-full border px-4 py-2 text-xs font-semibold ${
            mode === 'list'
              ? 'border-transparent bg-gradient-to-r from-neon-cyan to-neon-violet text-navy'
              : 'border-white/20 text-muted hover:text-ink'
          }`}
        >
          Daftar Kupon
        </button>
        <button
          onClick={() => setMode('test')}
          className={`rounded-full border px-4 py-2 text-xs font-semibold ${
            mode === 'test'
              ? 'border-transparent bg-gradient-to-r from-neon-cyan to-neon-violet text-navy'
              : 'border-white/20 text-muted hover:text-ink'
          }`}
        >
          Uji Validasi Kode
        </button>
      </div>

      {/* ── UJI VALIDASI KODE ── */}
      {mode === 'test' && (
        <form action={testAction} className="rounded-2xl border border-white/10 bg-navy-3/70 p-6">
          <p className="mb-4 text-xs text-dim">
            Simulasi lewat fungsi <code className="font-mono text-neon-cyan">validate_coupon</code> — sama seperti
            alur checkout nyata, tetapi tidak membuat invoice atau menghitung pemakaian.
          </p>
          <div className="grid gap-4 sm:grid-cols-3">
            <div>
              <label className={labelCls} htmlFor="test_code">Kode</label>
              <input
                id="test_code"
                name="test_code"
                value={testCode}
                onChange={(e) => setTestCode(e.target.value.toUpperCase())}
                placeholder="WELCOME50"
                className={`${inputCls} font-mono uppercase`}
              />
            </div>
            <div>
              <label className={labelCls} htmlFor="test_plan">Paket</label>
              <select id="test_plan" name="test_plan" defaultValue={plans[0]?.id ?? ''} className={inputCls}>
                {plans.map((p) => (
                  <option key={p.id} value={p.id}>{p.name}</option>
                ))}
              </select>
            </div>
            <div>
              <label className={labelCls} htmlFor="test_period">Periode</label>
              <select id="test_period" name="test_period" className={inputCls}>
                <option value="monthly">Bulanan</option>
                <option value="yearly">Tahunan</option>
              </select>
            </div>
          </div>
          <div className="mt-5 flex flex-wrap items-center gap-3">
            <button type="submit" className="rounded-xl bg-gradient-to-r from-neon-cyan to-neon-violet px-6 py-2.5 text-sm font-semibold text-navy">
              Cek Kode
            </button>
            {/* quick-fill dari daftar kupon */}
            <span className="flex flex-wrap gap-1.5">
              {coupons.slice(0, 6).map((c) => (
                <button
                  key={c.id}
                  type="button"
                  onClick={() => setTestCode(c.code)}
                  className="rounded-lg border border-white/15 px-2.5 py-1.5 font-mono text-[11px] text-muted hover:text-ink"
                >
                  {c.code}
                </button>
              ))}
            </span>
          </div>
          <Notice state={testState} />
          {testState?.data && (
            <div className="mt-4 grid grid-cols-3 gap-3 border-t border-white/10 pt-4 text-sm">
              <div>
                <p className="text-[11px] uppercase tracking-wider text-dim">Subtotal</p>
                <b className="font-display">{fmtIDR(testState.data.base ?? 0)}</b>
              </div>
              <div>
                <p className="text-[11px] uppercase tracking-wider text-dim">Diskon</p>
                <b className={`font-display ${testState.ok ? 'text-neon-mint' : ''}`}>
                  {testState.ok ? `−${fmtIDR(testState.data.discount ?? 0)}` : 'Rp0'}
                </b>
              </div>
              <div>
                <p className="text-[11px] uppercase tracking-wider text-dim">Total setelah kupon</p>
                <b className="font-display">{fmtIDR(testState.data.total ?? 0)}</b>
              </div>
            </div>
          )}
        </form>
      )}

      {/* ── FORM ── */}
      {mode === 'form' && (
        <form action={couponAction} key={form.id || 'new'} className="rounded-2xl border border-white/10 bg-navy-3/70 p-6">
          {form.id && <input type="hidden" name="id" value={form.id} />}
          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <label className={labelCls} htmlFor="code">Kode</label>
              <input
                id="code"
                name="code"
                defaultValue={form.code}
                placeholder="WELCOME50"
                className={`${inputCls} font-mono uppercase`}
              />
            </div>
            <div>
              <label className={labelCls} htmlFor="type">Tipe diskon</label>
              <select
                id="type"
                name="type"
                defaultValue={form.type}
                onChange={(e) => setForm((f) => ({ ...f, type: e.target.value as Coupon['type'] }))}
                className={inputCls}
              >
                <option value="percentage">Persentase (%)</option>
                <option value="fixed_amount">Nominal (Rp)</option>
              </select>
            </div>
            <div>
              <label className={labelCls} htmlFor="value">
                {form.type === 'percentage' ? 'Nilai (%)' : 'Nilai (Rp)'}
              </label>
              <input id="value" name="value" type="number" min={1} defaultValue={form.value} className={inputCls} />
            </div>
            <div>
              <label className={labelCls} htmlFor="min_payment">Minimum pembayaran (Rp, 0 = tanpa minimum)</label>
              <input id="min_payment" name="min_payment" type="number" min={0} defaultValue={form.min_payment} className={inputCls} />
            </div>
            <div>
              <label className={labelCls} htmlFor="max_usage">Maks. pemakaian (kosong = tanpa batas)</label>
              <input
                id="max_usage"
                name="max_usage"
                type="number"
                min={1}
                defaultValue={form.max_usage ?? ''}
                className={inputCls}
              />
            </div>
            <div>
              <label className={labelCls} htmlFor="plan_restriction">Batasi ke paket</label>
              <select id="plan_restriction" name="plan_restriction" defaultValue={form.plan_restriction ?? ''} className={inputCls}>
                <option value="">Semua paket</option>
                {plans.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className={labelCls} htmlFor="expires_at">Berlaku sampai</label>
              <input
                id="expires_at"
                name="expires_at"
                type="datetime-local"
                defaultValue={form.expires_at}
                className={inputCls}
              />
            </div>
            <div className="flex items-end pb-1">
              <label className="flex items-center gap-2 text-sm text-muted">
                <input type="checkbox" name="is_active" defaultChecked={form.is_active} />
                Kupon aktif
              </label>
            </div>
          </div>
          <div className="mt-6 flex gap-3">
            <button type="submit" className="rounded-xl bg-gradient-to-r from-neon-cyan to-neon-violet px-6 py-2.5 text-sm font-semibold text-navy">
              {form.id ? 'Simpan Perubahan' : 'Buat Kupon'}
            </button>
            <button
              type="button"
              onClick={() => {
                setMode('list');
                setForm(EMPTY);
              }}
              className="rounded-xl border border-white/20 px-5 py-2.5 text-sm text-muted"
            >
              Batal
            </button>
          </div>
          <Notice state={couponState} />
        </form>
      )}

      {/* ── LIST ── */}
      {mode === 'list' && (
        <div className="overflow-hidden rounded-2xl border border-white/10 bg-navy-3/70">
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b border-white/10 text-[11px] uppercase tracking-wider text-dim">
                <th className="px-4 py-3">Kode</th>
                <th className="px-4 py-3">Diskon</th>
                <th className="px-4 py-3">Pemakaian</th>
                <th className="px-4 py-3">Paket</th>
                <th className="px-4 py-3">Berlaku s.d.</th>
                <th className="px-4 py-3">Status</th>
                <th className="px-4 py-3 text-right">Aksi</th>
              </tr>
            </thead>
            <tbody>
              {coupons.length === 0 && (
                <tr>
                  <td colSpan={7} className="px-4 py-10 text-center text-muted">
                    Belum ada kupon. Buat satu dengan tombol <b>+ Kupon Baru</b>.
                  </td>
                </tr>
              )}
              {coupons.map((c) => {
                const isExpired = expired(c.expires_at);
                const exhausted = c.max_usage !== null && c.used_count >= c.max_usage;
                const effective = c.is_active && !isExpired && !exhausted;
                return (
                  <tr key={c.id} className="border-b border-white/5 last:border-0">
                    <td className="px-4 py-3 font-mono font-semibold">{c.code}</td>
                    <td className="px-4 py-3">
                      {c.type === 'percentage' ? `${c.value}%` : fmtIDR(c.value)}
                      {c.min_payment > 0 && (
                        <span className="block text-[11px] text-dim">min. {fmtIDR(c.min_payment)}</span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      {c.used_count}
                      {c.max_usage !== null && <span className="text-dim"> / {c.max_usage}</span>}
                    </td>
                    <td className="px-4 py-3 text-xs text-muted">{planName(c.plan_restriction)}</td>
                    <td className="px-4 py-3 text-xs">{fmtDate(c.expires_at)}</td>
                    <td className="px-4 py-3">
                      <span
                        className={`rounded-full px-2.5 py-1 text-[11px] font-semibold ${
                          effective ? 'bg-neon-mint/10 text-neon-mint' : 'bg-white/5 text-dim'
                        }`}
                      >
                        {isExpired ? 'Kedaluwarsa' : exhausted ? 'Habis' : c.is_active ? 'Aktif' : 'Nonaktif'}
                      </span>
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex justify-end gap-2">
                        <button
                          onClick={() => {
                            setForm({ ...c, expires_at: c.expires_at ? c.expires_at.slice(0, 16) : '' });
                            setMode('form');
                          }}
                          className="rounded-lg border border-white/15 px-3 py-1.5 text-xs text-muted hover:text-ink"
                        >
                          Edit
                        </button>
                        <form action={toggleAction}>
                          <input type="hidden" name="id" value={c.id} />
                          <input type="hidden" name="next_active" value={c.is_active ? 'false' : 'true'} />
                          <button className="rounded-lg border border-white/15 px-3 py-1.5 text-xs text-muted hover:text-ink">
                            {c.is_active ? 'Nonaktifkan' : 'Aktifkan'}
                          </button>
                        </form>
                        <form action={deleteAction}>
                          <input type="hidden" name="id" value={c.id} />
                          <button className="rounded-lg border border-rose-400/30 px-3 py-1.5 text-xs text-rose-300 hover:bg-rose-400/10">
                            Hapus
                          </button>
                        </form>
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
          <div className="px-4 py-3">
            <Notice state={toggleState} />
            <Notice state={deleteState} />
          </div>
        </div>
      )}

      {/* grafik penebusan */}
      {mode === 'list' && (
        <>
          <RedemptionsChart daily={daily} />
          <TopCoupons
            top={topCoupons}
            codes={new Map(coupons.map((c) => [c.id, c.code]))}
          />
        </>
      )}

      {/* penebusan terbaru */}
      {redemptions.length > 0 && (
        <div className="mt-8">
          <h2 className="mb-3 font-display text-sm font-semibold uppercase tracking-wider text-dim">
            Penebusan Terbaru
          </h2>
          <div className="overflow-hidden rounded-2xl border border-white/10 bg-navy-3/70">
            <table className="w-full text-left text-sm">
              <thead>
                <tr className="border-b border-white/10 text-[11px] uppercase tracking-wider text-dim">
                  <th className="px-4 py-3">Kupon</th>
                  <th className="px-4 py-3">User</th>
                  <th className="px-4 py-3">Diskon</th>
                  <th className="px-4 py-3">Tanggal</th>
                </tr>
              </thead>
              <tbody>
                {redemptions.slice(0, 10).map((r) => (
                  <tr key={r.id} className="border-b border-white/5 last:border-0">
                    <td className="px-4 py-2.5 font-mono text-xs">
                      {coupons.find((c) => c.id === r.coupon_id)?.code ?? r.coupon_id.slice(0, 8)}
                    </td>
                    <td className="px-4 py-2.5 font-mono text-xs text-muted">{r.user_id.slice(0, 8)}…</td>
                    <td className="px-4 py-2.5">{fmtIDR(r.discount_amount)}</td>
                    <td className="px-4 py-2.5 text-xs text-muted">{fmtDate(r.redeemed_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
