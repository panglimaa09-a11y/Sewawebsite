import { NextRequest, NextResponse } from 'next/server';
import { createAdminClient } from '@/lib/supabase/admin';

/**
 * Cron trigger — automation engine (PRD #38, #45).
 * Dipanggil scheduler (Vercel Cron / GitHub Actions / Supabase pg_cron alt):
 *   GET /api/cron/automation dengan header `Authorization: Bearer CRON_SECRET`.
 *
 * Logika bisnis hidup di SQL: public.run_subscription_automation()
 * (supabase/migrations/00003_automation.sql) — idempoten, jadi pemanggilan
 * ganda tidak membuat notifikasi duplikat.
 */
export async function GET(req: NextRequest) {
  const secret = process.env.CRON_SECRET;
  if (!secret) {
    return NextResponse.json({ error: 'CRON_SECRET belum diset' }, { status: 500 });
  }
  const auth = req.headers.get('authorization') ?? '';
  if (auth !== `Bearer ${secret}`) {
    return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  }

  const admin = createAdminClient();
  const { data, error } = await admin.rpc('run_subscription_automation');

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ ok: true, result: data });
}
