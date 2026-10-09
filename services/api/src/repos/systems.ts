import { and, asc, eq, isNull, ne } from "drizzle-orm";
import type { Config } from "../config";
import type { Db } from "../db/client";
import { connectors, sapSystems, tenants } from "../db/schema";
import { AppError } from "../errors";
import { SapClient } from "../sap/client";
import { type ConnectorHub, ConnectorSapTransport, DirectSapTransport, type SapTransport } from "../sap/transport";

export const DEFAULT_TENANT = "default";
export const DEFAULT_SYSTEM = "default";

export type SapSystem = typeof sapSystems.$inferSelect;

/** Campos editáveis de um sistema pela administração. */
export interface SystemFields {
  name: string;
  transport: "direct" | "connector";
  baseUrl: string | null;
  sapClient: string | null;
  connectorId: string | null;
  isDefault: boolean;
}

/**
 * Sistemas SAP por cliente e o cliente HTTP de cada um.
 * No Self-hosted, o sistema "default" vem das variáveis SAP_* a cada inicialização.
 */
export class SystemRegistry {
  private readonly clients = new Map<string, { key: string; client: SapClient }>();

  constructor(
    private readonly db: Db,
    private readonly config: Config,
    private readonly hub: ConnectorHub,
    /** Testes: substitui o transporte de todos os sistemas. */
    private readonly override?: SapTransport,
  ) {}

  /** Garante o cliente "default" e, se houver SAP_* configurado, o sistema "default". */
  async bootstrap(): Promise<void> {
    await this.db
      .insert(tenants)
      .values({ id: DEFAULT_TENANT, name: "Padrão" })
      .onConflictDoNothing({ target: tenants.id });
    const transport = this.config.SAP_TRANSPORT;
    if (transport === "direct" && !this.config.SAP_BASE_URL) return;
    const values = {
      name: this.config.SAP_SYSTEM_NAME,
      transport,
      baseUrl: transport === "direct" ? (this.config.SAP_BASE_URL ?? null) : null,
      sapClient: this.config.SAP_CLIENT ?? null,
      connectorId: transport === "connector" ? (this.config.SAP_CONNECTOR_ID ?? null) : null,
      isDefault: true,
    };
    await this.db
      .insert(sapSystems)
      .values({ id: DEFAULT_SYSTEM, tenantId: DEFAULT_TENANT, ...values })
      .onConflictDoUpdate({ target: [sapSystems.tenantId, sapSystems.id], set: values });
  }

  async list(tenantId: string): Promise<SapSystem[]> {
    return this.db.select().from(sapSystems).where(eq(sapSystems.tenantId, tenantId)).orderBy(asc(sapSystems.id));
  }

  /** O sistema "default" do cliente padrão vem das variáveis SAP_* e não é editado pela tela. */
  isManagedByEnv(system: Pick<SapSystem, "id" | "tenantId">): boolean {
    return system.tenantId === DEFAULT_TENANT && system.id === DEFAULT_SYSTEM;
  }

  /** Cadastra um sistema. O primeiro do cliente vira o padrão; marcar como padrão desmarca os outros. */
  async create(tenantId: string, id: string, input: Partial<SystemFields>): Promise<SapSystem> {
    if (id === DEFAULT_SYSTEM) {
      throw new AppError(409, "INVALID_PARAMS", `O id "${DEFAULT_SYSTEM}" é reservado ao sistema das variáveis SAP_*`);
    }
    const fields = await this.normalize(tenantId, {
      name: input.name ?? "",
      transport: input.transport ?? "direct",
      baseUrl: input.baseUrl ?? null,
      sapClient: input.sapClient ?? null,
      connectorId: input.connectorId ?? null,
      isDefault: input.isDefault ?? false,
    });
    return this.db.transaction(async (tx) => {
      const existing = await tx.select({ id: sapSystems.id }).from(sapSystems).where(eq(sapSystems.tenantId, tenantId));
      if (existing.some((s) => s.id === id)) {
        throw new AppError(409, "INVALID_PARAMS", `Já existe um sistema com o id ${id}`);
      }
      const isDefault = fields.isDefault || existing.length === 0;
      if (isDefault) await tx.update(sapSystems).set({ isDefault: false }).where(eq(sapSystems.tenantId, tenantId));
      const [row] = await tx
        .insert(sapSystems)
        .values({ id, tenantId, ...fields, isDefault })
        .returning();
      if (!row) throw new Error("falha ao gravar sistema");
      return row;
    });
  }

  async update(tenantId: string, id: string, patch: Partial<SystemFields>): Promise<SapSystem> {
    const current = await this.requireEditable(tenantId, id);
    const transport = patch.transport ?? current.transport;
    const switched = transport !== current.transport;
    const fields = await this.normalize(tenantId, {
      name: patch.name ?? current.name,
      transport,
      // Ao trocar de transporte, o destino do transporte antigo não vale mais.
      baseUrl: patch.baseUrl !== undefined ? patch.baseUrl : switched ? null : current.baseUrl,
      sapClient: patch.sapClient !== undefined ? patch.sapClient : current.sapClient,
      connectorId: patch.connectorId !== undefined ? patch.connectorId : switched ? null : current.connectorId,
      isDefault: patch.isDefault ?? current.isDefault,
    });
    if (current.isDefault && !fields.isDefault) {
      throw new AppError(400, "INVALID_PARAMS", "Defina outro sistema como padrão em vez de desmarcar este");
    }
    return this.db.transaction(async (tx) => {
      if (fields.isDefault && !current.isDefault) {
        await tx
          .update(sapSystems)
          .set({ isDefault: false })
          .where(and(eq(sapSystems.tenantId, tenantId), ne(sapSystems.id, id)));
      }
      const [row] = await tx
        .update(sapSystems)
        .set(fields)
        .where(and(eq(sapSystems.tenantId, tenantId), eq(sapSystems.id, id)))
        .returning();
      if (!row) throw new AppError(404, "ROUTE_NOT_FOUND", `Sistema ${id} não encontrado`);
      return row;
    });
  }

