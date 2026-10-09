import { type AdminSystem, AdminSystemInput, type SystemTestResult } from "@raiox/contracts";
import {
  CheckCircle2,
  Loader2,
  Lock,
  MoreHorizontal,
  Pencil,
  Plug,
  Plus,
  Server,
  Star,
  Trash2,
  XCircle,
  Zap,
} from "lucide-react";
import { DropdownMenu } from "radix-ui";
import { type FormEvent, useEffect, useRef, useState } from "react";
import { Badge } from "../../components/ui/badge";
import { Button } from "../../components/ui/button";
import { Card } from "../../components/ui/card";
import { ConfirmDialog, Modal } from "../../components/ui/dialog";
import { Callout, Field, inputClass, Select } from "../../components/ui/form";
import { EmptyState, ErrorState, Skeleton } from "../../components/ui/misc";
import { PageHeader } from "../../components/ui/page";
import { formatMs } from "../../lib/admin";
import { errorMessage, useAdminConnectors, useAdminMutation, useAdminSystems } from "../../lib/admin-queries";
import { api, RequestError } from "../../lib/api";

const RELEASE_LABEL: Record<string, string> = { ECC: "ECC", S4: "S/4HANA", NW: "NetWeaver" };

interface FormState {
  id: string;
  name: string;
  transport: "direct" | "connector";
  baseUrl: string;
  sapClient: string;
  connectorId: string;
  isDefault: boolean;
}

const EMPTY: FormState = {
  id: "",
  name: "",
  transport: "direct",
  baseUrl: "",
  sapClient: "",
  connectorId: "",
  isDefault: false,
};

function toForm(s: AdminSystem): FormState {
  return {
    id: s.id,
    name: s.name,
    transport: s.transport,
    baseUrl: s.baseUrl ?? "",
    sapClient: s.sapClient ?? "",
    connectorId: s.connectorId ?? "",
    isDefault: s.isDefault,
  };
}

/** Valida o formulário com o contrato e devolve a entrada da API ou os erros por campo. */
function buildInput(
  f: FormState,
  editing: boolean,
): { input: AdminSystemInput } | { errors: Partial<Record<keyof FormState, string>> } {
  const errors: Partial<Record<keyof FormState, string>> = {};
  const direct = f.transport === "direct";
  if (!editing && !f.id) errors.id = "Informe um identificador";
  if (!f.name.trim()) errors.name = "Informe o nome";
  if (direct && !f.baseUrl.trim()) errors.baseUrl = "Informe o endereço do SAP";
  if (!direct && !f.connectorId) errors.connectorId = "Escolha o conector";
  const candidate = {
    ...(editing ? {} : { id: f.id }),
    name: f.name.trim(),
    transport: f.transport,
    baseUrl: direct ? f.baseUrl.trim() : null,
    sapClient: f.sapClient.trim() || null,
    connectorId: direct ? null : f.connectorId,
    isDefault: f.isDefault,
  };
  const parsed = AdminSystemInput.safeParse(candidate);
  if (!parsed.success) {
    for (const issue of parsed.error.issues) {
      const key = issue.path[0] as keyof FormState | undefined;
      if (key && !errors[key]) errors[key] = issue.message;
    }
  }
  if (Object.keys(errors).length > 0 || !parsed.success) return { errors };
  return { input: parsed.data };
}

