import { randomBytes } from "node:crypto";
import type { MeResponse } from "@raiox/contracts";
import type { SapCredentials } from "./sap/transport";

interface Session {
  credentials: SapCredentials;
  me: MeResponse;
  createdAt: number;
  lastSeen: number;
}

/**
 * Sessões do navegador, só em memória do servidor: a credencial SAP nunca vai para disco
 * nem volta ao navegador (que recebe apenas um cookie httpOnly com um id aleatório).
 * Fase 2: armazenamento compartilhado entre instâncias e principal propagation (sem senha).
 */
export class SessionStore {
  private readonly sessions = new Map<string, Session>();

  constructor(
    private readonly idleMs = 30 * 60 * 1000,
    private readonly maxAgeMs = 10 * 60 * 60 * 1000,
  ) {}

  create(credentials: SapCredentials, me: MeResponse): string {
    this.evict();
    const id = randomBytes(32).toString("base64url");
    const now = Date.now();
    this.sessions.set(id, { credentials, me, createdAt: now, lastSeen: now });
    return id;
  }

  get(id: string | undefined): Session | undefined {
    if (!id) return undefined;
    const session = this.sessions.get(id);
    if (!session) return undefined;
    const now = Date.now();
    if (now - session.lastSeen > this.idleMs || now - session.createdAt > this.maxAgeMs) {
      this.sessions.delete(id);
      return undefined;
    }
    session.lastSeen = now;
    return session;
  }

  delete(id: string | undefined): void {
    if (id) this.sessions.delete(id);
  }

  private evict(): void {
    const now = Date.now();
    for (const [id, s] of this.sessions) {
      if (now - s.lastSeen > this.idleMs || now - s.createdAt > this.maxAgeMs) this.sessions.delete(id);
    }
  }
}
