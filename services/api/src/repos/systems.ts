import { and, asc, eq } from "drizzle-orm";
import type { Config } from "../config";
import type { Db } from "../db/client";
import { sapSystems, tenants } from "../db/schema";
import { AppError } from "../errors";
import { SapClient } from "../sap/client";
import { type ConnectorHub, ConnectorSapTransport, DirectSapTransport, type SapTransport } from "../sap/transport";

export const DEFAULT_TENANT = "default";
export const DEFAULT_SYSTEM = "default";

export type SapSystem = typeof sapSystems.$inferSelect;

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