function SystemFormDialog({ system, onClose }: { system?: AdminSystem; onClose: () => void }) {
  const editing = system !== undefined;
  const [form, setForm] = useState<FormState>(system ? toForm(system) : EMPTY);
  const [errors, setErrors] = useState<Partial<Record<keyof FormState, string>>>({});
  const [formError, setFormError] = useState<string>();
  const connectors = useAdminConnectors();
  const set = <K extends keyof FormState>(key: K, value: FormState[K]) => setForm((f) => ({ ...f, [key]: value }));

  const save = useAdminMutation(
    (input: AdminSystemInput) => (editing ? api.admin.updateSystem(system.id, input) : api.admin.createSystem(input)),
    {
      success: editing ? "Sistema atualizado" : "Sistema criado",
      invalidate: [["admin", "systems"]],
      onSuccess: onClose,
      toastError: false,
      onError: (err) => {
        if (err instanceof RequestError && err.params) {
          setErrors(err.params as Partial<Record<keyof FormState, string>>);
          setFormError(undefined);
        } else setFormError(errorMessage(err));
      },
    },
  );

  function submit(e: FormEvent) {
    e.preventDefault();
    setFormError(undefined);
    const built = buildInput(form, editing);
    if ("errors" in built) return setErrors(built.errors);
    setErrors({});
    save.mutate(built.input);
  }

  const available = (connectors.data ?? []).filter((c) => !c.revoked || c.id === form.connectorId);

  return (
    <Modal
      open
      onOpenChange={(o) => !o && !save.isPending && onClose()}
      title={editing ? `Editar ${system.name}` : "Novo sistema SAP"}
      description="Sistemas disponíveis para os usuários na tela de login."
      footer={
        <>
          <Button variant="outline" onClick={onClose} disabled={save.isPending}>
            Cancelar
          </Button>
          <Button type="submit" form="system-form" disabled={save.isPending}>
            {save.isPending && <Loader2 className="animate-spin" />}
            {editing ? "Salvar" : "Criar sistema"}
          </Button>
        </>
      }
    >
      <form id="system-form" onSubmit={submit} className="space-y-4" noValidate>
        <div className="grid gap-4 sm:grid-cols-[1fr_1.4fr]">
          <Field label="Identificador" error={errors.id} hint={editing ? "Não pode ser alterado" : "Ex.: prd, qas"}>
            <input
              className={inputClass}
              value={form.id}
              onChange={(e) => set("id", e.target.value.toLowerCase())}
              disabled={editing}
              maxLength={20}
              aria-invalid={Boolean(errors.id)}
              autoCapitalize="none"
              spellCheck={false}
            />
          </Field>
          <Field label="Nome" error={errors.name}>
            <input
              className={inputClass}
              value={form.name}
              onChange={(e) => set("name", e.target.value)}
              maxLength={40}
              placeholder="Produção"
              aria-invalid={Boolean(errors.name)}
            />
          </Field>
        </div>

        <Field label="Como o Raio-X chega ao SAP" error={errors.transport}>
          <Select value={form.transport} onChange={(e) => set("transport", e.target.value as FormState["transport"])}>
            <option value="direct">Direto (a API acessa o SAP pela rede)</option>
            <option value="connector">Por conector on-premise</option>
          </Select>
        </Field>

        {form.transport === "direct" ? (
          <Field
            label="URL do SAP"
            error={errors.baseUrl}
            hint="Endereço base do SAP, ex.: https://sap.empresa.com:8443"
          >
            <input
              className={inputClass}
              type="url"
              value={form.baseUrl}
              onChange={(e) => set("baseUrl", e.target.value)}
              placeholder="https://sap.empresa.com:8443"
              aria-invalid={Boolean(errors.baseUrl)}
              spellCheck={false}
            />
          </Field>
        ) : (
          <Field
            label="Conector"
            error={errors.connectorId}
            hint={
              available.length === 0 && !connectors.isLoading
                ? "Nenhum conector disponível: crie um em Conectores."
                : undefined
            }
          >
            <Select
              value={form.connectorId}
              onChange={(e) => set("connectorId", e.target.value)}
              aria-invalid={Boolean(errors.connectorId)}
            >
              <option value="">Selecione…</option>
              {available.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                  {c.revoked ? " (revogado)" : c.online ? "" : " (offline)"}
                </option>
              ))}
            </Select>
          </Field>
        )}

        <div className="grid items-end gap-4 sm:grid-cols-2">
          <Field label="Mandante" error={errors.sapClient} hint="3 dígitos (opcional)">
            <input
              className={inputClass}
              value={form.sapClient}
              onChange={(e) => set("sapClient", e.target.value.replace(/\D/g, "").slice(0, 3))}
              inputMode="numeric"
              placeholder="100"
              aria-invalid={Boolean(errors.sapClient)}
            />
          </Field>
          <label className="flex h-10 items-center gap-2.5 text-sm font-medium">
            <input
              type="checkbox"
              checked={form.isDefault}
              onChange={(e) => set("isDefault", e.target.checked)}
              className="size-4 rounded border-zinc-300 accent-brand-600"
            />
            Sistema padrão
          </label>
        </div>

        {formError && <Callout tone="critical">{formError}</Callout>}
      </form>
    </Modal>
  );
}

