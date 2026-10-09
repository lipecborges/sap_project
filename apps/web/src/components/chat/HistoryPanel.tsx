import type { ConversationSummary } from "@raiox/contracts";
import { useMutation, useQuery } from "@tanstack/react-query";
import { Loader2, MessageSquarePlus, MessagesSquare, Trash2 } from "lucide-react";
import { useMemo, useState } from "react";
import { toast } from "sonner";
import { api, RequestError } from "../../lib/api";
import { chatStore } from "../../lib/chat";
import { groupConversations } from "../../lib/chat-model";
import { CONVERSATIONS_KEY, queryClient } from "../../lib/query-client";
import { cn } from "../../lib/utils";
import { ConfirmDialog } from "../ui/dialog";
import { EmptyState, ErrorState, Skeleton } from "../ui/misc";

/** Histórico do assistente (vem do servidor), agrupado por data; serve a barra lateral e a gaveta do celular. */
export function HistoryPanel({
  activeServerId,
  loadingServerId,
  onOpen,
  onNew,
}: {
  activeServerId?: string;
  loadingServerId?: string;
  onOpen: (id: string) => void;
  onNew: () => void;
}) {
  const { data, isLoading, error, refetch } = useQuery({
    queryKey: CONVERSATIONS_KEY,
    queryFn: api.conversations,
    staleTime: 30_000,
  });
  const groups = useMemo(() => groupConversations(data ?? []), [data]);
  const [toDelete, setToDelete] = useState<ConversationSummary>();

  const remove = useMutation({
    mutationFn: (id: string) => api.deleteConversation(id),
    onSuccess: (_, id) => {
      chatStore.forget(id);
      void queryClient.invalidateQueries({ queryKey: CONVERSATIONS_KEY });
      toast.success("Conversa apagada");
      setToDelete(undefined);
    },
    onError: (err) => {
      toast.error(err instanceof RequestError ? err.message : "Não foi possível apagar a conversa");
      // 404: já não existe no servidor; sincroniza a lista.
      if (err instanceof RequestError && err.status === 404) {
        chatStore.forget(toDelete?.id ?? "");
        void queryClient.invalidateQueries({ queryKey: CONVERSATIONS_KEY });
        setToDelete(undefined);
      }
    },
  });

  return (
    <div className="flex h-full min-h-0 flex-col p-3">
      <button
        type="button"
        onClick={onNew}
        className="flex items-center gap-2 rounded-lg border border-zinc-200 bg-white px-3 py-2 text-sm font-medium shadow-xs hover:bg-zinc-50 dark:border-zinc-800 dark:bg-zinc-900 dark:hover:bg-zinc-800"
      >
        <MessageSquarePlus className="size-4 text-brand-600 dark:text-brand-400" /> Nova conversa
      </button>

      <div className="mt-4 min-h-0 flex-1 overflow-y-auto pr-0.5">
        {isLoading ? (
          <div className="space-y-2 px-1 pt-1" role="status" aria-busy="true" aria-label="Carregando histórico">
            {[70, 90, 60, 80, 50].map((w) => (
              <Skeleton key={w} className="h-7" />
            ))}
          </div>
        ) : error ? (
          <ErrorState error={error} onRetry={() => refetch()} />
        ) : groups.length === 0 ? (
          <EmptyState
            icon={<MessagesSquare />}
            title="Sem conversas ainda"
            description="Suas conversas com o assistente ficam salvas aqui."
          />
        ) : (
          groups.map((g) => (
            <section key={g.label} className="mb-4" aria-label={g.label}>
              <h3 className="mb-1 px-2 text-xs font-medium text-zinc-400">{g.label}</h3>
              <ul className="space-y-0.5">
                {g.conversations.map((c) => {
                  const active = c.id === activeServerId;
                  return (
                    <li key={c.id} className="group relative">
                      <button
                        type="button"
                        onClick={() => onOpen(c.id)}
                        aria-current={active ? "true" : undefined}
                        className={cn(
                          "flex w-full items-center gap-2 rounded-md px-2 py-1.5 pr-8 text-left text-sm",
                          active
                            ? "bg-zinc-200/70 font-medium dark:bg-zinc-800"
                            : "text-zinc-600 hover:bg-zinc-100 dark:text-zinc-400 dark:hover:bg-zinc-800/60",
                        )}
                      >
                        <span className="min-w-0 flex-1 truncate">{c.title || "Conversa sem título"}</span>
                        {loadingServerId === c.id && (
                          <Loader2 className="size-3.5 shrink-0 animate-spin text-zinc-400" />
                        )}
                      </button>
                      <button
                        type="button"
                        aria-label={`Apagar conversa: ${c.title}`}
                        onClick={() => setToDelete(c)}
                        className="absolute top-1/2 right-1 flex size-6 -translate-y-1/2 items-center justify-center rounded text-zinc-400 opacity-0 transition hover:bg-zinc-200 hover:text-red-600 focus-visible:opacity-100 group-hover:opacity-100 [@media(hover:none)]:opacity-100 dark:hover:bg-zinc-700"
                      >
                        <Trash2 className="size-3.5" />
                      </button>
                    </li>
                  );
                })}
              </ul>
            </section>
          ))
        )}
      </div>

      <ConfirmDialog
        open={toDelete !== undefined}
        onOpenChange={(o) => !o && setToDelete(undefined)}
        title="Apagar conversa?"
        description={
          <>
            A conversa <strong className="text-zinc-700 dark:text-zinc-200">“{toDelete?.title}”</strong> será removida
            do histórico. Esta ação não pode ser desfeita.
          </>
        }
        confirmLabel="Apagar"
        destructive
        pending={remove.isPending}
        onConfirm={() => toDelete && remove.mutate(toDelete.id)}
      />
    </div>
  );
}
