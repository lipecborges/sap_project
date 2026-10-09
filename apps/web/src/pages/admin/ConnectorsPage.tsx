import type { AdminConnector, AdminConnectorCreated } from "@raiox/contracts";
import { AlertTriangle, Cable, Check, Copy, Loader2, Plus, Trash2 } from "lucide-react";
import { type FormEvent, useState } from "react";
import { toast } from "sonner";
import { Badge } from "../../components/ui/badge";
import { Button } from "../../components/ui/button";
import { Card } from "../../components/ui/card";
import { ConfirmDialog, Modal } from "../../components/ui/dialog";
import { Callout, Field, inputClass } from "../../components/ui/form";
import { EmptyState, ErrorState, Skeleton } from "../../components/ui/misc";
import { PageHeader } from "../../components/ui/page";
import { connectorSnippet, formatDateTime, timeAgo } from "../../lib/admin";
import { errorMessage, useAdminConnectors, useAdminMutation } from "../../lib/admin-queries";
import { api } from "../../lib/api";
import { cn } from "../../lib/utils";

function CopyButton({ text, label }: { text: string; label: string }) {
  const [copied, setCopied] = useState(false);
  async function copy() {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      toast.error("Não foi possível copiar. Selecione o texto e copie manualmente.");
    }
  }
  return (
    <Button variant="outline" size="sm" onClick={copy} aria-label={label}>
      {copied ? <Check className="text-emerald-600" /> : <Copy />}
      {copied ? "Copiado" : "Copiar"}
    </Button>
  );
}

function CreateDialog({ onClose, onCreated }: { onClose: () => void; onCreated: (c: AdminConnectorCreated) => void }) {
  const [name, setName] = useState("");
  const [error, setError] = useState<string>();
  const create = useAdminMutation((n: string) => api.admin.createConnector(n), {
    success: "Conector criado",
    invalidate: [["admin", "connectors"]],
    onSuccess: onCreated,
    toastError: false,
    onError: (err) => setError(errorMessage(err)),
  });
  function submit(e: FormEvent) {
    e.preventDefault();
    if (!name.trim()) return setError("Dê um nome ao conector");
    setError(undefined);
    create.mutate(name.trim());
  }
  return (
    <Modal
      open
      onOpenChange={(o) => !o && !create.isPending && onClose()}
      title="Novo conector"
      description="O conector roda na rede do cliente, perto do SAP, e abre uma conexão segura de saída até o Raio-X."
      className="max-w-md"
      footer={
        <>
          <Button variant="outline" onClick={onClose} disabled={create.isPending}>
            Cancelar
          </Button>
          <Button type="submit" form="connector-form" disabled={create.isPending}>
            {create.isPending && <Loader2 className="animate-spin" />}
            Criar conector
          </Button>
        </>
      }
    >
      <form id="connector-form" onSubmit={submit} noValidate>
        <Field label="Nome" error={error} hint="Ex.: Matriz São Paulo">
          <input
            className={inputClass}
            value={name}
            onChange={(e) => setName(e.target.value)}
            maxLength={60}
            aria-invalid={Boolean(error)}
          />
        </Field>
      </form>
    </Modal>
  );
}

function TokenDialog({ created, onClose }: { created: AdminConnectorCreated; onClose: () => void }) {
  const snippet = connectorSnippet(created.token, window.location.origin);
  return (
    <Modal
      open
      dismissible={false}
      onOpenChange={() => undefined}
      title={`Conector “${created.connector.name}” criado`}
      description="Copie o token agora: por segurança ele não será exibido de novo."
      className="max-w-2xl"
      footer={<Button onClick={onClose}>Já copiei, concluir</Button>}
    >
      <div className="space-y-4">
        <Callout tone="warning" className="flex items-start gap-2">
          <AlertTriangle className="mt-0.5 size-4 shrink-0" />
          <span>
            O Raio-X guarda apenas um resumo (hash) do token. Se perder, será preciso revogar e criar outro conector.
          </span>
        </Callout>
        <div>
          <div className="mb-1.5 flex items-center justify-between gap-3">
            <p className="text-sm font-medium">Token do conector</p>
            <CopyButton text={created.token} label="Copiar token" />
          </div>
          <code className="block overflow-x-auto rounded-lg border border-zinc-200 bg-zinc-50 px-3 py-2.5 font-mono text-xs break-all dark:border-zinc-800 dark:bg-zinc-950">
            {created.token}
          </code>
        </div>
        <div>
          <div className="mb-1.5 flex items-center justify-between gap-3">
            <p className="text-sm font-medium">Executar o conector</p>
            <CopyButton text={snippet} label="Copiar comando" />
          </div>
          <pre className="overflow-x-auto rounded-lg border border-zinc-200 bg-zinc-50 p-3 font-mono text-xs leading-relaxed dark:border-zinc-800 dark:bg-zinc-950">
            {snippet}
          </pre>
          <p className="mt-1.5 text-xs text-zinc-500">
            Troque <code className="font-mono">&lt;sap-host&gt;:&lt;porta&gt;</code> pelo endereço do SAP visto de
            dentro da rede do cliente.
          </p>
        </div>
      </div>
    </Modal>
  );
}