function TestDialog({ system, onClose }: { system: AdminSystem; onClose: () => void }) {
  const [result, setResult] = useState<SystemTestResult>();
  const [failure, setFailure] = useState<string>();
  const run = useAdminMutation(() => api.admin.testSystem(system.id), {
    success: "Teste concluído",
    invalidate: [],
    toastError: false,
    onSuccess: (r) => setResult(r),
    onError: (err) => setFailure(errorMessage(err)),
  });
  const started = useRef(false);
  const start = () => {
    setResult(undefined);
    setFailure(undefined);
    run.mutate();
  };
  // biome-ignore lint/correctness/useExhaustiveDependencies: dispara o teste uma única vez ao abrir
  useEffect(() => {
    if (started.current) return;
    started.current = true;
    start();
  }, []);

  return (
    <Modal
      open
      onOpenChange={(o) => !o && onClose()}
      title={`Testar conexão: ${system.name}`}
      description="O teste chama o SAP com a credencial do administrador logado."
      className="max-w-md"
      footer={
        <>
          <Button variant="outline" onClick={start} disabled={run.isPending}>
            Testar de novo
          </Button>
          <Button onClick={onClose}>Fechar</Button>
        </>
      }
    >
      {run.isPending ? (
        <div className="flex items-center gap-2 py-4 text-sm text-zinc-500" role="status">
          <Loader2 className="size-4 animate-spin" /> Consultando o SAP…
        </div>
      ) : failure ? (
        <Callout tone="critical">{failure}</Callout>
      ) : result?.ok ? (
        <div>
          <p className="flex items-center gap-2 text-sm font-medium text-emerald-700 dark:text-emerald-400">
            <CheckCircle2 className="size-5" /> Conexão estabelecida
          </p>
          <dl className="mt-4 grid grid-cols-2 gap-x-6 gap-y-3 text-sm">
            <div>
              <dt className="text-xs text-zinc-500">Latência</dt>
              <dd className="font-medium tabular-nums">{formatMs(result.latencyMs)}</dd>
            </div>
            <div>
              <dt className="text-xs text-zinc-500">Add-on Raio-X</dt>
              <dd className="font-medium">{result.health?.addonVersion ?? "—"}</dd>
            </div>
            <div>
              <dt className="text-xs text-zinc-500">Sistema</dt>
              <dd className="font-medium">
                {result.health ? `${result.health.system.sid}/${result.health.system.client}` : "—"}
              </dd>
            </div>
            <div>
              <dt className="text-xs text-zinc-500">Release</dt>
              <dd className="font-medium">
                {result.health ? (RELEASE_LABEL[result.health.system.release] ?? result.health.system.release) : "—"}
              </dd>
            </div>
          </dl>
        </div>
      ) : result ? (
        <div>
          <p className="flex items-center gap-2 text-sm font-medium text-red-700 dark:text-red-400">
            <XCircle className="size-5" /> Falha na conexão
          </p>
          <Callout tone="critical" className="mt-3">
            {result.error?.message ?? "O SAP não respondeu."}
            {result.error?.code && <span className="mt-1 block font-mono text-xs opacity-80">{result.error.code}</span>}
          </Callout>
          <p className="mt-3 text-xs text-zinc-500">Tempo até a falha: {formatMs(result.latencyMs)}</p>
        </div>
      ) : null}
    </Modal>
  );
}

function SystemRow({
  system,
  connectorName,
  onEdit,
  onTest,
  onDelete,
}: {
  system: AdminSystem;
  connectorName?: string;
  onEdit: () => void;
  onTest: () => void;
  onDelete: () => void;
}) {
  const where =
    system.transport === "connector"
      ? `Conector${connectorName ? ` · ${connectorName}` : ""}`
      : (system.baseUrl ?? "Sem endereço");
  return (
    <li className="flex items-start gap-3 px-5 py-4">
      <span className="mt-0.5 flex size-9 shrink-0 items-center justify-center rounded-lg bg-zinc-100 text-zinc-500 dark:bg-zinc-800">
        {system.transport === "connector" ? <Plug className="size-4" /> : <Server className="size-4" />}
      </span>
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
          <p className="font-medium">{system.name}</p>
          <span className="font-mono text-xs text-zinc-400">{system.id}</span>
          {system.isDefault && (
            <Badge tone="brand">
              <Star /> Padrão
            </Badge>
          )}
          {system.managedByEnv && (
            <Badge title="Definido nas variáveis de ambiente do servidor">
              <Lock /> Somente leitura
            </Badge>
          )}
        </div>
        <p className="mt-0.5 truncate text-sm text-zinc-500 dark:text-zinc-400">
          {where}
          {system.sapClient ? ` · mandante ${system.sapClient}` : ""}
        </p>
        {system.managedByEnv && (
          <p className="mt-1.5 text-xs text-zinc-500">
            Este sistema vem da configuração do servidor (variáveis SAP_*). Para alterá-lo, edite a configuração e
            reinicie a API.
          </p>
        )}
      </div>
      <Button variant="outline" size="sm" onClick={onTest} className="hidden sm:inline-flex">
        <Zap /> Testar conexão
      </Button>
      <DropdownMenu.Root>
        <DropdownMenu.Trigger
          aria-label={`Ações para ${system.name}`}
          className="flex size-8 shrink-0 items-center justify-center rounded-md text-zinc-500 hover:bg-zinc-100 hover:text-zinc-900 data-[state=open]:bg-zinc-100 dark:hover:bg-zinc-800 dark:hover:text-zinc-100 dark:data-[state=open]:bg-zinc-800"
        >
          <MoreHorizontal className="size-4" />
        </DropdownMenu.Trigger>
        <DropdownMenu.Portal>
          <DropdownMenu.Content
            align="end"
            sideOffset={4}
            className="z-50 min-w-48 rounded-lg border border-zinc-200 bg-white p-1 shadow-lg dark:border-zinc-800 dark:bg-zinc-900"
          >
            <DropdownMenu.Item
              onSelect={onTest}
              className="flex cursor-pointer items-center gap-2 rounded-md px-2 py-1.5 text-sm outline-none data-[highlighted]:bg-zinc-100 sm:hidden dark:data-[highlighted]:bg-zinc-800"
            >
              <Zap className="size-4 text-zinc-400" /> Testar conexão
            </DropdownMenu.Item>
            <DropdownMenu.Item
              onSelect={onEdit}
              disabled={system.managedByEnv}
              className="flex cursor-pointer items-center gap-2 rounded-md px-2 py-1.5 text-sm outline-none data-[disabled]:cursor-not-allowed data-[disabled]:opacity-40 data-[highlighted]:bg-zinc-100 dark:data-[highlighted]:bg-zinc-800"
            >
              <Pencil className="size-4 text-zinc-400" /> Editar
            </DropdownMenu.Item>
            <DropdownMenu.Item
              onSelect={onDelete}
              disabled={system.managedByEnv}
              className="flex cursor-pointer items-center gap-2 rounded-md px-2 py-1.5 text-sm text-red-600 outline-none data-[disabled]:cursor-not-allowed data-[disabled]:opacity-40 data-[highlighted]:bg-red-50 dark:text-red-400 dark:data-[highlighted]:bg-red-950/40"
            >
              <Trash2 className="size-4" /> Remover
            </DropdownMenu.Item>
          </DropdownMenu.Content>
        </DropdownMenu.Portal>
      </DropdownMenu.Root>
    </li>
  );
}

