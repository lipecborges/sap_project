import type { AdminUser, AdminUserUpdate } from "@raiox/contracts";
import { Link } from "@tanstack/react-router";
import { Ban, KeyRound, MoreHorizontal, Search, ShieldCheck, ShieldOff, Unlock, UserX } from "lucide-react";
import { DropdownMenu } from "radix-ui";
import { useMemo, useState } from "react";
import { Badge } from "../../components/ui/badge";
import { Card } from "../../components/ui/card";
import { ConfirmDialog } from "../../components/ui/dialog";
import { inputClass, tableHeadClass, tbodyClass, tdClass, thClass } from "../../components/ui/form";
import { EmptyState, ErrorState, Progress, Skeleton } from "../../components/ui/misc";
import { PageHeader } from "../../components/ui/page";
import { filterUsers, seatPercent, timeAgo } from "../../lib/admin";
import { useAdminLicense, useAdminMutation, useAdminUsers } from "../../lib/admin-queries";
import { api } from "../../lib/api";
import { useSession } from "../../lib/auth";
import { cn } from "../../lib/utils";

type ActionKind = "makeAdmin" | "makeUser" | "block" | "unblock" | "release";

interface PendingAction {
  user: AdminUser;
  kind: ActionKind;
}

const ACTIONS: Record<
  ActionKind,
  {
    title: (u: AdminUser) => string;
    body: (u: AdminUser) => string;
    confirm: string;
    destructive: boolean;
    patch: AdminUserUpdate;
    done: (u: AdminUser) => string;
  }
> = {
  makeAdmin: {
    title: (u) => `Tornar ${u.sapUser} administrador?`,
    body: (u) =>
      `${u.sapUser} poderá gerenciar usuários, licença, sistemas SAP e conectores, e consultar a auditoria deste cliente.`,
    confirm: "Tornar administrador",
    destructive: false,
    patch: { role: "admin" },
    done: (u) => `${u.sapUser} agora é administrador`,
  },
  makeUser: {
    title: (u) => `Remover o papel de administrador de ${u.sapUser}?`,
    body: (u) => `${u.sapUser} continua usando o Raio-X, mas perde o acesso à área de Administração.`,
    confirm: "Tornar usuário comum",
    destructive: true,
    patch: { role: "user" },
    done: (u) => `${u.sapUser} agora é usuário comum`,
  },
  block: {
    title: (u) => `Bloquear ${u.sapUser}?`,
    body: (u) =>
      `${u.sapUser} não conseguirá entrar no Raio-X enquanto estiver bloqueado. A licença continua reservada para esse usuário.`,
    confirm: "Bloquear",
    destructive: true,
    patch: { blocked: true },
    done: (u) => `${u.sapUser} foi bloqueado`,
  },
  unblock: {
    title: (u) => `Desbloquear ${u.sapUser}?`,
    body: (u) => `${u.sapUser} poderá entrar no Raio-X novamente.`,
    confirm: "Desbloquear",
    destructive: false,
    patch: { blocked: false },
    done: (u) => `${u.sapUser} foi desbloqueado`,
  },
  release: {
    title: (u) => `Liberar a licença de ${u.sapUser}?`,
    body: (u) =>
      `${u.sapUser} deixa de ocupar uma licença de usuário nomeado e perde o acesso ao Raio-X até conseguir outra. Use isto para reaproveitar a licença de quem não usa mais o produto.`,
    confirm: "Liberar licença",
    destructive: true,
    patch: { seat: false },
    done: (u) => `Licença de ${u.sapUser} liberada`,
  },
};

function LicenseMeter() {
  const { data, isLoading } = useAdminLicense();
  if (isLoading) return <Skeleton className="mb-6 h-[4.5rem] w-full rounded-xl" />;
  if (!data) return null;
  const pct = seatPercent(data.usedSeats, data.maxNamedUsers);
  const tone = pct >= 100 ? "critical" : pct >= 90 ? "warning" : "brand";
  return (
    <Card className="mb-6 flex flex-wrap items-center gap-x-6 gap-y-3 px-5 py-4">
      <div className="min-w-48 flex-1">
        <div className="flex items-baseline justify-between gap-3">
          <p className="text-sm font-medium">Licenças de usuário nomeado</p>
          <p className="text-sm tabular-nums text-zinc-500">
            <span className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">{data.usedSeats}</span> de{" "}
            {data.maxNamedUsers} em uso
          </p>
        </div>
        <Progress value={pct} tone={tone} className="mt-2.5" />
        {pct >= 90 && (
          <p
            className={cn(
              "mt-2 text-xs",
              pct >= 100 ? "text-red-600 dark:text-red-400" : "text-amber-700 dark:text-amber-400",
            )}
          >
            {pct >= 100
              ? "Todas as licenças estão em uso: novos usuários não conseguem entrar."
              : "Quase no limite de licenças."}
          </p>
        )}
      </div>
      <Link to="/admin/licenca" className="text-sm font-medium text-brand-600 hover:underline dark:text-brand-400">
        Ver licença
      </Link>
    </Card>
  );
}

