'use client';

import { useActionState, useState } from 'react';
import { saveSettings, saveTemplate, sendTestEmail, type ActionState } from './actions';

type Settings = {
  platform_name: string;
  currency: string;
  timezone: string;
  support_email: string | null;
  support_whatsapp: string | null;
  email_provider_name: string;
  email_from: string | null;
  email_reply_to: string | null;
  reminder_days: number[];
  grace_period_days: number;
  expire_after_days: number;
  registration_enabled: boolean;
  maintenance_mode: boolean;
};

type Template = {
  id: string;
  kind: string;
  channel: string;
  subject: string;
  body: string;
  variables: string[];
  is_active: boolean;
  updated_at: string;
};

const inputCls =
  'w-full rounded-xl border border-white/20 bg-white/5 px-3 py-2.5 text-sm text-ink outline-none focus:border-neon-cyan';
const labelCls = 'mb-1.5 block text-xs font-semibold text-muted';

function Notice({ state }: { state: ActionState | null }) {
  if (!state) return null;
  return (
    <p className={`mt-2 text-xs ${state.ok ? 'text-neon-mint' : 'text-rose-400'}`}>{state.message}</p>
  );
}

const TABS = ['Umum', 'Email', 'Jadwal Reminder', 'Template Notifikasi'] as const;

/** Contoh nilai variabel untuk preview template. */
const SAMPLE: Record<string, string> = {
  nama: 'Sari Rahma',
  website: 'kateringbunda.sewawebmurah.com',
  jumlah: 'Rp99.000',
  invoice: 'INV-202609-001',
  tanggal: '25 Okt 2026',
  jumlah_hari: '3',
  tanggal_jatuh_tempo: '26 Sep 2026',
  grace_hari: '3',
  tiket: 'TCK-1042',
  subjek: 'Domain tidak aktif',
};

