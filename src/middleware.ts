import { createMiddlewareClient } from '@supabase/auth-helpers-nextjs';
import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

export async function middleware(req: NextRequest) {
  const res = NextResponse.next();
  const supabase = createMiddlewareClient({ req, res });

  const {
    data: { session },
  } = await supabase.auth.getSession();

  // Jika user mencoba mengakses auth pages saat sudah login dan terverifikasi
  if (session) {
    const { data: userData } = await supabase
      .from('users')
      .select('is_verified')
      .eq('id', session.user.id)
      .single();

    const isVerified = userData?.is_verified;

    // Jika user belum verifikasi, redirect ke halaman verifikasi
    if (!isVerified && !req.nextUrl.pathname.startsWith('/auth/verify')) {
      if (!req.nextUrl.pathname.startsWith('/')) {
          return NextResponse.redirect(new URL('/auth/verify-email', req.url));
      }
    }

    // Jika sudah verifikasi dan mencoba akses halaman auth
    if (isVerified && req.nextUrl.pathname.startsWith('/auth')) {
      return NextResponse.redirect(new URL('/dashboard', req.url));
    }
  }

  // Jika user mencoba mengakses dashboard saat belum login
  if (!session && req.nextUrl.pathname.startsWith('/dashboard')) {
    return NextResponse.redirect(new URL('/auth/login', req.url));
  }

  return res;
}

// Specify the paths that should be handled by the middleware
export const config = {
  matcher: ['/', '/dashboard/:path*', '/auth/:path*']
}; 
