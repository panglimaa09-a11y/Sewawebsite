export const metadata = { title: 'Billing Center' };

export default function Page() {
  return (
    <div>
      <h1 className="font-display text-2xl font-bold">Billing Center</h1>
      <p className="mt-2 text-sm text-muted">
        Kerangka rute <code className="text-neon-cyan">/admin/billing</code> (PRD #23–#40).
        Layout /admin sudah menegakkan role staff server-side.
      </p>
    </div>
  );
}
