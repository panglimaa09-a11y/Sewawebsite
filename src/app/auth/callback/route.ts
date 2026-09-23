import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

/**
 * Callback konfirmasi email (Supabase → {SITE_URL}/auth/callback?code=...).
 * Menukar code menjadi session, lalu mengarahkan ke dashboard.
 * Pastikan di Supabase: Authentication → URL Configuration → Redirect URLs
 * memuat {SITE_URL}/auth/callback — dan template email konfirmasi memakai
 * {{ .ConfirmationURL }}.
 */
export async function GET(request: NextRequest) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get('code');
  const next = searchParams.get('next') ?? '/app/dashboard';

  if (code) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) {
      return NextResponse.redirect(`${origin}${next}`);
    }
  }

  return NextResponse.redirect(`${origin}/login?error=confirmation`);
}
