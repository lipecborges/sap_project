import type { AppInfo, DiagnosticMeta, HealthResponse, SessionInfo } from "@raiox/contracts";
import { createContext, type ReactNode, useCallback, useContext, useEffect, useMemo, useState } from "react";
import { api, type Credentials, UNAUTHORIZED_EVENT } from "./api";

export interface Session {
  me: SessionInfo;
  sap: HealthResponse;
  app: AppInfo;
  /** Diagnósticos que o usuário pode executar. */
  diagnostics: DiagnosticMeta[];
}

interface AuthValue {
  /** "loading" enquanto verifica se já existe sessão (ex.: após recarregar a página). */
  status: "loading" | "anonymous" | "authenticated";
  session?: Session;
  login(credentials: Credentials): Promise<void>;
  logout(): void;
  can(diagnosticId: string): boolean;
  /** Papel de administrador do Raio-X (libera a área de Administração). */
  isAdmin: boolean;
}

const AuthContext = createContext<AuthValue | undefined>(undefined);

async function loadSession(me: SessionInfo): Promise<Session> {
  const [sap, app, catalog] = await Promise.all([api.sapHealth(), api.info(), api.diagnostics()]);
  return { me, sap, app, diagnostics: catalog.filter((d) => me.diagnostics.includes(d.id)) };
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [status, setStatus] = useState<AuthValue["status"]>("loading");
  const [session, setSession] = useState<Session>();

  // Recupera a sessão do cookie ao abrir/recarregar o app.
  useEffect(() => {
    api
      .session()
      .then(loadSession)
      .then((s) => {
        setSession(s);
        setStatus("authenticated");
      })
      .catch(() => setStatus("anonymous"));
  }, []);

  useEffect(() => {
    const expire = () => {
      setSession(undefined);
      setStatus("anonymous");
    };
    window.addEventListener(UNAUTHORIZED_EVENT, expire);
    return () => window.removeEventListener(UNAUTHORIZED_EVENT, expire);
  }, []);

  const login = useCallback(async (credentials: Credentials) => {
    const me = await api.login(credentials);
    setSession(await loadSession(me));
    setStatus("authenticated");
  }, []);

  const logout = useCallback(() => {
    void api.logout();
    setSession(undefined);
    setStatus("anonymous");
  }, []);

  const value = useMemo<AuthValue>(
    () => ({
      status,
      session,
      login,
      logout,
      can: (id) => session?.me.diagnostics.includes(id) ?? false,
      isAdmin: session?.me.role === "admin",
    }),
    [status, session, login, logout],
  );
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthValue {
  const value = useContext(AuthContext);
  if (!value) throw new Error("useAuth fora do AuthProvider");
  return value;
}

/** Sessão garantida (rotas internas só renderizam com usuário logado). */
export function useSession(): Session {
  const { session } = useAuth();
  if (!session) throw new Error("Sessão ausente");
  return session;
}
