export const metadata = { title: 'Templates' };

export default function Page() {
  return (
    <div>
      <h1 className="font-display text-2xl font-bold">Templates</h1>
      <p className="mt-2 text-sm text-muted">
        Kerangka rute <code className="text-neon-cyan">/admin/templates</code> (PRD #23–#40).
        Layout /admin sudah menegakkan role staff server-side.
      </p>
    </div>
  );
}
