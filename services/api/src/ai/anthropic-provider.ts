import Anthropic from "@anthropic-ai/sdk";
import { AppError } from "../errors";
import { SYSTEM_PROMPT } from "./prompt";
import type { AgentTurn, LlmProvider } from "./provider";
import { resultForModel, toAnthropicTools, toolName } from "./tools";

export interface AnthropicProviderOptions {
  model: string;
  effort: "low" | "medium" | "high" | "xhigh" | "max";
  /** Refazer automaticamente em outro modelo se o principal recusar (só na API da Anthropic). */
  fallbacks: boolean;
  maxToolRounds?: number;
  client?: Anthropic;
}

/** Assistente com Claude: laço manual de ferramentas com streaming de texto. */
export class AnthropicProvider implements LlmProvider {
  readonly name = "anthropic" as const;
  readonly model: string;
  private readonly client: Anthropic;

  constructor(private readonly options: AnthropicProviderOptions) {
    this.model = options.model;
    // Credenciais do ambiente: ANTHROPIC_API_KEY (ou perfil do `ant auth login`).
    this.client = options.client ?? new Anthropic();
  }

  async respond(turn: AgentTurn): Promise<Anthropic.Beta.BetaMessageParam[]> {
    const tools = toAnthropicTools(turn.diagnostics);
    const byName = new Map(turn.diagnostics.map((d) => [toolName(d.id), d]));
    const added: Anthropic.Beta.BetaMessageParam[] = [{ role: "user", content: turn.message }];
    const maxRounds = this.options.maxToolRounds ?? 6;

    for (let round = 0; ; round++) {
      const stream = this.client.beta.messages.stream(
        {
          model: this.model,
          max_tokens: 64000,
          output_config: { effort: this.options.effort },
          system: [{ type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } }],
          tools,
          messages: [...turn.history, ...added],
          ...(this.options.fallbacks
            ? { betas: ["server-side-fallback-2026-07-01"], fallbacks: "default" as const }
            : {}),
        },
        { signal: turn.signal },
      );
      stream.on("text", (delta) => turn.emitText(delta));

      let message: Anthropic.Beta.BetaMessage;
      try {
        message = await stream.finalMessage();
      } catch (err) {
        throw toAppError(err);
      }

      if (message.stop_reason === "refusal") {
        turn.emitText("\n\nNão posso ajudar com esse pedido. Reformule a pergunta sobre o processo SAP.");
        added.push({ role: "assistant", content: message.content });
        return added;
      }
      if (message.stop_reason === "pause_turn") {
        added.push({ role: "assistant", content: message.content });
        continue;
      }

      const toolUses = message.content.filter((b): b is Anthropic.Beta.BetaToolUseBlock => b.type === "tool_use");
      if (toolUses.length > 0 && message.stop_reason === "max_tokens") {
        throw new AppError(502, "INTERNAL", "Resposta da IA truncada; tente de novo.");
      }
      added.push({ role: "assistant", content: message.content });
      if (toolUses.length === 0) return added;

      if (round >= maxRounds) {
        // Limite de consultas por pergunta: responde com o que já tem.
        added.push({
          role: "user",
          content: toolUses.map((t) => ({
            type: "tool_result" as const,
            tool_use_id: t.id,
            is_error: true,
            content: "Limite de consultas desta pergunta atingido. Responda com o que já foi encontrado.",
          })),
        });
        continue;
      }

      // Ferramentas da mesma resposta rodam em paralelo; todos os resultados voltam numa única mensagem.
      const results = await Promise.all(
        toolUses.map(async (t): Promise<Anthropic.Beta.BetaToolResultBlockParam> => {
          const meta = byName.get(t.name);
          const input = (t.input ?? {}) as Record<string, unknown>;
          if (!meta)
            return {
              type: "tool_result",
              tool_use_id: t.id,
              is_error: true,
              content: `Ferramenta ${t.name} indisponível`,
            };
          const params = Object.fromEntries(
            Object.entries(input)
              .filter(([, v]) => typeof v === "string" || typeof v === "number")
              .map(([k, v]) => [k, String(v)]),
          );
          const outcome = await turn.runTool(meta.id, params);
          if (outcome.error) {
            return { type: "tool_result", tool_use_id: t.id, is_error: true, content: JSON.stringify(outcome.error) };
          }
          return { type: "tool_result", tool_use_id: t.id, content: resultForModel(outcome.result!) };
        }),
      );
      added.push({ role: "user", content: results });
    }
  }
}

function toAppError(err: unknown): AppError {
  if (err instanceof Anthropic.AuthenticationError) {
    return new AppError(503, "INTERNAL", "Credencial da IA inválida. Verifique ANTHROPIC_API_KEY.");
  }
  if (err instanceof Anthropic.RateLimitError) {
    return new AppError(503, "INTERNAL", "Limite de uso da IA atingido. Tente em instantes.");
  }
  if (err instanceof Anthropic.APIUserAbortError) {
    return new AppError(499, "INTERNAL", "Pergunta cancelada.");
  }
  if (err instanceof Anthropic.APIError) {
    return new AppError(502, "INTERNAL", `Erro do provedor de IA (${err.status ?? "rede"}).`);
  }
  if (err instanceof AppError) return err;
  return new AppError(502, "INTERNAL", "Falha ao consultar a IA.");
}
