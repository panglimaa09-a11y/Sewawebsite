export const metadata = { title: 'Pengaturan' };

export default function Page() {
  return (
    <div>
      <h1 className="font-display text-2xl font-bold">Pengaturan</h1>
      <p className="mt-2 text-sm text-muted">
        Kerangka rute <code className="text-neon-cyan">/app/settings</code> (PRD #10–#18).
        Bangun widget &amp; aksi di sini — akses data sudah dilindungi RLS.
      </p>
    </div>
  );
}
