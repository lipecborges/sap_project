import {
  INVOICE_STATE_LABELS,
  PP_FLAG_LABELS,
  PP_SITUATION_LABELS,
  type PpFlag,
  type PpSituation,
  type ResultStatus,
  SD_STAGE_LABELS,
  type Severity,
} from "@raiox/contracts";
import {
  AlertOctagon,
  AlertTriangle,
  CheckCircle2,
  Clock,
  Info,
  Lock,
  PackageX,
  RotateCcw,
  Truck,
  UserRound,
} from "lucide-react";
import type { ComponentType } from "react";
import { Badge, type Tone } from "../ui/badge";

export const SEVERITY: Record<Severity, { label: string; tone: Tone; icon: ComponentType<{ className?: string }> }> = {
  BLOCKING: { label: "Bloqueio", tone: "critical", icon: AlertOctagon },
  WARNING: { label: "Atenção", tone: "warning", icon: AlertTriangle },
  INFO: { label: "Informação", tone: "info", icon: Info },
};

export const SEVERITY_ORDER: Record<Severity, number> = { BLOCKING: 0, WARNING: 1, INFO: 2 };

const SITUATION_TONE: Record<PpSituation, Tone> = {
  DELETED: "neutral",
  CLOSED: "neutral",
  TECHNICALLY_COMPLETED: "neutral",
  DELIVERED: "good",
  PARTIALLY_DELIVERED: "good",
  CONFIRMED: "brand",
  IN_PRODUCTION: "brand",
  RELEASED: "info",
  APPROVED: "info",
  CREATED: "neutral",
};

export function SituationBadge({ code }: { code: string }) {
  const situation = code as PpSituation;
  return <Badge tone={SITUATION_TONE[situation] ?? "neutral"}>{PP_SITUATION_LABELS[situation] ?? code}</Badge>;
}

export const FLAG_META: Record<PpFlag, { tone: Tone; icon: ComponentType<{ className?: string }> }> = {
  LATE_START: { tone: "critical", icon: Clock },
  LATE_FINISH: { tone: "critical", icon: Clock },
  OPERATION_LATE: { tone: "warning", icon: Clock },
  MISSING_PARTS: { tone: "serious", icon: PackageX },
  LOCKED: { tone: "critical", icon: Lock },
  CONFIRMED_NOT_RECEIVED: { tone: "warning", icon: Truck },
  SALES_ORDER_AT_RISK: { tone: "warning", icon: UserRound },
  REVERSED_CONFIRMATION: { tone: "neutral", icon: RotateCcw },
};

export function FlagBadge({ code, compact = false }: { code: string; compact?: boolean }) {
  const flag = code as PpFlag;
  const meta = FLAG_META[flag];
  if (!meta) return null;
  const Icon = meta.icon;
  return (
    <Badge tone={meta.tone} title={PP_FLAG_LABELS[flag]}>
      <Icon />
      {compact ? null : PP_FLAG_LABELS[flag]}
    </Badge>
  );
}

const PP_LABEL_TO_CODE = Object.fromEntries(Object.entries(PP_SITUATION_LABELS).map(([k, v]) => [v, k]));
const FLAG_LABEL_TO_CODE = Object.fromEntries(Object.entries(PP_FLAG_LABELS).map(([k, v]) => [v, k]));

/** O PP-03 traz rótulos nos fatos; converte de volta para os códigos. */
export function situationCodeFromLabel(label?: string): string | undefined {
  return label ? PP_LABEL_TO_CODE[label] : undefined;
}
export function flagCodesFromLabels(labels?: string): string[] {
  if (!labels || labels === "Nenhum") return [];
  return labels
    .split(",")
    .map((l) => FLAG_LABEL_TO_CODE[l.trim()])
    .filter((c): c is string => Boolean(c));
}

const STAGE_TONE: Record<string, Tone> = {
  CREDIT: "critical",
  DELIVERY: "warning",
  GOODS_ISSUE: "serious",
  BILLING: "warning",
};
export function StageBadge({ code }: { code: string }) {
  return (
    <Badge tone={STAGE_TONE[code] ?? "neutral"}>{SD_STAGE_LABELS[code as keyof typeof SD_STAGE_LABELS] ?? code}</Badge>
  );
}

export function InvoiceStateBadge({ code }: { code: string }) {
  return (
    <Badge tone={code === "BLOCKED" ? "critical" : "warning"}>
      {INVOICE_STATE_LABELS[code as keyof typeof INVOICE_STATE_LABELS] ?? code}
    </Badge>
  );
}

const STATUS: Record<ResultStatus, { label: string; tone: Tone; icon: ComponentType<{ className?: string }> }> = {
  OK: { label: "Sem impedimentos", tone: "good", icon: CheckCircle2 },
  PROBLEM_FOUND: { label: "Requer ação", tone: "critical", icon: AlertOctagon },
  NOT_FOUND: { label: "Não encontrado", tone: "neutral", icon: Info },
  ERROR: { label: "Erro", tone: "critical", icon: AlertTriangle },
};

export function ResultStatusBadge({ status }: { status: ResultStatus }) {
  const meta = STATUS[status];
  const Icon = meta.icon;
  return (
    <Badge tone={meta.tone}>
      <Icon /> {meta.label}
    </Badge>
  );
}
