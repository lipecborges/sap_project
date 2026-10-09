import { createRootRouteWithContext, createRoute, createRouter, Outlet, redirect } from "@tanstack/react-router";
import { z } from "zod";
import { AppShell } from "./layouts/AppShell";
import type { useAuth } from "./lib/auth";
import { AssistantPage } from "./pages/AssistantPage";
import { AdminLayout } from "./pages/admin/AdminLayout";
import { AuditPage } from "./pages/admin/AuditPage";
import { ConnectorsPage } from "./pages/admin/ConnectorsPage";
import { LicensePage } from "./pages/admin/LicensePage";
import { SystemsPage } from "./pages/admin/SystemsPage";
import { UsagePage } from "./pages/admin/UsagePage";
import { UsersPage } from "./pages/admin/UsersPage";
import { DiagnosticRunPage, DiagnosticsPage } from "./pages/DiagnosticsPages";
import { HomePage } from "./pages/HomePage";
import { LoginPage } from "./pages/LoginPage";
import { NotFoundPage } from "./pages/NotFoundPage";
import { ProductionListPage, ProductionOrderPage } from "./pages/ProductionPages";
import { InvoicePage, InvoicesListPage } from "./pages/PurchasingPages";
import { SalesListPage, SalesOrderPage } from "./pages/SalesPages";

interface RouterContext {
  auth: ReturnType<typeof useAuth>;
}

const rootRoute = createRootRouteWithContext<RouterContext>()({
  component: Outlet,
  notFoundComponent: NotFoundPage,
});

const loginRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/login",
  validateSearch: z.object({ redirect: z.string().optional() }),
  beforeLoad: ({ context, search }) => {
    if (context.auth.status === "authenticated")
      throw redirect({ to: search.redirect?.startsWith("/") ? search.redirect : "/" });
  },
  component: function Login() {
    const { redirect: to } = loginRoute.useSearch();
    return <LoginPage redirect={to} />;
  },
});

const appRoute = createRoute({
  getParentRoute: () => rootRoute,
  id: "app",
  beforeLoad: ({ context, location }) => {
    if (context.auth.status !== "authenticated") throw redirect({ to: "/login", search: { redirect: location.href } });
  },
  component: AppShell,
});

const filterSearch = z.object({ filtro: z.string().optional() });

const homeRoute = createRoute({ getParentRoute: () => appRoute, path: "/", component: HomePage });

const assistantRoute = createRoute({
  getParentRoute: () => appRoute,
  path: "/assistente",
  validateSearch: z.object({ q: z.string().optional() }),
  component: function Assistant() {
    const { q } = assistantRoute.useSearch();
    return <AssistantPage q={q} />;
  },
});

const productionRoute = createRoute({
  getParentRoute: () => appRoute,
  path: "/producao",
  validateSearch: filterSearch,
  component: function Production() {
    const { filtro } = productionRoute.useSearch();
    return <ProductionListPage filter={filtro} />;
  },
});

const orderRoute = createRoute({
  getParentRoute: () => appRoute,
  path: "/producao/ordens/$orderId",
  component: function Order() {
    const { orderId } = orderRoute.useParams();
    return <ProductionOrderPage key={orderId} orderId={orderId} />;
  },
});

const salesRoute = createRoute({
  getParentRoute: () => appRoute,
  path: "/vendas",
  validateSearch: filterSearch,
  component: function Sales() {
    const { filtro } = salesRoute.useSearch();
    return <SalesListPage filter={filtro} />;
  },
});

const salesOrderRoute = createRoute({
  getParentRoute: () => appRoute,
  path: "/vendas/pedidos/$salesOrder",
  component: function SalesOrder() {
    const { salesOrder } = salesOrderRoute.useParams();
    return <SalesOrderPage key={salesOrder} salesOrder={salesOrder} />;
  },
});

const purchasingRoute = createRoute({
  getParentRoute: () => appRoute,
  path: "/compras",
  validateSearch: filterSearch,
  component: function Purchasing() {
    const { filtro } = purchasingRoute.useSearch();
    return <InvoicesListPage filter={filtro} />;
  },
});

const invoiceRoute = createRoute({
  getParentRoute: () => appRoute,
  path: "/compras/faturas/$invoice/$year",
  component: function Invoice() {
    const { invoice, year } = invoiceRoute.useParams();
    return <InvoicePage key={`${invoice}-${year}`} invoice={invoice} year={year} />;
  },
});

const diagnosticsRoute = createRoute({
  getParentRoute: () => appRoute,
  path: "/diagnosticos",
  component: DiagnosticsPage,
});

const diagnosticRunRoute = createRoute({
  getParentRoute: () => appRoute,
  path: "/diagnosticos/$diagnosticId",
  component: function Run() {
    const { diagnosticId } = diagnosticRunRoute.useParams();
    return <DiagnosticRunPage key={diagnosticId} diagnosticId={diagnosticId} />;
  },
});

/** Área de administração: só para o papel "admin"; os demais voltam ao início. */
const adminRoute = createRoute({
  getParentRoute: () => appRoute,
  path: "/admin",
  beforeLoad: ({ context }) => {
    if (!context.auth.isAdmin) throw redirect({ to: "/" });
  },
  component: AdminLayout,
});
const adminIndexRoute = createRoute({
  getParentRoute: () => adminRoute,
  path: "/",
  beforeLoad: () => {
    throw redirect({ to: "/admin/usuarios" });
  },
});
const adminPages = [
  ["usuarios", UsersPage],
  ["licenca", LicensePage],
  ["sistemas", SystemsPage],
  ["conectores", ConnectorsPage],
  ["auditoria", AuditPage],
  ["uso", UsagePage],
] as const;
const adminChildren = adminPages.map(([path, component]) =>
  createRoute({ getParentRoute: () => adminRoute, path, component }),
);

const routeTree = rootRoute.addChildren([
  loginRoute,
  appRoute.addChildren([
    homeRoute,
    assistantRoute,
    productionRoute,
    orderRoute,
    salesRoute,
    salesOrderRoute,
    purchasingRoute,
    invoiceRoute,
    diagnosticsRoute,
    diagnosticRunRoute,
    adminRoute.addChildren([adminIndexRoute, ...adminChildren]),
  ]),
]);

export const router = createRouter({
  routeTree,
  context: { auth: undefined as unknown as RouterContext["auth"] },
  defaultPreload: false,
  scrollRestoration: true,
});

declare module "@tanstack/react-router" {
  interface Register {
    router: typeof router;
  }
}