function StatusDot({ connector }: { connector: AdminConnector }) {
  const state = connector.revoked ? "revoked" : connector.online ? "online" : "offline";
  const label = { revoked: "Revogado", online: "Online", offline: "Offline" }[state];
  return (
    <span className="flex items-center gap-2 text-sm">
      <span
        aria-hidden
        className={cn(
          "size-2.5 rounded-full",
          state === "online" && "bg-emerald-500 shadow-[0_0_0_3px] shadow-emerald-500/20",
          state === "offline" && "bg-zinc-400",
          state === "revoked" && "bg-red-500",
        )}
      />
      <span className="font-medium">{label}</span>
    </span>
  );
}

export function ConnectorsPage() {
  const { data, isLoading, error, refetch, isFetching } = useAdminConnectors();
  const [creating, setCreating] = useState(false);
  const [created, setCreated] = useState<AdminConnectorCreated>();
  const [revoking, setRevoking] = useState<AdminConnector>();

  const revoke = useAdminMutation((id: string) => api.admin.revokeConnector(id), {
    success: "Conector revogado",
    invalidate: [
      ["admin", "connectors"],
      ["admin", "systems"],
    ],
    onSuccess: () => setRevoking(undefined),
    onError: () => setRevoking(undefined),
  });

  return (
    <>
      <PageHeader
        title="Conectores"
        description="Agentes on-premise que levam o Raio-X até um SAP que não é acessível pela internet. O status atualiza sozinho."
        actions={
          <Button onClick={() => setCreating(true)}>
            <Plus /> Novo conector
          </Button>
        }
      />
      <Card>
        {isLoading ? (
          <div className="space-y-3 p-5" role="status" aria-busy="true" aria-label="Carregando conectores">
            {[0, 1].map((i) => (
              <Skeleton key={i} className="h-14" />
            ))}
          </div>
        ) : error ? (
          <ErrorState error={error} onRetry={() => refetch()} />
        ) : !data || data.length === 0 ? (
          <EmptyState
            icon={<Cable />}
            title="Nenhum conector ainda"
            description="Crie um conector se o SAP do cliente fica em rede privada, sem acesso direto pela internet."
          />
        ) : (
          <ul className="divide-y divide-zinc-100 dark:divide-zinc-800/70">
            {data.map((c) => (
              <li
                key={c.id}
                className={cn("flex flex-wrap items-center gap-x-4 gap-y-2 px-5 py-4", c.revoked && "opacity-60")}
              >
                <div className="min-w-0 flex-1 basis-56">
                  <p className="truncate font-medium">{c.name}</p>
                  <p className="mt-0.5 text-xs text-zinc-500">Criado em {formatDateTime(c.createdAt)}</p>
                </div>
                <div className="w-28 shrink-0">
                  <StatusDot connector={c} />
                </div>
                <div className="hidden w-36 shrink-0 text-sm sm:block">
                  <p className="text-xs text-zinc-500">Versão</p>
                  <p className="font-medium">{c.version ?? "—"}</p>
                </div>
                <div className="hidden w-32 shrink-0 text-sm md:block">
                  <p className="text-xs text-zinc-500">Visto por último</p>
                  <p className="font-medium" title={formatDateTime(c.lastSeenAt)}>
                    {timeAgo(c.lastSeenAt)}
                  </p>
                </div>
                {c.revoked ? (
                  <Badge className="ml-auto">Revogado</Badge>
                ) : (
                  <Button variant="outline" size="sm" className="ml-auto" onClick={() => setRevoking(c)}>
                    <Trash2 /> Revogar
                  </Button>
                )}
              </li>
            ))}
          </ul>
        )}
        {data && data.length > 0 && (
          <p className="border-t border-zinc-100 px-5 py-2.5 text-xs text-zinc-500 dark:border-zinc-800">
            {isFetching ? "Atualizando status…" : "Status atualizado a cada 15 segundos."}
          </p>
        )}
      </Card>

      {creating && (
        <CreateDialog
          onClose={() => setCreating(false)}
          onCreated={(c) => {
            setCreating(false);
            setCreated(c);
          }}
        />
      )}
      {created && <TokenDialog created={created} onClose={() => setCreated(undefined)} />}
      <ConfirmDialog
        open={revoking !== undefined}
        onOpenChange={(o) => !o && setRevoking(undefined)}
        title={`Revogar o conector “${revoking?.name ?? ""}”?`}
        description="O token deixa de valer e o conector é desconectado na hora. Sistemas SAP que dependem dele ficam indisponíveis até você apontá-los para outro conector. Não dá para desfazer."
        confirmLabel="Revogar conector"
        destructive
        pending={revoke.isPending}
        onConfirm={() => revoking && revoke.mutate(revoking.id)}
      />
    </>
  );
}