  /** Remove o sistema. Se era o padrão, o primeiro dos restantes assume. Devolve o novo padrão, se houve. */
  async remove(tenantId: string, id: string): Promise<{ removed: SapSystem; promoted?: string }> {
    const removed = await this.requireEditable(tenantId, id);
    const promoted = await this.db.transaction(async (tx) => {
      await tx.delete(sapSystems).where(and(eq(sapSystems.tenantId, tenantId), eq(sapSystems.id, id)));
      if (!removed.isDefault) return undefined;
      const [next] = await tx
        .select({ id: sapSystems.id })
        .from(sapSystems)
        .where(eq(sapSystems.tenantId, tenantId))
        .orderBy(asc(sapSystems.id))
        .limit(1);
      if (next) {
        await tx
          .update(sapSystems)
          .set({ isDefault: true })
          .where(and(eq(sapSystems.tenantId, tenantId), eq(sapSystems.id, next.id)));
      }
      return next?.id;
    });
    this.clients.delete(`${tenantId}/${id}`);
    return { removed, promoted };
  }

  private async requireEditable(tenantId: string, id: string): Promise<SapSystem> {
    const system = await this.get(tenantId, id);
    if (!system) throw new AppError(404, "ROUTE_NOT_FOUND", `Sistema ${id} não encontrado`);
    if (this.isManagedByEnv(system)) {
      throw new AppError(409, "INVALID_PARAMS", "Este sistema é definido pelas variáveis SAP_* do servidor");
    }
    return system;
  }

  /** direct exige endereço; connector exige um conector cadastrado (e não revogado) do cliente. */
  private async normalize(tenantId: string, f: SystemFields): Promise<SystemFields> {
    const name = f.name.trim();
    if (!name) throw new AppError(400, "INVALID_PARAMS", "Informe o nome do sistema");
    if (f.transport === "direct") {
      if (!f.baseUrl) throw new AppError(400, "INVALID_PARAMS", "Sistema direto exige o endereço (baseUrl)");
      return { ...f, name, connectorId: null };
    }
    if (!f.connectorId) {
      throw new AppError(400, "INVALID_PARAMS", "Sistema via conector exige o conector (connectorId)");
    }
    const [connector] = await this.db
      .select({ id: connectors.id })
      .from(connectors)
      .where(and(eq(connectors.tenantId, tenantId), eq(connectors.id, f.connectorId), isNull(connectors.revokedAt)))
      .limit(1);
    if (!connector) throw new AppError(400, "INVALID_PARAMS", `Conector ${f.connectorId} não cadastrado`);
    return { ...f, name, baseUrl: null };
  }

  /** O sistema pedido, ou o padrão do cliente quando o id não é informado. */
  async resolve(tenantId: string, systemId?: string): Promise<SapSystem> {
    const rows = await this.list(tenantId);
    const system = systemId
      ? rows.find((s) => s.id === systemId)
      : (rows.find((s) => s.isDefault) ?? (rows.length === 1 ? rows[0] : undefined));
    if (!system) {
      throw systemId
        ? new AppError(400, "INVALID_PARAMS", `Sistema SAP ${systemId} não cadastrado`)
        : new AppError(503, "SAP_UNAVAILABLE", "Nenhum sistema SAP configurado");
    }
    return system;
  }

  async get(tenantId: string, systemId: string): Promise<SapSystem | undefined> {
    const [row] = await this.db
      .select()
      .from(sapSystems)
      .where(and(eq(sapSystems.tenantId, tenantId), eq(sapSystems.id, systemId)))
      .limit(1);
    return row;
  }

  /** Cliente SAP do sistema; recriado se a configuração do sistema mudou. */
  client(system: SapSystem): SapClient {
    const cacheId = `${system.tenantId}/${system.id}`;
    const key = JSON.stringify([system.transport, system.baseUrl, system.sapClient, system.connectorId]);
    const cached = this.clients.get(cacheId);
    if (cached && cached.key === key) return cached.client;
    const client = new SapClient(this.transportFor(system));
    this.clients.set(cacheId, { key, client });
    return client;
  }

  transportKind(system: SapSystem): "direct" | "connector" {
    return this.override?.kind ?? system.transport;
  }

  private transportFor(system: SapSystem): SapTransport {
    if (this.override) return this.override;
    const endpoint = { apiPath: this.config.SAP_API_PATH, client: system.sapClient ?? undefined };
    if (system.transport === "connector") {
      if (!system.connectorId)
        throw new AppError(503, "SAP_UNAVAILABLE", `Sistema ${system.id} sem conector associado`);
      return new ConnectorSapTransport(this.hub, system.connectorId, endpoint, this.config.SAP_TIMEOUT_MS);
    }
    if (!system.baseUrl) throw new AppError(503, "SAP_UNAVAILABLE", `Sistema ${system.id} sem endereço`);
    return new DirectSapTransport(system.baseUrl, endpoint, this.config.SAP_TIMEOUT_MS);
  }
}
