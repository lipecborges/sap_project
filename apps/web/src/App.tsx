import type { DiagnosticMeta, HealthResponse, MeResponse } from "@raiox/contracts";
import { useState } from "react";
import { api, type Credentials, RequestError } from "./api";
import { DiagnosticRunner } from "./components/DiagnosticRunner";
import { LoginForm } from "./components/LoginForm";

interface Session {
  credentials: Credentials;
  me: MeResponse;
  health: HealthResponse;
  diagnostics: DiagnosticMeta[];
}

export function App() {
  const [session, setSession] = useState<Session>();
  const [loginError, setLoginError] = useState<string>();

  async function login(credentials: Credentials) {
    setLoginError(undefined);
    try {
      const me = await api.login(credentials);
      const [health, all] = await Promise.all([api.sapHealth(credentials), api.diagnostics(credentials)]);
      const allowed = all.filter((d) => me.diagnostics.includes(d.id));
      setSession({ credentials, me, health, diagnostics: allowed });
    } catch (err) {
      setLoginError(err instanceof RequestError ? err.message : "Falha ao entrar");
    }
  }

  if (!session) return <LoginForm onLogin={login} error={loginError} />;

  const { system } = session.health;
  return (
    <div className="mx-auto max-w-7xl px-4 pb-16">
      <header className="flex flex-wrap items-center gap-x-4 gap-y-2 py-4">
        <h1 className="text-xl font-semibold tracking-tight">Raio-X</h1>
        <span className="rounded-md bg-slate-200 px-2 py-0.5 text-xs dark:bg-slate-800">
          {system.sid}/{system.client} · {system.release} · add-on {session.health.addonVersion}
        </span>
        <span className="ml-auto text-sm text-slate-600 dark:text-slate-400">{session.me.user}</span>
        <button
          type="button"
          onClick={() => setSession(undefined)}
          className="rounded-lg px-3 py-1 text-sm hover:bg-slate-200 dark:hover:bg-slate-800"
        >
          Sair
        </button>
      </header>
      <p className="mb-6 rounded-lg bg-brand-50 px-3 py-2 text-sm text-brand-800 dark:bg-brand-800/30 dark:text-brand-100">
        Modo diagnóstico direto (sem IA). A conversa com IA chega na Fase 2.
      </p>
      {session.diagnostics.length === 0 ? (
        <p>Seu usuário SAP não tem autorização para nenhum diagnóstico (objeto ZRX_DIAG).</p>
      ) : (
        <DiagnosticRunner
          credentials={session.credentials}
          diagnostics={session.diagnostics}
          showExamples={system.sid === "MCK"}
        />
      )}
    </div>
  );
}
