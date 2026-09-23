export const metadata = { title: 'Customers' };

export default function Page() {
  return (
    <div>
      <h1 className="font-display text-2xl font-bold">Customers</h1>
      <p className="mt-2 text-sm text-muted">
        Kerangka rute <code className="text-neon-cyan">/admin/customers</code> (PRD #23–#40).
        Layout /admin sudah menegakkan role staff server-side.
      </p>
    </div>
  );
}
