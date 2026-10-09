import type Anthropic from "@anthropic-ai/sdk";
import type { AiProvider, DiagnosticMeta, DiagnosticResult } from "@raiox/contracts";

export interface ToolOutcome {
  result?: DiagnosticResult;
  error?: { code: string; message: string };
}

export interface AgentTurn {
  /** Turnos anteriores, exatamente como foram gravados. */
  history: Anthropic.Beta.BetaMessageParam[];
  message: string;
  /** Diagnósticos que este usuário pode executar. */
  diagnostics: DiagnosticMeta[];
  runTool(diagnosticId: string, params: Record<string, string>): Promise<ToolOutcome>;
  emitText(delta: string): void;
  signal: AbortSignal;
}

export interface LlmProvider {
  readonly name: AiProvider;
  readonly model?: string;
  /** Responde ao turno e devolve as mensagens novas (usuário + assistente + ferramentas) para gravar. */
  respond(turn: AgentTurn): Promise<Anthropic.Beta.BetaMessageParam[]>;
}
