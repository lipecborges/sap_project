import type { PpFlag, PpSituation } from "@raiox/contracts";
import { isShort, type PpOrder, USER_STATUS_MAP } from "./orders";

/**
 * Implementação de referência das regras do catálogo (PP-03 "Situação resumida").
 * O add-on ABAP (ZCL_RX_PP_STATUS_MAP) deve produzir o mesmo resultado para os mesmos dados.
 * Datas em dias relativos a hoje (0 = hoje, negativo = passado).
 */

export interface Classification {
  situation: PpSituation;
  flags: PpFlag[];
  /** Dias de atraso no início (0 = no prazo). */
  startDelayDays: number;
  /** Dias de atraso no fim (0 = no prazo). */
  finishDelayDays: number;
}

export interface ClassifyOptions {
  toleranceDays?: number;
  /** Janela para considerar um estorno de apontamento "recente". */
  reversalWindowDays?: number;
}

const FINISHED: PpSituation[] = ["DELETED", "CLOSED", "TECHNICALLY_COMPLETED", "DELIVERED"];

export function userStatusRole(order: PpOrder, role: "APPROVED" | "BLOCKS_RELEASE"): boolean {
  return order.userStatus.some((u) => USER_STATUS_MAP[`${u.profile}/${u.code}`] === role);
}

export function situationOf(order: PpOrder): PpSituation {
  const has = (s: string) => order.systemStatus.includes(s);
  if (has("DLFL")) return "DELETED";
  if (has("CLSD")) return "CLOSED";
  if (has("TECO")) return "TECHNICALLY_COMPLETED";
  if (has("DLV")) return "DELIVERED";
  if (has("PDLV")) return "PARTIALLY_DELIVERED";
  if (has("CNF")) return "CONFIRMED";
  if (has("PCNF")) return "IN_PRODUCTION";
  if (has("REL") || has("PREL")) return "RELEASED";
  if (userStatusRole(order, "APPROVED")) return "APPROVED";
  return "CREATED";
}

export function classify(order: PpOrder, options: ClassifyOptions = {}): Classification {
  const tolerance = options.toleranceDays ?? 0;
  const reversalWindow = options.reversalWindowDays ?? 7;
  const has = (s: string) => order.systemStatus.includes(s);
  const situation = situationOf(order);
  const open = !FINISHED.includes(situation);
  const flags: PpFlag[] = [];

  const startDelayDays =
    open && order.actualStart === undefined && order.schedStart < -tolerance ? -order.schedStart : 0;
  const finishDelayDays = open && order.schedFinish < -tolerance ? -order.schedFinish : 0;

  if (startDelayDays > 0) flags.push("LATE_START");
  if (finishDelayDays > 0) flags.push("LATE_FINISH");
  if (open && order.operations.some((o) => !o.systemStatus.includes("CNF") && o.schedFinish < -tolerance)) {
    flags.push("OPERATION_LATE");
  }
  if (open && (has("MSPT") || order.components.some(isShort))) flags.push("MISSING_PARTS");
  if (has("LKD")) flags.push("LOCKED");
  // Só para ordens totalmente confirmadas: em PCNF é normal a entrada vir no fim.
  if (has("CNF") && !has("DLV") && order.delivered < order.confirmed) flags.push("CONFIRMED_NOT_RECEIVED");
  if (open && order.salesOrder) {
    const projectedFinish = Math.max(order.schedFinish, 0);
    if (projectedFinish > order.salesOrder.requestedDate) flags.push("SALES_ORDER_AT_RISK");
  }
  if (order.confirmations.some((c) => c.reversed && c.date >= -reversalWindow)) flags.push("REVERSED_CONFIRMATION");

  return { situation, flags, startDelayDays, finishDelayDays };
}
