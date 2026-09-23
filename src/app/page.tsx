import Link from 'next/link';

/**
 * Landing page. Desain final ada di landing statis (index.html, rute / dipakai
 * oleh Next). Tempel konten landing page premium di sini, atau render dari CMS.
 */
export default function HomePage() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-6 bg-navy p-8 text-center">
      <h1 className="font-display text-4xl font-bold md:text-6xl">
        Punya website profesional.
        <span className="bg-gradient-to-r from-neon-cyan to-neon-violet bg-clip-text text-transparent">
          {' '}
          Tanpa biaya pembuatan mahal.
        </span>
      </h1>
      <p className="max-w-xl text-muted">
        Sewa website untuk bisnis, UMKM, personal brand. Mulai dari Rp49.000/bulan.
      </p>
      <div className="flex gap-4">
        <Link href="/register" className="rounded-xl bg-gradient-to-r from-neon-cyan to-neon-violet px-6 py-3 font-semibold text-navy">
          Mulai Sekarang
        </Link>
        <Link href="/template" className="rounded-xl border border-white/20 px-6 py-3">
          Lihat Template
        </Link>
      </div>
    </main>
  );
}
