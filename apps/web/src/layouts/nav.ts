import { Factory, LayoutDashboard, type LucideIcon, Receipt, ShoppingCart, Sparkles, Stethoscope } from "lucide-react";

export interface NavItem {
  to: string;
  label: string;
  icon: LucideIcon;
  /** Diagnóstico necessário para mostrar o item. */
  requires?: string;
}

export const MAIN_NAV: NavItem[] = [
  { to: "/", label: "Início", icon: LayoutDashboard },
  { to: "/assistente", label: "Assistente", icon: Sparkles },
];

export const PROCESS_NAV: NavItem[] = [
  { to: "/producao", label: "Produção", icon: Factory, requires: "PP-04" },
  { to: "/vendas", label: "Vendas", icon: ShoppingCart, requires: "SD-10" },
  { to: "/compras", label: "Compras", icon: Receipt, requires: "MM-10" },
];

export const TOOLS_NAV: NavItem[] = [{ to: "/diagnosticos", label: "Diagnósticos", icon: Stethoscope }];
