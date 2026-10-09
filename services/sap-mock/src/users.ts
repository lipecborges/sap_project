import { DIAGNOSTICS } from "@raiox/contracts";

export interface MockUser {
  password: string;
  language: string;
  /** Diagnósticos liberados (simula o objeto de autorização ZRX_DIAG). */
  diagnostics: string[];
}

/** Usuários do simulador. Nunca use estas senhas fora do ambiente de desenvolvimento. */
export const USERS: Record<string, MockUser> = {
  DEMO: { password: "demo", language: "PT", diagnostics: DIAGNOSTICS.map((d) => d.id) },
  VENDAS: { password: "vendas", language: "PT", diagnostics: ["SD-01", "SD-10"] },
};
