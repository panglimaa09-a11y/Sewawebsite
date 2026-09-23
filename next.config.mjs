/** @type {import('next').NextConfig} */
const nextConfig = {
  images: {
    remotePatterns: [
      { protocol: 'https', hostname: '*.supabase.co' },
      { protocol: 'https', hostname: '*.sewawebmurah.com' },
    ],
  },
  async rewrites() {
    return {
      // Halaman marketing premium (statik) disajikan sebelum route Next.
      // Route stub Next tetap ada untuk integrasi CMS di fase berikutnya.
      beforeFiles: [
        { source: '/', destination: '/landing.html' },
        { source: '/harga', destination: '/harga.html' },
        { source: '/template', destination: '/template.html' },
        { source: '/fitur', destination: '/fitur.html' },
        { source: '/faq', destination: '/faq.html' },
      ],
    };
  },
};

export default nextConfig;
