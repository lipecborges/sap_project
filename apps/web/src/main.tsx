import "@fontsource-variable/inter";
import "./index.css";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { RouterProvider } from "@tanstack/react-router";
import { StrictMode, useEffect } from "react";
import { createRoot } from "react-dom/client";
import { Toaster } from "sonner";
import { AuthProvider, useAuth } from "./lib/auth";
import { applyTheme } from "./lib/theme";
import { router } from "./router";

applyTheme();

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: (count, error) =>
        count < 1 && (error as { status?: number }).status !== 403 && (error as { status?: number }).status !== 401,
      refetchOnWindowFocus: false,
    },
  },
});

function Splash() {
  return (
    <div className="flex h-full items-center justify-center">
      <div className="flex size-10 animate-pulse items-center justify-center rounded-xl bg-gradient-to-br from-brand-500 to-brand-700 text-sm font-bold text-white">
        RX
      </div>
    </div>
  );
}

function App() {
  const auth = useAuth();
  useEffect(() => {
    // Ao entrar ou sair, reavalia as rotas protegidas; ao sair, limpa os dados em cache.
    if (auth.status === "anonymous") queryClient.clear();
    if (auth.status !== "loading") void router.invalidate();
  }, [auth.status]);
  if (auth.status === "loading") return <Splash />;
  return <RouterProvider router={router} context={{ auth }} />;
}

const root = document.getElementById("root");
if (!root) throw new Error("Elemento #root não encontrado");

createRoot(root).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <App />
        <Toaster position="bottom-right" richColors closeButton />
      </AuthProvider>
    </QueryClientProvider>
  </StrictMode>,
);
