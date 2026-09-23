import 'server-only';
import { createClient as createSupabaseClient } from '@supabase/supabase-js';

/**
 * SERVICE ROLE client — BYPASS RLS. Hanya untuk:
 *  - webhook pembayaran terverifikasi (PRD #20)
 *  - cron automation engine (PRD #45)
 *  - operasi admin internal
 * JANGAN pernah mengimpor file ini dari Client Component.
 * (PRD #44: jangan expose SUPABASE_SERVICE_ROLE_KEY ke client.)
 */
export function createAdminClient() {
  return createSupabaseClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { autoRefreshToken: false, persistSession: false } }
  );
}
