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
    /** Minutos sem uso até a sessão expirar. */
    SESSION_IDLE_MINUTES: z.coerce.number().int().positive().default(30),
    /** Centro usado no painel inicial. */
    DEFAULT_PLANT: z.string().default("1000"),
  })
  .transform((env) => ({
    ...env,
    SAP_TRANSPORT: env.SAP_TRANSPORT ?? (env.DEPLOYMENT_MODE === "cloud" ? "connector" : "direct"),
  }))
  .superRefine((env, ctx) => {
    if (env.SAP_TRANSPORT === "direct" && !env.SAP_BASE_URL) {
      ctx.addIssue({ code: "custom", path: ["SAP_BASE_URL"], message: "Obrigatório quando o transporte é direct" });
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
