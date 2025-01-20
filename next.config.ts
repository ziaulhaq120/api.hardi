import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  images: {
    domains: ['plrkrorlqralicbsangu.supabase.co'],
    unoptimized: true,
  },
  async headers() {
    return [
      {
        source: '/:path*',
        headers: [
          {
            key: 'Content-Security-Policy',
            value: `
              default-src 'self';
              img-src 'self' blob: data: https://plrkrorlqralicbsangu.supabase.co;
              script-src 'self' 'unsafe-eval' 'unsafe-inline';
              style-src 'self' 'unsafe-inline';
              font-src 'self';
              connect-src 'self' https://plrkrorlqralicbsangu.supabase.co;
              frame-src 'self';
              media-src 'self';
            `.replace(/\s{2,}/g, ' ').trim()
          }
        ]
      }
    ];
  }
};

export default nextConfig;