export function SystemsPage() {
  const { data, isLoading, error, refetch } = useAdminSystems();
  const connectors = useAdminConnectors();
  const [form, setForm] = useState<{ system?: AdminSystem }>();
  const [testing, setTesting] = useState<AdminSystem>();
  const [removing, setRemoving] = useState<AdminSystem>();

  const remove = useAdminMutation((id: string) => api.admin.deleteSystem(id), {
    success: "Sistema removido",
    invalidate: [["admin", "systems"]],
    onSuccess: () => setRemoving(undefined),
    onError: () => setRemoving(undefined),
  });

  return (
    <>
      <PageHeader
        title="Sistemas SAP"
        description="Ambientes SAP que os usuários podem escolher ao entrar no Raio-X."
        actions={
          <Button onClick={() => setForm({})}>
            <Plus /> Novo sistema
          </Button>
        }
      />
      <Card>
        {isLoading ? (
          <div className="space-y-3 p-5" role="status" aria-busy="true" aria-label="Carregando sistemas">
            {[0, 1].map((i) => (
              <Skeleton key={i} className="h-14" />
            ))}
          </div>
        ) : error ? (
          <ErrorState error={error} onRetry={() => refetch()} />
        ) : !data || data.length === 0 ? (
          <EmptyState
            icon={<Server />}
            title="Nenhum sistema cadastrado"
            description="Cadastre o SAP que os usuários vão consultar."
          />
        ) : (
          <ul className="divide-y divide-zinc-100 dark:divide-zinc-800/70">
            {data.map((s) => (
              <SystemRow
                key={s.id}
                system={s}
                connectorName={connectors.data?.find((c) => c.id === s.connectorId)?.name}
                onEdit={() => setForm({ system: s })}
                onTest={() => setTesting(s)}
                onDelete={() => setRemoving(s)}
              />
            ))}
          </ul>
        )}
      </Card>

      {form && (
        <SystemFormDialog key={form.system?.id ?? "new"} system={form.system} onClose={() => setForm(undefined)} />
      )}
      {testing && <TestDialog key={testing.id} system={testing} onClose={() => setTesting(undefined)} />}
      <ConfirmDialog
        open={removing !== undefined}
        onOpenChange={(o) => !o && setRemoving(undefined)}
        title={`Remover ${removing?.name ?? "sistema"}?`}
        description="Os usuários não poderão mais escolher este sistema ao entrar, e as sessões abertas nele deixam de funcionar. Os registros de auditoria são mantidos."
        confirmLabel="Remover sistema"
        destructive
        pending={remove.isPending}
        onConfirm={() => removing && remove.mutate(removing.id)}
      />
    </>
  );
}