export default function SettingsClient({
  settings,
  templates,
}: {
  settings: Settings | null;
  templates: Template[];
}) {
  const [tab, setTab] = useState<(typeof TABS)[number]>('Umum');
  const [tplState, tplAction] = useActionState<ActionState | null, FormData>(saveTemplate, null);
  const [settingsState, settingsAction] = useActionState<ActionState | null, FormData>(saveSettings, null);
  const [testState, testAction] = useActionState<ActionState | null, FormData>(sendTestEmail, null);

  const [tpl, setTpl] = useState<Template>(templates[0] ?? null);
  const preview = (text: string) =>
    text.replace(/\{\{(\w+)\}\}/g, (_, k: string) => SAMPLE[k] ?? `{{${k}}}`);

  return (
    <div>
      {/* tabs */}
      <div className="mb-6 flex flex-wrap gap-2">
        {TABS.map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`rounded-full border px-4 py-2 text-xs font-semibold transition ${
              tab === t
                ? 'border-transparent bg-gradient-to-r from-neon-cyan to-neon-violet text-navy'
                : 'border-white/20 text-muted hover:text-ink'
            }`}
          >
            {t}
          </button>
        ))}
      </div>

      {/* ── UMUM ── */}
      {tab === 'Umum' && (
        <form action={settingsAction} className="rounded-2xl border border-white/10 bg-navy-3/70 p-6">
          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <label className={labelCls} htmlFor="platform_name">Nama platform</label>
              <input id="platform_name" name="platform_name" defaultValue={settings?.platform_name ?? ''} className={inputCls} />
            </div>
            <div>
              <label className={labelCls} htmlFor="currency">Mata uang</label>
              <input id="currency" name="currency" defaultValue={settings?.currency ?? 'IDR'} className={inputCls} />
            </div>
            <div>
              <label className={labelCls} htmlFor="timezone">Zona waktu</label>
              <input id="timezone" name="timezone" defaultValue={settings?.timezone ?? 'Asia/Jakarta'} className={inputCls} />
            </div>
            <div>
              <label className={labelCls} htmlFor="support_email">Email support</label>
              <input id="support_email" name="support_email" type="email" defaultValue={settings?.support_email ?? ''} className={inputCls} />
            </div>
            <div>
              <label className={labelCls} htmlFor="support_whatsapp">WhatsApp support</label>
              <input id="support_whatsapp" name="support_whatsapp" defaultValue={settings?.support_whatsapp ?? ''} className={inputCls} />
            </div>
            <div className="flex items-end gap-6 pb-1">
              <label className="flex items-center gap-2 text-sm text-muted">
                <input type="checkbox" name="registration_enabled" defaultChecked={settings?.registration_enabled ?? true} />
                Registrasi terbuka
              </label>
              <label className="flex items-center gap-2 text-sm text-muted">
                <input type="checkbox" name="maintenance_mode" defaultChecked={settings?.maintenance_mode ?? false} />
                Maintenance mode
              </label>
            </div>
          </div>
          <button type="submit" className="mt-6 rounded-xl bg-gradient-to-r from-neon-cyan to-neon-violet px-6 py-2.5 text-sm font-semibold text-navy">
            Simpan Pengaturan
          </button>
          <Notice state={settingsState} />
        </form>
      )}

      {/* ── EMAIL ── */}
      {tab === 'Email' && (
        <form action={settingsAction} className="rounded-2xl border border-white/10 bg-navy-3/70 p-6">
          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <label className={labelCls} htmlFor="email_provider_name">Provider</label>
              <select id="email_provider_name" name="email_provider_name" defaultValue={settings?.email_provider_name ?? 'none'} className={inputCls}>
                <option value="none">Belum diaktifkan</option>
                <option value="resend">Resend (API key di env)</option>
                <option value="smtp">SMTP (host di env)</option>
              </select>
              <p className="mt-1.5 text-[11px] text-dim">
                Kredensial rahasia tetap di environment variable (RESEND_API_KEY / SMTP_URL) — tidak disimpan di database.
              </p>
            </div>
            <div>
              <label className={labelCls} htmlFor="email_from">Alamat pengirim (from)</label>
              <input id="email_from" name="email_from" type="email" defaultValue={settings?.email_from ?? ''} placeholder="noreply@sewawebmurah.com" className={inputCls} />
            </div>
            <div>
              <label className={labelCls} htmlFor="email_reply_to">Reply-to</label>
              <input id="email_reply_to" name="email_reply_to" type="email" defaultValue={settings?.email_reply_to ?? ''} className={inputCls} />
            </div>
          </div>
          <button type="submit" className="mt-6 rounded-xl bg-gradient-to-r from-neon-cyan to-neon-violet px-6 py-2.5 text-sm font-semibold text-navy">
            Simpan Pengaturan
          </button>
          <Notice state={settingsState} />
        </form>
      )}

      {/* ── JADWAL REMINDER ── */}
      {tab === 'Jadwal Reminder' && (
        <form action={settingsAction} className="rounded-2xl border border-white/10 bg-navy-3/70 p-6">
          <p className="mb-4 text-xs text-dim">
            Angka-angka ini dipakai engine otomatis harian (PRD #38). Perubahan berlaku pada eksekusi berikutnya — tanpa deploy ulang.
          </p>
          <div className="grid gap-4 sm:grid-cols-3">
            <div>
              <label className={labelCls} htmlFor="reminder_days">Hari reminder (D-…)</label>
              <input id="reminder_days" name="reminder_days" defaultValue={(settings?.reminder_days ?? [7, 3, 1]).join(',')} className={inputCls} />
              <p className="mt-1.5 text-[11px] text-dim">Pisah koma, mis. 7,3,1</p>
            </div>
            <div>
              <label className={labelCls} htmlFor="grace_period_days">Masa tenggang (hari)</label>
              <input id="grace_period_days" name="grace_period_days" type="number" min={0} max={30} defaultValue={settings?.grace_period_days ?? 3} className={inputCls} />
              <p className="mt-1.5 text-[11px] text-dim">Sesudah jatuh tempo → suspended</p>
            </div>
            <div>
              <label className={labelCls} htmlFor="expire_after_days">Retensi setelah suspend (hari)</label>
              <input id="expire_after_days" name="expire_after_days" type="number" min={1} max={90} defaultValue={settings?.expire_after_days ?? 14} className={inputCls} />
              <p className="mt-1.5 text-[11px] text-dim">Sesudah itu → expired</p>
            </div>
          </div>
          <button type="submit" className="mt-6 rounded-xl bg-gradient-to-r from-neon-cyan to-neon-violet px-6 py-2.5 text-sm font-semibold text-navy">
            Simpan Jadwal
          </button>
          <Notice state={settingsState} />
        </form>
      )}

      {/* ── TEMPLATE NOTIFIKASI ── */}
      {tab === 'Template Notifikasi' && (
        <div className="grid gap-4 md:grid-cols-[220px_1fr]">
          {/* daftar template */}
          <div className="rounded-2xl border border-white/10 bg-navy-3/70 p-3">
            {templates.map((t) => (
              <button
                key={t.id}
                onClick={() => setTpl(t)}
                className={`mb-1 block w-full rounded-xl px-3 py-2.5 text-left text-xs transition ${
                  tpl?.id === t.id ? 'bg-white/10 text-ink' : 'text-muted hover:bg-white/5'
                }`}
              >
                <span className="block font-mono">{t.kind}</span>
                <span className="mt-0.5 flex items-center gap-2">
                  <span className={`inline-block h-1.5 w-1.5 rounded-full ${t.is_active ? 'bg-neon-mint' : 'bg-white/20'}`} />
                  {t.channel}
                </span>
              </button>
            ))}
          </div>

          {/* editor */}
          {tpl && (
            <form key={tpl.id} action={tplAction} className="rounded-2xl border border-white/10 bg-navy-3/70 p-6">
              <input type="hidden" name="id" value={tpl.id} />
              <div className="grid gap-4 sm:grid-cols-2">
                <div>
                  <label className={labelCls} htmlFor="kind">Jenis (kind)</label>
                  <input id="kind" name="kind" defaultValue={tpl.kind} className={`${inputCls} font-mono`} />
                </div>
                <div>
                  <label className={labelCls} htmlFor="channel">Kanal</label>
                  <select id="channel" name="channel" defaultValue={tpl.channel} className={inputCls}>
                    <option value="dashboard">Dashboard</option>
                    <option value="email">Email</option>
                    <option value="whatsapp">WhatsApp</option>
                  </select>
                </div>
              </div>
              <div className="mt-4">
                <label className={labelCls} htmlFor="subject">Subjek</label>
                <input id="subject" name="subject" defaultValue={tpl.subject} className={inputCls} />
                <p className="mt-1.5 text-[11px] text-dim">Preview: {preview(tpl.subject)}</p>
              </div>
              <div className="mt-4">
                <label className={labelCls} htmlFor="body">Isi pesan — variabel {'{{nama}}'} dsb.</label>
                <textarea
                  id="body"
                  name="body"
                  defaultValue={tpl.body}
                  rows={5}
                  onChange={(e) => setTpl({ ...tpl, body: e.target.value })}
                  className={`${inputCls} leading-relaxed`}
                />
                <div className="mt-2 rounded-xl border border-dashed border-white/15 bg-white/[0.03] p-3 text-xs text-muted">
                  <span className="mb-1 block font-mono text-[10px] uppercase tracking-wider text-dim">Preview</span>
                  <b className="text-ink">{preview(tpl.subject)}</b>
                  <p className="mt-1">{preview(tpl.body)}</p>
                </div>
                {tpl.variables.length > 0 && (
                  <p className="mt-2 text-[11px] text-dim">
                    Variabel: {tpl.variables.map((v) => `{{${v}}}`).join(' · ')}
                  </p>
                )}
              </div>
              <div className="mt-5 flex flex-wrap items-center gap-4">
                <label className="flex items-center gap-2 text-sm text-muted">
                  <input type="checkbox" name="is_active" defaultChecked={tpl.is_active} />
                  Template aktif
                </label>
                <button type="submit" className="rounded-xl bg-gradient-to-r from-neon-cyan to-neon-violet px-6 py-2.5 text-sm font-semibold text-navy">
                  Simpan Template
                </button>
              </div>
              <Notice state={tplState} />

              {/* uji kirim email */}
              <div className="mt-6 border-t border-white/10 pt-5">
                <p className="mb-2 text-xs font-semibold text-muted">Uji kirim email dengan template ini</p>
                <div className="flex gap-2">
                  <input name="to" type="email" placeholder="email-anda@contoh.com" className={inputCls} />
                  <input type="hidden" name="subject" value={tpl.subject} />
                  <input type="hidden" name="body" value={tpl.body} />
                  <button formAction={testAction} className="whitespace-nowrap rounded-xl border border-neon-cyan/40 bg-neon-cyan/10 px-4 py-2.5 text-sm font-semibold text-neon-cyan">
                    Kirim Uji
                  </button>
                </div>
                <Notice state={testState} />
              </div>
            </form>
          )}
        </div>
      )}
    </div>
  );
}