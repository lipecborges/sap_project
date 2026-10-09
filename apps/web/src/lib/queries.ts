import { useQuery } from "@tanstack/react-query";
import { api } from "./api";
import { useSession } from "./auth";

export function useOverview(plant?: string) {
  const { me } = useSession();
  return useQuery({
    queryKey: ["overview", me.user, plant ?? ""],
    queryFn: () => api.overview(plant),
    staleTime: 60_000,
  });
}

export function useDiagnostic(id: string, params: Record<string, string>, enabled = true) {
  const { me } = useSession();
  return useQuery({
    queryKey: ["diagnostic", me.user, id, params],
    queryFn: () => api.run(id, params),
    enabled: enabled && me.diagnostics.includes(id),
    staleTime: 30_000,
  });
}
