import { z } from "zod";

/**
 * Configuração única para os dois modos de implantação (projeto, seção 4.4).
 * Lida das variáveis de ambiente e validada na inicialização.
 */
const Env = z
  .object({
    DEPLOYMENT_MODE: z.enum(["cloud", "selfhosted"]).default("selfhosted"),
    /** Padrão: selfhosted → direct, cloud → connector. */
    SAP_TRANSPORT: z.enum(["direct", "connector"]).optional(),
    SAP_BASE_URL: z.url().optional(),
    SAP_API_PATH: z.string().startsWith("/").default("/sap/bc/zrx/api/v1"),
    SAP_CLIENT: z
      .string()
      .regex(/^\d{3}$/, "Mandante deve ter 3 dígitos")
      .optional(),
    SAP_TIMEOUT_MS: z.coerce.number().int().positive().default(30_000),
    /** Nome exibido do sistema SAP configurado pelas variáveis SAP_* (ex.: "PRD"). */
    SAP_SYSTEM_NAME: z.string().default("SAP"),
    /** Conector on-premise do sistema padrão, quando o transporte é connector. */
    SAP_CONNECTOR_ID: z.string().optional(),
    /**
     * Banco (D31): postgres://… em produção; pglite:memory (testes) ou pglite:<pasta> (desenvolvimento).
     * Obrigatório com NODE_ENV=production.
     */
    DATABASE_URL: z.string().optional(),
    /** Chave (≥ 32 bytes, base64 ou hex) que cifra a senha SAP das sessões no banco (D32). */
    SESSION_SECRET: z.string().optional(),
    NODE_ENV: z.string().optional(),
    /** Cloud: domínio base; o cliente vem do subdomínio (acme.raiox.app → acme). */
    CLOUD_BASE_DOMAIN: z.string().optional(),
    /** Usuários SAP com papel de administrador do Raio-X, separados por vírgula. */
    ADMIN_USERS: z
      .string()
      .default("")
      .transform((v) =>
        v
          .split(",")
          .map((u) => u.trim().toUpperCase())
          .filter(Boolean),
      ),
    /**
     * Licença (D34). LICENSE_FILE: arquivo de licença do Self-hosted; só vale enquanto não houver licença
     * instalada pela administração (o banco tem precedência).
     */
    LICENSE_FILE: z.string().optional(),
    /** Chave pública (PEM ou SPKI em base64) no lugar da do fornecedor; só para testes e desenvolvimento. */
    LICENSE_PUBLIC_KEY: z.string().optional(),
    /** Retenção em dias (D36). */
    AUDIT_RETENTION_DAYS: z.coerce.number().int().positive().default(365),
    CONVERSATION_RETENTION_DAYS: z.coerce.number().int().positive().default(90),
    HOST: z.string().default("0.0.0.0"),
    PORT: z.coerce.number().int().positive().default(3000),
    /** Pasta com o build da web (apps/web/dist). Se definida, a API serve a interface. */
    WEB_DIST_DIR: z.string().optional(),
    LOG_LEVEL: z.enum(["fatal", "error", "warn", "info", "debug", "trace", "silent"]).default("info"),
    /** demo: regras locais, sem modelo e sem internet. anthropic: Claude (requer ANTHROPIC_API_KEY ou perfil `ant`). */
    AI_PROVIDER: z.enum(["demo", "anthropic"]).default("demo"),
    AI_MODEL: z.string().default("claude-opus-5-5"),
    AI_EFFORT: z.enum(["low", "medium", "high", "xhigh", "max"]).default("medium"),
    /** Refazer em outro modelo se o principal recusar (só na API da Anthropic; desligue em Bedrock/Vertex). */
    AI_FALLBACKS: z
      .enum(["true", "false"])
      .default("true")
      .transform((v) => v === "true"),
    /** Cookie de sessão só por HTTPS. Ligue em produção atrás de TLS. */
    COOKIE_SECURE: z
      .enum(["true", "false"])
      .default("false")
      .transform((v) => v === "true"),
    /** Atrás de proxy reverso (nginx, balanceador): usa X-Forwarded-For para o IP real. Desligue se a API ficar exposta direto. */
    TRUST_PROXY: z
      .enum(["true", "false"])
      .default("true")
      .transform((v) => v === "true"),
    /** Limite global de requisições por IP na janela (generoso: o SPA faz várias chamadas por tela). */
    RATE_LIMIT_MAX: z.coerce.number().int().positive().default(600),
    RATE_LIMIT_WINDOW_SECONDS: z.coerce.number().int().positive().default(60),
    /** Limite estrito de tentativas de login por IP + usuário na janela (força bruta). */
    RATE_LIMIT_LOGIN_MAX: z.coerce.number().int().positive().default(10),
    RATE_LIMIT_LOGIN_WINDOW_SECONDS: z.coerce.number().int().positive().default(60),
    /** Token Bearer do GET /metrics (Prometheus). Sem ele, /metrics fica desligado (404). */
    METRICS_TOKEN: z.preprocess(
      (v) => (v === "" ? undefined : v),
      z.string().min(16, "Use ao menos 16 caracteres (openssl rand -hex 24)").optional(),
    ),
    /** Minutos sem uso até a sessão expirar. */
    SESSION_IDLE_MINUTES: z.coerce.number().int().positive().default(30),
    /** Centro usado no painel inicial. */
    DEFAULT_PLANT: z.string().default("1000"),
  })
  .transform((env) => ({
    ...env,
    SAP_TRANSPORT: env.SAP_TRANSPORT ?? (env.DEPLOYMENT_MODE === "cloud" ? "connector" : "direct"),
    DATABASE_URL: env.DATABASE_URL ?? "pglite:memory",
    DATABASE_URL_DEFAULTED: env.DATABASE_URL === undefined,
  }))
  .superRefine((env, ctx) => {
    if (env.DEPLOYMENT_MODE === "selfhosted" && env.SAP_TRANSPORT === "direct" && !env.SAP_BASE_URL) {
      ctx.addIssue({ code: "custom", path: ["SAP_BASE_URL"], message: "Obrigatório quando o transporte é direct" });
    }
    if (env.NODE_ENV === "production" && env.DATABASE_URL_DEFAULTED) {
      ctx.addIssue({ code: "custom", path: ["DATABASE_URL"], message: "Obrigatório em produção (postgres://…)" });
    }
    if (env.NODE_ENV === "production" && env.LICENSE_PUBLIC_KEY) {
      ctx.addIssue({
        code: "custom",
        path: ["LICENSE_PUBLIC_KEY"],
        message: "Não é aceito em produção (a chave do fornecedor é fixa no código)",
      });
    }
    if (env.DATABASE_URL.startsWith("postgres") && !env.SESSION_SECRET) {
      ctx.addIssue({
        code: "custom",
        path: ["SESSION_SECRET"],
        message: "Obrigatório com PostgreSQL (gere com: openssl rand -base64 32)",
      });
    }
  });

export type Config = z.infer<typeof Env>;

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const parsed = Env.safeParse(env);
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `  - ${i.path.join(".")}: ${i.message}`).join("\n");
    throw new Error(`Configuração inválida:\n${issues}`);
  }
  return parsed.data;
}
