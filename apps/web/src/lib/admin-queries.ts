import { useInfiniteQuery, useMutation, useQuery } from "@tanstack/react-query";
import { toast } from "sonner";
import type { AuditFilters } from "./admin";
import { api, RequestError } from "./api";
import { queryClient } from "./query-client";

/** Consultas e mutações da área de administração (TanStack Query). */

export const adminKeys = {
  users: ["admin", "users"] as const,
  license: ["admin", "license"] as const,
  systems: ["admin", "systems"] as const,
  connectors: ["admin", "connectors"] as const,
  audit: (filters: AuditFilters) => ["admin", "audit", filters] as const,
  usage: (days: number) => ["admin", "usage", days] as const,
};

export const useAdminUsers = () => useQuery({ queryKey: adminKeys.users, queryFn: api.admin.users });
export const useAdminLicense = () => useQuery({ queryKey: adminKeys.license, queryFn: api.admin.license });
export const useAdminSystems = () => useQuery({ queryKey: adminKeys.systems, queryFn: api.admin.systems });

/** Conectores: o status online/offline muda sozinho, então atualiza a cada 15 s enquanto a tela está aberta. */
export const useAdminConnectors = () =>
  useQuery({
    queryKey: adminKeys.connectors,
    queryFn: api.admin.connectors,
    refetchInterval: 15_000,
    refetchIntervalInBackground: false,
  });

export const useAdminUsage = (days = 30) =>
  useQuery({ queryKey: adminKeys.usage(days), queryFn: () => api.admin.usage(days), staleTime: 60_000 });

export function useAdminAudit(filters: AuditFilters) {
  return useInfiniteQuery({
    queryKey: adminKeys.audit(filters),
    queryFn: ({ pageParam }) => api.admin.audit(filters, pageParam),
    initialPageParam: undefined as number | undefined,
    getNextPageParam: (last) => last.nextBefore ?? undefined,
  });
}

export function errorMessage(err: unknown, fallback = "Não foi possível concluir a operação"): string {
  return err instanceof RequestError ? err.message : fallback;
}

/** Mutação de administração: toast de sucesso/erro e invalidação das listas afetadas. */
export function useAdminMutation<TVars, TData>(
  fn: (vars: TVars) => Promise<TData>,
  opts: {
    success: string | ((vars: TVars, data: TData) => string);
    invalidate: (readonly string[])[];
    onSuccess?: (data: TData, vars: TVars) => void;
    onError?: (err: unknown) => void;
    /** false: não mostra o toast de erro (o formulário exibe a mensagem). */
    toastError?: boolean;
  },
) {
  return useMutation({
    mutationFn: fn,
    onSuccess: (data, vars) => {
      for (const queryKey of opts.invalidate) void queryClient.invalidateQueries({ queryKey });
      toast.success(typeof opts.success === "function" ? opts.success(vars, data) : opts.success);
      opts.onSuccess?.(data, vars);
    },
    onError: (err) => {
      if (opts.toastError !== false) toast.error(errorMessage(err));
      opts.onError?.(err);
    },
  });
}