function RowMenu({ user, self, onAction }: { user: AdminUser; self: boolean; onAction: (a: ActionKind) => void }) {
  const items: { kind: ActionKind; label: string; icon: typeof Ban; disabled?: boolean; hint?: string }[] = [
    user.role === "admin"
      ? {
          kind: "makeUser",
          label: "Tornar usuário comum",
          icon: ShieldOff,
          disabled: self,
          hint: "Você não pode remover o seu próprio acesso",
        }
      : { kind: "makeAdmin", label: "Tornar administrador", icon: ShieldCheck },
    user.blocked
      ? { kind: "unblock", label: "Desbloquear", icon: Unlock }
      : { kind: "block", label: "Bloquear", icon: Ban, disabled: self, hint: "Você não pode bloquear a si mesmo" },
    { kind: "release", label: "Liberar licença", icon: KeyRound, disabled: !user.hasSeat, hint: "Sem licença em uso" },
  ];
  return (
    <DropdownMenu.Root>
      <DropdownMenu.Trigger
        aria-label={`Ações para ${user.sapUser}`}
        className="flex size-8 items-center justify-center rounded-md text-zinc-500 hover:bg-zinc-100 hover:text-zinc-900 data-[state=open]:bg-zinc-100 dark:hover:bg-zinc-800 dark:hover:text-zinc-100 dark:data-[state=open]:bg-zinc-800"
      >
        <MoreHorizontal className="size-4" />
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content
          align="end"
          sideOffset={4}
          className="z-50 min-w-52 rounded-lg border border-zinc-200 bg-white p-1 shadow-lg dark:border-zinc-800 dark:bg-zinc-900"
        >
          {items.map((i) => (
            <DropdownMenu.Item
              key={i.kind}
              disabled={i.disabled}
              title={i.disabled ? i.hint : undefined}
              onSelect={() => onAction(i.kind)}
              className="flex cursor-pointer items-center gap-2 rounded-md px-2 py-1.5 text-sm outline-none data-[disabled]:cursor-not-allowed data-[disabled]:opacity-40 data-[highlighted]:bg-zinc-100 dark:data-[highlighted]:bg-zinc-800"
            >
              <i.icon className="size-4 text-zinc-400" /> {i.label}
            </DropdownMenu.Item>
          ))}
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}

export function UsersPage() {
  const { me } = useSession();
  const { data, isLoading, error, refetch } = useAdminUsers();
  const [query, setQuery] = useState("");
  const [pending, setPending] = useState<PendingAction>();
  const users = useMemo(() => filterUsers(data ?? [], query), [data, query]);

  const mutation = useAdminMutation(
    ({ user, kind }: PendingAction) => api.admin.updateUser(user.sapUser, ACTIONS[kind].patch),
    {
      success: ({ user, kind }) => ACTIONS[kind].done(user),
      invalidate: [
        ["admin", "users"],
        ["admin", "license"],
      ],
      onSuccess: () => setPending(undefined),
      onError: () => setPending(undefined),
    },
  );

  return (
    <>
      <PageHeader
        title="Usuários"
        description="Quem já entrou no Raio-X com um usuário SAP: papel, licença e acesso."
      />
      <LicenseMeter />

      <Card>
        <div className="flex flex-wrap items-center gap-3 border-b border-zinc-100 px-5 py-3 dark:border-zinc-800">
          <div className="relative min-w-52 flex-1 sm:max-w-xs">
            <Search className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-zinc-400" />
            <input
              type="search"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Buscar usuário"
              aria-label="Buscar usuário"
              className={cn(inputClass, "h-9 pl-9")}
            />
          </div>
          {data && (
            <p className="text-sm text-zinc-500">
              {users.length === data.length ? `${data.length} usuários` : `${users.length} de ${data.length}`}
            </p>
          )}
        </div>

        {isLoading ? (
          <div className="space-y-3 p-5" role="status" aria-busy="true" aria-label="Carregando usuários">
            {[0, 1, 2, 3].map((i) => (
              <Skeleton key={i} className="h-10" />
            ))}
          </div>
        ) : error ? (
          <ErrorState error={error} onRetry={() => refetch()} />
        ) : users.length === 0 ? (
          <EmptyState
            icon={<UserX />}
            title={query ? "Nenhum usuário encontrado" : "Nenhum usuário ainda"}
            description={
              query
                ? "Tente outro nome ou usuário SAP."
                : "Os usuários aparecem aqui depois do primeiro login no Raio-X."
            }
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead>
                <tr className={tableHeadClass}>
                  <th scope="col" className={thClass}>
                    Usuário SAP
                  </th>
                  <th scope="col" className={cn(thClass, "hidden sm:table-cell")}>
                    Papel
                  </th>
                  <th scope="col" className={cn(thClass, "hidden md:table-cell")}>
                    Licença
                  </th>
                  <th scope="col" className={cn(thClass, "hidden sm:table-cell")}>
                    Acesso
                  </th>
                  <th scope="col" className={cn(thClass, "hidden md:table-cell")}>
                    Último acesso
                  </th>
                  <th scope="col" className={cn(thClass, "hidden text-right lg:table-cell")}>
                    Sessões ativas
                  </th>
                  <th scope="col" className={cn(thClass, "w-10")}>
                    <span className="sr-only">Ações</span>
                  </th>
                </tr>
              </thead>
              <tbody className={tbodyClass}>
                {users.map((u) => {
                  const self = u.sapUser === me.user;
                  return (
                    <tr
                      key={u.sapUser}
                      className={cn(
                        "hover:bg-zinc-50/70 dark:hover:bg-zinc-800/30",
                        u.blocked && "bg-zinc-50/50 dark:bg-zinc-900/60",
                      )}
                    >
                      <td className={tdClass}>
                        <p className="font-medium">
                          <span className="font-mono text-[0.8125rem]">{u.sapUser}</span>
                          {self && <span className="ml-2 text-xs font-normal text-zinc-400">você</span>}
                        </p>
                        {u.displayName && <p className="text-xs text-zinc-500">{u.displayName}</p>}
                        <div className="mt-1.5 flex flex-wrap items-center gap-1.5 sm:hidden">
                          {u.role === "admin" && (
                            <Badge tone="brand">
                              <ShieldCheck /> Admin
                            </Badge>
                          )}
                          {u.blocked && (
                            <Badge tone="critical">
                              <Ban /> Bloqueado
                            </Badge>
                          )}
                          {!u.hasSeat && <Badge>Sem licença</Badge>}
                        </div>
                        <p className="mt-1 text-xs text-zinc-500 md:hidden">acesso {timeAgo(u.lastLoginAt)}</p>
                      </td>
                      <td className={cn(tdClass, "hidden sm:table-cell")}>
                        {u.role === "admin" ? (
                          <Badge tone="brand">
                            <ShieldCheck /> Admin
                          </Badge>
                        ) : (
                          <Badge>Usuário</Badge>
                        )}
                      </td>
                      <td className={cn(tdClass, "hidden md:table-cell")}>
                        {u.hasSeat ? <Badge tone="good">Em uso</Badge> : <Badge>Sem licença</Badge>}
                      </td>
                      <td className={cn(tdClass, "hidden sm:table-cell")}>
                        {u.blocked ? (
                          <Badge tone="critical">
                            <Ban /> Bloqueado
                          </Badge>
                        ) : (
                          <span className="text-zinc-500">Liberado</span>
                        )}
                      </td>
                      <td
                        className={cn(
                          tdClass,
                          "hidden whitespace-nowrap text-zinc-600 md:table-cell dark:text-zinc-400",
                        )}
                      >
                        {timeAgo(u.lastLoginAt)}
                      </td>
                      <td className={cn(tdClass, "hidden text-right tabular-nums lg:table-cell")}>
                        {u.activeSessions}
                      </td>
                      <td className={cn(tdClass, "text-right")}>
                        <RowMenu user={u} self={self} onAction={(kind) => setPending({ user: u, kind })} />
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <ConfirmDialog
        open={pending !== undefined}
        onOpenChange={(o) => !o && setPending(undefined)}
        title={pending ? ACTIONS[pending.kind].title(pending.user) : ""}
        description={pending ? ACTIONS[pending.kind].body(pending.user) : ""}
        confirmLabel={pending ? ACTIONS[pending.kind].confirm : ""}
        destructive={pending ? ACTIONS[pending.kind].destructive : false}
        pending={mutation.isPending}
        onConfirm={() => pending && mutation.mutate(pending)}
      />
    </>
  );
}
