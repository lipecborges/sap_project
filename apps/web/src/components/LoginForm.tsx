import { type FormEvent, useState } from "react";
import type { Credentials } from "../api";

interface Props {
  onLogin: (creds: Credentials) => Promise<void>;
  error?: string;
}

export function LoginForm({ onLogin, error }: Props) {
  const [user, setUser] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    try {
      await onLogin({ user: user.trim(), password });
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="flex min-h-dvh items-center justify-center px-4">
      <form
        onSubmit={submit}
        className="w-full max-w-sm space-y-5 rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900"
      >
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Raio-X</h1>
          <p className="mt-1 text-sm text-slate-500 dark:text-slate-400">Entre com o seu usuário SAP.</p>
        </div>
        <label className="block text-sm font-medium">
          Usuário SAP
          <input
            className="mt-1 w-full rounded-lg border border-slate-300 bg-white px-3 py-2 uppercase outline-none focus:border-brand-600 focus:ring-2 focus:ring-brand-100 dark:border-slate-700 dark:bg-slate-950 dark:focus:ring-brand-800"
            autoComplete="username"
            autoCapitalize="characters"
            value={user}
            onChange={(e) => setUser(e.target.value)}
            required
          />
        </label>
        <label className="block text-sm font-medium">
          Senha
          <input
            className="mt-1 w-full rounded-lg border border-slate-300 bg-white px-3 py-2 outline-none focus:border-brand-600 focus:ring-2 focus:ring-brand-100 dark:border-slate-700 dark:bg-slate-950 dark:focus:ring-brand-800"
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
        </label>
        {error && (
          <p
            role="alert"
            className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-800 dark:bg-red-950/50 dark:text-red-200"
          >
            {error}
          </p>
        )}
        <button
          type="submit"
          disabled={busy}
          className="w-full rounded-lg bg-brand-700 px-4 py-2 font-medium text-white hover:bg-brand-800 disabled:opacity-60"
        >
          {busy ? "Validando no SAP…" : "Entrar"}
        </button>
        <p className="text-xs text-slate-500 dark:text-slate-400">
          A senha é validada pelo próprio SAP e não é armazenada.
        </p>
      </form>
    </main>
  );
}
