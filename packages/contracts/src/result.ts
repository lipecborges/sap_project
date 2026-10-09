import { z } from "zod";

/**
 * Resultado padrão de um diagnóstico ou consulta.
 * Espelha os tipos de ZIF_RX_TYPES no add-on ABAP: qualquer mudança aqui
 * precisa ser refletida lá (e vice-versa).
 */

export const Severity = z.enum(["BLOCKING", "WARNING", "INFO"]);
export type Severity = z.infer<typeof Severity>;

export const ResultStatus = z.enum(["OK", "PROBLEM_FOUND", "NOT_FOUND", "ERROR"]);
export type ResultStatus = z.infer<typeof ResultStatus>;

/** NW = só a plataforma ABAP, sem ERP (ex.: ABAP Platform Trial). */
export const SapRelease = z.enum(["ECC", "S4", "NW"]);
export type SapRelease = z.infer<typeof SapRelease>;

export const Evidence = z.object({
  source: z.string(),
  field: z.string(),
  value: z.string(),
  label: z.string(),
});
export type Evidence = z.infer<typeof Evidence>;

export const SuggestedAction = z.object({
  tcode: z.string().min(1),
  description: z.string(),
});
export type SuggestedAction = z.infer<typeof SuggestedAction>;

export const Finding = z.object({
  /** <ID sem hífen>.<CÓDIGO>, ex.: SD01.CREDIT_BLOCK */
  code: z.string().regex(/^[A-Z]{2}\d{2}\.[A-Z0-9_]+$/),
  severity: Severity,
  title: z.string().min(1),
  detail: z.string(),
  evidence: z.array(Evidence),
  /** O ABAP omite o bloco quando não há ação sugerida. */
  suggestedAction: SuggestedAction.optional(),
});
export type Finding = z.infer<typeof Finding>;

export const ObjectRef = z.object({
  kind: z.string().min(1),
  id: z.string().min(1),
});
export type ObjectRef = z.infer<typeof ObjectRef>;

export const SystemInfo = z.object({
  sid: z.string(),
  client: z.string(),
  release: SapRelease,
  basisRelease: z.string(),
});
export type SystemInfo = z.infer<typeof SystemInfo>;

export const Fact = z.object({
  id: z.string().min(1),
  label: z.string(),
  value: z.string(),
});
export type Fact = z.infer<typeof Fact>;

export const ResultTable = z
  .object({
    id: z.string().min(1),
    title: z.string(),
    /** Identificadores estáveis das colunas (para a interface e a IA); `columns` são os rótulos. */
    keys: z.array(z.string().min(1)),
    columns: z.array(z.string()),
    rows: z.array(z.array(z.string())),
    truncated: z.boolean(),
  })
  .refine((t) => t.keys.length === t.columns.length, {
    message: "keys e columns precisam ter o mesmo tamanho",
  })
  .refine((t) => t.rows.every((row) => row.length === t.columns.length), {
    message: "Toda linha precisa ter o mesmo número de colunas do cabeçalho",
  });
export type ResultTable = z.infer<typeof ResultTable>;

export const DiagnosticResult = z.object({
  diagnosticId: z.string(),
  version: z.string(),
  object: ObjectRef,
  system: SystemInfo,
  status: ResultStatus,
  findings: z.array(Finding),
  related: z.array(ObjectRef),
  facts: z.array(Fact),
  tables: z.array(ResultTable),
  executedAt: z.iso.datetime(),
  durationMs: z.number().int().nonnegative(),
});
export type DiagnosticResult = z.infer<typeof DiagnosticResult>;
