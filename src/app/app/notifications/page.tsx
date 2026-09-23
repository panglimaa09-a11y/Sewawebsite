export const metadata = { title: 'Notifikasi' };

export default function Page() {
  return (
    <div>
      <h1 className="font-display text-2xl font-bold">Notifikasi</h1>
      <p className="mt-2 text-sm text-muted">
        Kerangka rute <code className="text-neon-cyan">/app/notifications</code> (PRD #10–#18).
        Bangun widget &amp; aksi di sini — akses data sudah dilindungi RLS.
      </p>
    </div>
  );
}
