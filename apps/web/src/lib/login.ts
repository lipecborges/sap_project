import { RequestError } from "./api";

const SYSTEM_KEY = "raiox.system";

/** Mensagem de login para o usuário, conforme o código de erro da API. */
export function loginErrorMessage(err: unknown): string {
  if (!(err instanceof RequestError)) return "Não foi possível entrar";
  switch (err.code) {
    case "LICENSE_REQUIRED":
      return "Não há licença disponível para este usuário. Peça ao administrador do Raio-X para liberar uma licença.";
    case "FORBIDDEN":
      return "Seu acesso ao Raio-X está bloqueado. Fale com o administrador.";
    case "RATE_LIMITED":
      return "Muitas tentativas de login. Aguarde alguns minutos e tente de novo.";
    case "NETWORK":
      return err.message;
    default:
      return err.message || "Não foi possível entrar";
  }
}

export function readSystemChoice(): string | undefined {
  try {
    return localStorage.getItem(SYSTEM_KEY) ?? undefined;
  } catch {
    return undefined;
  }
}

export function saveSystemChoice(id: string): void {
  try {
    localStorage.setItem(SYSTEM_KEY, id);
  } catch {
    // Armazenamento indisponível: a escolha vale só nesta visita.
  }
}

/** Sistema inicial do seletor: o último usado (se ainda existir), senão o padrão, senão o primeiro. */
export function pickSystem(systems: { id: string; isDefault: boolean }[], stored?: string): string | undefined {
  return systems.find((s) => s.id === stored)?.id ?? systems.find((s) => s.isDefault)?.id ?? systems[0]?.id;
}
