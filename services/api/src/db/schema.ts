import {
  bigserial,
  boolean,
  index,
  integer,
  jsonb,
  pgTable,
  primaryKey,
  text,
  timestamp,
  uniqueIndex,
} from "drizzle-orm/pg-core";

/**
 * Modelo de dados do Raio-X (D31). Mesmo esquema no Cloud (vários clientes) e no Self-hosted
 * (um cliente, tenant "default"). Toda tabela de negócio carrega tenant_id.
 * Alterou aqui? Gere a migração: `pnpm --filter @raiox/api db:generate`.
 */

const createdAt = () => timestamp("created_at", { withTimezone: true }).notNull().defaultNow();

/** Cliente (empresa). No Self-hosted existe só o "default". */
export const tenants = pgTable("tenants", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  createdAt: createdAt(),
});

/** Sistemas SAP do cliente (ex.: PRD, QAS). Cada um tem o seu caminho de rede. */
export const sapSystems = pgTable(
  "sap_systems",
  {
    id: text("id").notNull(),
    tenantId: text("tenant_id")
      .notNull()
      .references(() => tenants.id),
    name: text("name").notNull(),
    /** direct: HTTP do servidor da API até o SAP. connector: pelo conector on-premise (D35). */
    transport: text("transport", { enum: ["direct", "connector"] }).notNull(),
    baseUrl: text("base_url"),
    sapClient: text("sap_client"),
    connectorId: text("connector_id"),
    isDefault: boolean("is_default").notNull().default(false),
    createdAt: createdAt(),
  },
  (t) => [primaryKey({ columns: [t.tenantId, t.id] })],
);

/** Usuários conhecidos (usuário SAP). Base do licenciamento por usuário nomeado (D34). */
export const users = pgTable(
  "users",
  {
    tenantId: text("tenant_id")
      .notNull()
      .references(() => tenants.id),
    sapUser: text("sap_user").notNull(),
    displayName: text("display_name"),
    role: text("role", { enum: ["user", "admin"] })
      .notNull()
      .default("user"),
    /** Quando o usuário ocupou uma licença; null = sem licença (não consegue entrar). */
    seatAssignedAt: timestamp("seat_assigned_at", { withTimezone: true }),
    blocked: boolean("blocked").notNull().default(false),
    firstLoginAt: createdAt(),
    lastLoginAt: timestamp("last_login_at", { withTimezone: true }),
  },
  (t) => [primaryKey({ columns: [t.tenantId, t.sapUser] })],
);

/**
 * Sessões do navegador (D32). O cookie leva um id aleatório; aqui fica só o hash dele.
 * A senha SAP fica cifrada (AES-256-GCM) com a chave SESSION_SECRET, que não está no banco.
 */
export const sessions = pgTable(
  "sessions",
  {
    idHash: text("id_hash").primaryKey(),
    tenantId: text("tenant_id").notNull(),
    sapSystemId: text("sap_system_id").notNull(),
    sapUser: text("sap_user").notNull(),
    credential: text("credential").notNull(),
    me: jsonb("me").notNull(),
    ip: text("ip"),
    userAgent: text("user_agent"),
    createdAt: createdAt(),
    lastSeenAt: timestamp("last_seen_at", { withTimezone: true }).notNull().defaultNow(),
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
  },
  (t) => [index("sessions_user_idx").on(t.tenantId, t.sapUser), index("sessions_expires_idx").on(t.expiresAt)],
);

/** Conversas com o assistente. As mensagens ficam em linhas separadas, só acrescentadas. */
export const conversations = pgTable(
  "conversations",
  {
    id: text("id").primaryKey(),
    tenantId: text("tenant_id").notNull(),
    sapUser: text("sap_user").notNull(),
    title: text("title").notNull().default(""),
    createdAt: createdAt(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index("conversations_user_idx").on(t.tenantId, t.sapUser, t.updatedAt)],
);

export const conversationMessages = pgTable(
  "conversation_messages",
  {
    conversationId: text("conversation_id")
      .notNull()
      .references(() => conversations.id, { onDelete: "cascade" }),
    seq: integer("seq").notNull(),
    role: text("role", { enum: ["user", "assistant"] }).notNull(),
    /** Conteúdo exatamente como a API do modelo devolveu (inclui blocos de raciocínio). */
    content: jsonb("content").notNull(),
    createdAt: createdAt(),
  },
  (t) => [primaryKey({ columns: [t.conversationId, t.seq] })],
);

/** O que a tela mostrou em cada turno (pergunta + eventos), para reabrir a conversa no histórico. */
export const conversationTurns = pgTable(
  "conversation_turns",
  {
    conversationId: text("conversation_id")
      .notNull()
      .references(() => conversations.id, { onDelete: "cascade" }),
    seq: integer("seq").notNull(),
    question: text("question").notNull(),
    events: jsonb("events").notNull(),
    createdAt: createdAt(),
  },
  (t) => [primaryKey({ columns: [t.conversationId, t.seq] })],
);

/** Trilha de auditoria (D36): quem consultou o quê, quando e com qual resultado. */
export const auditEvents = pgTable(
  "audit_events",
  {
    id: bigserial("id", { mode: "number" }).primaryKey(),
    tenantId: text("tenant_id").notNull(),
    at: timestamp("at", { withTimezone: true }).notNull().defaultNow(),
    sapUser: text("sap_user"),
    sapSystemId: text("sap_system_id"),
    action: text("action").notNull(),
    target: text("target"),
    details: jsonb("details"),
    outcome: text("outcome").notNull(),
    httpStatus: integer("http_status"),
    durationMs: integer("duration_ms"),
    ip: text("ip"),
    requestId: text("request_id"),
  },
  (t) => [index("audit_tenant_at_idx").on(t.tenantId, t.at), index("audit_user_idx").on(t.tenantId, t.sapUser, t.at)],
);

/** Conectores on-premise (D35). O token só existe em claro na criação; aqui fica o hash. */
export const connectors = pgTable(
  "connectors",
  {
    id: text("id").primaryKey(),
    tenantId: text("tenant_id")
      .notNull()
      .references(() => tenants.id),
    name: text("name").notNull(),
    tokenHash: text("token_hash").notNull(),
    createdAt: createdAt(),
    lastSeenAt: timestamp("last_seen_at", { withTimezone: true }),
    version: text("version"),
    revokedAt: timestamp("revoked_at", { withTimezone: true }),
  },
  (t) => [uniqueIndex("connectors_token_idx").on(t.tokenHash)],
);

/** Licença instalada por cliente (D34): o texto assinado, verificado a cada uso. */
export const licenses = pgTable("licenses", {
  tenantId: text("tenant_id")
    .primaryKey()
    .references(() => tenants.id),
  license: text("license").notNull(),
  installedAt: createdAt(),
  installedBy: text("installed_by"),
});
