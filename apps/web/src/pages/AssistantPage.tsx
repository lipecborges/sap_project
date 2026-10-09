import { useNavigate } from "@tanstack/react-router";
import {
  AlertTriangle,
  ArrowUp,
  Factory,
  MessageSquarePlus,
  Receipt,
  ShoppingCart,
  Sparkles,
  Square,
  Trash2,
} from "lucide-react";
import { type FormEvent, type KeyboardEvent, useEffect, useRef, useState } from "react";
import { Markdown } from "../components/chat/Markdown";
import { ToolStep } from "../components/chat/ToolStep";
import { useSession } from "../lib/auth";
import { type ChatItem, chatStore, useChat } from "../lib/chat";
import { cn } from "../lib/utils";

const STARTERS = [
  { icon: Sparkles, title: "Panorama do dia", prompt: "Me dá um panorama de hoje" },
  { icon: ShoppingCart, title: "Pedido não faturou", prompt: "Por que o pedido 4500001 não faturou?" },
  { icon: Factory, title: "Andamento de uma ordem", prompt: "Como está a ordem 1000010?" },
  { icon: Receipt, title: "Fatura bloqueada", prompt: "Por que a fatura 5105600001 está bloqueada?" },
];

function AssistantMessage({
  item,
  onAsk,
  busy,
}: {
  item: Extract<ChatItem, { role: "assistant" }>;
  onAsk: (q: string) => void;
  busy: boolean;
}) {
  const thinking = item.status === "streaming" && item.text === "" && item.tools.every((t) => t.status !== "running");
  return (
    <div className="flex gap-3">
      <div className="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-brand-500 to-brand-700 text-white">
        <Sparkles className="size-4" />
      </div>
      <div className="min-w-0 flex-1 space-y-3">
        {item.tools.length > 0 && (
          <div className="space-y-2">
            {item.tools.map((t) => (
              <ToolStep key={t.callId} call={t} />
            ))}
          </div>
        )}
        {thinking && (
          <div className="flex items-center gap-2 py-1 text-sm text-zinc-500">
            <span className="flex gap-1">
              {[0, 1, 2].map((i) => (
                <span
                  key={i}
                  className="size-1.5 animate-bounce rounded-full bg-brand-400"
                  style={{ animationDelay: `${i * 120}ms` }}
                />
              ))}
            </span>
            Analisando…
          </div>
        )}
        {item.text && (
          <div>
            <Markdown text={item.text} />
            {item.status === "streaming" && (
              <span className="ml-0.5 inline-block h-4 w-1.5 animate-blink bg-brand-500 align-middle" />
            )}
          </div>
        )}
        {item.status === "error" && (
          <div className="flex items-start gap-2 rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700 dark:border-red-900 dark:bg-red-950/40 dark:text-red-300">
            <AlertTriangle className="mt-0.5 size-4 shrink-0" /> {item.error}
          </div>
        )}
        {item.status === "done" && item.suggestions.length > 0 && (
          <div className="flex flex-wrap gap-1.5 pt-1">
            {item.suggestions.map((s) => (
              <button
                key={s}
                type="button"
                disabled={busy}
                onClick={() => onAsk(s)}
                className="rounded-full border border-zinc-200 bg-white px-3 py-1 text-xs text-zinc-600 transition hover:border-brand-300 hover:text-brand-700 disabled:opacity-50 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-400 dark:hover:text-brand-300"
              >
                {s}
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

export function AssistantPage({ q }: { q?: string }) {
  const { app } = useSession();
  const { conversations, activeId } = useChat();
  const navigate = useNavigate();
  const active = conversations.find((c) => c.id === activeId);
  const busy = active ? chatStore.isBusy(active.id) : false;
  const [text, setText] = useState("");
  const bottom = useRef<HTMLDivElement>(null);
  const textarea = useRef<HTMLTextAreaElement>(null);
  const handledQ = useRef<string | undefined>(undefined);

  const ask = (message: string, conversationId = active?.id) => {
    if (!message.trim()) return;
    void chatStore.send(message.trim(), conversationId);
    setText("");
  };

  // Pergunta vinda do painel ou da busca (?q=…): abre uma conversa nova e envia.
  useEffect(() => {
    if (q && handledQ.current !== q) {
      handledQ.current = q;
      const id = chatStore.newConversation();
      void chatStore.send(q, id);
      navigate({ to: "/assistente", search: {}, replace: true });
    }
  }, [q, navigate]);

  const lastText = active?.items.at(-1);
  const scrollKey =
    lastText?.role === "assistant" ? lastText.text.length + lastText.tools.length : active?.items.length;
  // biome-ignore lint/correctness/useExhaustiveDependencies: rolar quando a conversa cresce
  useEffect(() => {
    bottom.current?.scrollIntoView({ behavior: "smooth", block: "end" });
  }, [scrollKey, activeId]);

  const submit = (e?: FormEvent) => {
    e?.preventDefault();
    if (!busy) ask(text);
  };
  const onKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      submit();
    }
  };

  return (
    <div className="-mx-4 -mt-6 -mb-24 flex h-[calc(100dvh-3.5rem)] lg:-mx-8 lg:-mb-12">
      <aside className="hidden w-64 shrink-0 flex-col border-r border-zinc-200 p-3 xl:flex dark:border-zinc-800">
        <button
          type="button"
          onClick={() => chatStore.newConversation()}
          className="flex items-center gap-2 rounded-lg border border-zinc-200 bg-white px-3 py-2 text-sm font-medium hover:bg-zinc-50 dark:border-zinc-800 dark:bg-zinc-900 dark:hover:bg-zinc-800"
        >
          <MessageSquarePlus className="size-4" /> Nova conversa
        </button>
        <p className="mt-5 mb-1 px-2 text-xs font-medium text-zinc-400">Nesta sessão</p>
        <ul className="space-y-0.5 overflow-y-auto">
          {conversations.map((c) => (
            <li key={c.id} className="group relative">
              <button
                type="button"
                onClick={() => chatStore.select(c.id)}
                className={cn(
                  "w-full truncate rounded-md px-2 py-1.5 pr-7 text-left text-sm",
                  c.id === activeId
                    ? "bg-zinc-200/70 font-medium dark:bg-zinc-800"
                    : "text-zinc-600 hover:bg-zinc-100 dark:text-zinc-400 dark:hover:bg-zinc-800/60",
                )}
              >
                {c.title}
              </button>
              <button
                type="button"
                aria-label="Apagar conversa"
                onClick={() => chatStore.remove(c.id)}
                className="absolute top-1.5 right-1.5 hidden text-zinc-400 hover:text-red-600 group-hover:block"
              >
                <Trash2 className="size-3.5" />
              </button>
            </li>
          ))}
        </ul>
      </aside>

      <section className="flex min-w-0 flex-1 flex-col">
        <div className="flex-1 overflow-y-auto">
          <div className="mx-auto max-w-3xl px-4 py-8 lg:px-6">
            {!active || active.items.length === 0 ? (
              <div className="pt-[8vh] text-center">
                <div className="mx-auto flex size-12 items-center justify-center rounded-2xl bg-gradient-to-br from-brand-500 to-brand-700 text-white shadow-lg shadow-brand-500/20">
                  <Sparkles className="size-6" />
                </div>
                <h1 className="mt-5 text-2xl font-semibold tracking-tight">Como posso ajudar?</h1>
                <p className="mx-auto mt-2 max-w-md text-sm text-zinc-500 dark:text-zinc-400">
                  Pergunte sobre pedidos de venda, ordens de produção ou faturas de fornecedor. Eu consulto o SAP com o
                  seu usuário e explico a causa e o que fazer.
                </p>
                <div className="mt-8 grid gap-3 text-left sm:grid-cols-2">
                  {STARTERS.map((s) => (
                    <button
                      key={s.title}
                      type="button"
                      onClick={() => ask(s.prompt, active?.id ?? chatStore.newConversation())}
                      className="rounded-xl border border-zinc-200 bg-white p-4 transition hover:border-brand-300 hover:shadow-sm dark:border-zinc-800 dark:bg-zinc-900 dark:hover:border-brand-800"
                    >
                      <s.icon className="size-4 text-brand-500" />
                      <p className="mt-2 text-sm font-medium">{s.title}</p>
                      <p className="mt-0.5 text-xs text-zinc-500">{s.prompt}</p>
                    </button>
                  ))}
                </div>
              </div>
            ) : (
              <div className="space-y-8">
                {active.items.map((item) =>
                  item.role === "user" ? (
                    <div key={item.id} className="flex justify-end">
                      <div className="max-w-[85%] rounded-2xl rounded-br-md bg-zinc-900 px-4 py-2.5 text-[0.9375rem] text-white dark:bg-zinc-100 dark:text-zinc-900">
                        {item.text}
                      </div>
                    </div>
                  ) : (
                    <AssistantMessage key={item.id} item={item} onAsk={(qq) => ask(qq)} busy={busy} />
                  ),
                )}
              </div>
            )}
            <div ref={bottom} />
          </div>
        </div>

        <div className="border-t border-zinc-200 bg-zinc-50/90 px-4 pt-3 pb-20 backdrop-blur lg:pb-4 dark:border-zinc-800 dark:bg-zinc-950/90">
          <form onSubmit={submit} className="mx-auto max-w-3xl">
            <div className="flex items-end gap-2 rounded-2xl border border-zinc-200 bg-white p-2 shadow-sm focus-within:border-brand-400 focus-within:ring-4 focus-within:ring-brand-500/10 dark:border-zinc-800 dark:bg-zinc-900">
              <textarea
                ref={textarea}
                rows={1}
                value={text}
                onChange={(e) => setText(e.target.value)}
                onKeyDown={onKeyDown}
                placeholder="Pergunte sobre um pedido, ordem ou fatura…"
                className="max-h-40 min-h-10 flex-1 resize-none bg-transparent px-2 py-2 text-[0.9375rem] outline-none placeholder:text-zinc-400"
              />
              {busy && active ? (
                <button
                  type="button"
                  onClick={() => chatStore.stop(active.id)}
                  aria-label="Parar"
                  className="flex size-9 items-center justify-center rounded-xl bg-zinc-900 text-white dark:bg-zinc-100 dark:text-zinc-900"
                >
                  <Square className="size-3.5 fill-current" />
                </button>
              ) : (
                <button
                  type="submit"
                  aria-label="Enviar"
                  disabled={!text.trim()}
                  className="flex size-9 items-center justify-center rounded-xl bg-brand-600 text-white transition hover:bg-brand-700 disabled:bg-zinc-200 disabled:text-zinc-400 dark:disabled:bg-zinc-800"
                >
                  <ArrowUp className="size-4" />
                </button>
              )}
            </div>
            <p className="mt-2 text-center text-xs text-zinc-400">
              {app.ai.provider === "demo"
                ? "Modo demonstração: respostas por regras, sem modelo de IA. "
                : "A IA pode errar: confira os cartões de diagnóstico. "}
              Somente leitura no SAP.
            </p>
          </form>
        </div>
      </section>
    </div>
  );
}
