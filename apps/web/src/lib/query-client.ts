import { QueryClient } from "@tanstack/react-query";

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: (count, error) =>
        count < 1 && (error as { status?: number }).status !== 403 && (error as { status?: number }).status !== 401,
      refetchOnWindowFocus: false,
    },
  },
});

export const CONVERSATIONS_KEY = ["conversations"] as const;
