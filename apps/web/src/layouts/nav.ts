import {
  Cable,
  Factory,
  KeyRound,
  LayoutDashboard,
  type LucideIcon,
  Receipt,
  ScrollText,
  Server,
  ShieldCheck,
  ShoppingCart,
  Sparkles,
  Stethoscope,
  TrendingUp,
  Users,
} from "lucide-react";

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

/** Entrada única "Administração" no menu; as subpáginas aparecem dentro dela. */
export const ADMIN_ROOT: NavItem = { to: "/admin", label: "Administração", icon: ShieldCheck };

export const ADMIN_NAV: NavItem[] = [
  { to: "/admin/usuarios", label: "Usuários", icon: Users },
  { to: "/admin/licenca", label: "Licença", icon: KeyRound },
  { to: "/admin/sistemas", label: "Sistemas SAP", icon: Server },
  { to: "/admin/conectores", label: "Conectores", icon: Cable },
  { to: "/admin/auditoria", label: "Auditoria", icon: ScrollText },
  { to: "/admin/uso", label: "Uso", icon: TrendingUp },
];

export interface NavSections {
  main: NavItem[];
  process: NavItem[];
  tools: NavItem[];
  /** Vazio para quem não é administrador. */
  admin: NavItem[];
}

/** Itens de menu visíveis conforme as autorizações SAP (diagnósticos) e o papel no Raio-X. */
export function navSections(user: { diagnostics: string[]; role: "user" | "admin" }): NavSections {
  const allowed = (n: NavItem) => !n.requires || user.diagnostics.includes(n.requires);
  return {
    main: MAIN_NAV.filter(allowed),
    process: PROCESS_NAV.filter(allowed),
    tools: TOOLS_NAV.filter(allowed),
    admin: user.role === "admin" ? ADMIN_NAV : [],
  };
}

export function isActivePath(pathname: string, to: string): boolean {
  return to === "/" ? pathname === "/" : pathname === to || pathname.startsWith(`${to}/`);
}
