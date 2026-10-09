import {
  type DiagnosticResult,
  type Finding,
  PP_FLAG_LABELS,
  PP_SITUATION_LABELS,
  type PpFlag,
  type ResultTable,
  stripLeadingZeros,
} from "@raiox/contracts";
import { day, emptyResult, formatQty, type MockContext, settleStatus } from "../context";
import { classify } from "../pp/classify";
import { findOrder, isShort, ORDERS, type PpOrder, USER_STATUS_MAP } from "../pp/orders";

const percent = (part: number, total: number) => (total === 0 ? "0%" : `${Math.round((part / total) * 100)}%`);

function orderNotFound(ctx: MockContext, diagnosticId: string, prefix: string, aufnr: string): DiagnosticResult {
  const result = emptyResult(ctx, diagnosticId, { kind: "PRODUCTION_ORDER", id: aufnr }, "NOT_FOUND");
  result.findings.push({
    code: `${prefix}.NOT_FOUND`,
    severity: "INFO",
    title: "Ordem não encontrada",
    detail: `A ordem de produção ${aufnr} não existe neste sistema/mandante.`,
    evidence: [{ source: "AUFK", field: "AUFNR", value: aufnr, label: "Ordem de produção" }],
  });
  return result;
}

function componentsTable(order: PpOrder): ResultTable {
  return {
    id: "components",
    title: "Componentes",
    columns: ["Material", "Descrição", "Necessário", "Retirado", "Pendente", "Estoque livre", "Falta?"],
    rows: order.components.map((c) => [
      c.material,
      c.text,
      formatQty(c.required, c.unit),
      formatQty(c.withdrawn, c.unit),
      formatQty(c.required - c.withdrawn, c.unit),
      formatQty(c.stock, c.unit),
      isShort(c) ? "Sim" : "Não",
    ]),
    truncated: false,
  };
}

function statusText(order: PpOrder): string {
  return order.systemStatus.join(" ");
}

// ---------------------------------------------------------------------------
// PP-01: Ordem não liberada / falta de componentes
// ---------------------------------------------------------------------------

export function pp01(ctx: MockContext, params: Record<string, string>): DiagnosticResult {
  const aufnr = stripLeadingZeros(params.productionOrder ?? "");
  const order = findOrder(aufnr);
  if (!order) return orderNotFound(ctx, "PP-01", "PP01", aufnr);

  const r = emptyResult(ctx, "PP-01", { kind: "PRODUCTION_ORDER", id: aufnr });
  const has = (s: string) => order.systemStatus.includes(s);
  const statusEvidence = { source: "JEST", field: "STAT", value: statusText(order), label: "Status de sistema ativos" };

  if (has("DLFL")) {
    r.findings.push({
      code: "PP01.DELETED",
      severity: "INFO",
      title: "Ordem marcada para eliminação",
      detail: "A ordem está marcada para eliminação (DLFL) e não pode ser liberada.",
      evidence: [statusEvidence],
    });
    return r;
  }
  if (has("TECO")) {
    r.findings.push({
      code: "PP01.TECO",
      severity: "INFO",
      title: "Ordem encerrada tecnicamente",
      detail: "A ordem já foi encerrada tecnicamente (TECO). Não há liberação pendente.",
      evidence: [statusEvidence],
      suggestedAction: { tcode: "CO03", description: "Exibir a ordem" },
    });
    return r;
  }

  const released = has("REL") || has("PREL");
  if (!released) {
    r.findings.push({
      code: "PP01.NOT_RELEASED",
      severity: "BLOCKING",
      title: "Ordem não liberada",
      detail: "A ordem está apenas criada (CRTD). Sem liberação não é possível apontar nem retirar material.",
      evidence: [statusEvidence],
      suggestedAction: { tcode: "CO02", description: "Liberar a ordem (Funções → Liberar)" },
    });
  }

  for (const u of order.userStatus) {
    if (USER_STATUS_MAP[`${u.profile}/${u.code}`] === "BLOCKS_RELEASE") {
      r.findings.push({
        code: "PP01.USER_STATUS_BLOCK",
        severity: "BLOCKING",
        title: "Status de usuário impede a liberação",
        detail: `O status de usuário "${u.text}" (perfil ${u.profile}) proíbe a liberação.`,
        evidence: [{ source: "JEST", field: "STAT", value: u.code, label: `Status de usuário: ${u.text}` }],
        suggestedAction: { tcode: "CO02", description: "Alterar o status de usuário (área responsável)" },
      });
    }
  }

  if (has("LKD")) {
    r.findings.push({
      code: "PP01.LOCKED",
      severity: "BLOCKING",
      title: "Ordem bloqueada",
      detail: "A ordem está bloqueada (LKD). Nenhuma operação de negócio é permitida até o desbloqueio.",
      evidence: [statusEvidence],
      suggestedAction: { tcode: "CO02", description: "Desbloquear a ordem (Funções → Bloquear → Desbloquear)" },
    });
  }

  const missing = order.components.filter(isShort);
  if (has("MSPT") || missing.length > 0) {
    r.findings.push({
      code: "PP01.MISSING_PARTS",
      severity: "BLOCKING",
      title: `Falta de material em ${missing.length} componente(s)`,
      detail: missing
        .map(
          (c) =>
            `${c.material} (${c.text}): precisa ${formatQty(c.required - c.withdrawn, c.unit)}, estoque ${formatQty(c.stock, c.unit)}`,
        )
        .join("; "),
      evidence: [
        statusEvidence,
        ...missing.map((c) => ({
          source: "RESB",
          field: "BDMNG",
          value: String(c.required),
          label: `Necessidade de ${c.material}`,
        })),
      ],
      suggestedAction: { tcode: "CO24", description: "Analisar a lista de faltas e o MD04 de cada componente" },
    });
  }

  if (!released && r.findings.length === 1) {
    r.findings.push({
      code: "PP01.MANUAL_RELEASE",
      severity: "INFO",
      title: "Nada impede a liberação",
      detail: "Não há falta de material nem bloqueios. A ordem só aguarda a liberação manual.",
      evidence: [],
      suggestedAction: { tcode: "COHV", description: "Liberar em massa, se houver várias ordens" },
    });
  }

  if (released && r.findings.length === 0) {
    r.findings.push({
      code: "PP01.RELEASED",
      severity: "INFO",
      title: "Ordem liberada e sem faltas",
      detail: "A ordem está liberada e todos os componentes estão disponíveis.",
      evidence: [statusEvidence],
    });
  }

  r.tables.push(componentsTable(order));
  return settleStatus(r);
}

// ---------------------------------------------------------------------------
// PP-03: Situação da ordem de produção
// ---------------------------------------------------------------------------

const PP03_FINDINGS: Record<PpFlag, (order: PpOrder, ctx: MockContext, c: ReturnType<typeof classify>) => Finding> = {
  LATE_START: (o, ctx, c) => ({
    code: "PP03.LATE_START",
    severity: "BLOCKING",
    title: `Início atrasado em ${c.startDelayDays} dia(s)`,
    detail: `O início programado era ${day(ctx, o.schedStart)} e a ordem ainda não começou.`,
    evidence: [{ source: "AFKO", field: "GSTRS", value: day(ctx, o.schedStart), label: "Início programado" }],
    suggestedAction: { tcode: "CO02", description: "Liberar ou reprogramar a ordem com o PCP" },
  }),
  LATE_FINISH: (o, ctx, c) => ({
    code: "PP03.LATE_FINISH",
    severity: "BLOCKING",
    title: `Fim atrasado em ${c.finishDelayDays} dia(s)`,
    detail: `O fim programado era ${day(ctx, o.schedFinish)}. Confirmado até agora: ${formatQty(o.confirmed, o.unit)} de ${formatQty(o.planned, o.unit)}.`,
    evidence: [{ source: "AFKO", field: "GLTRS", value: day(ctx, o.schedFinish), label: "Fim programado" }],
    suggestedAction: { tcode: "COOIS", description: "Ver as operações pendentes e o gargalo" },
  }),
  OPERATION_LATE: (o, ctx) => {
    const late = o.operations.filter((op) => !op.systemStatus.includes("CNF") && op.schedFinish < 0);
    return {
      code: "PP03.OPERATION_LATE",
      severity: "WARNING",
      title: `${late.length} operação(ões) atrasada(s)`,
      detail: late
        .map((op) => `${op.vornr} ${op.text} (${op.workCenter}), fim programado ${day(ctx, op.schedFinish)}`)
        .join("; "),
      evidence: late.map((op) => ({
        source: "AFVV",
        field: "FSEDD",
        value: day(ctx, op.schedFinish),
        label: `Fim programado da operação ${op.vornr}`,
      })),
      suggestedAction: { tcode: "CM01", description: "Verificar a carga do centro de trabalho" },
    };
  },
  MISSING_PARTS: () => ({
    code: "PP03.MISSING_PARTS",
    severity: "WARNING",
    title: "Falta de material",
    detail: "Há componentes com falta. Rode o diagnóstico PP-01 para o detalhe.",
    evidence: [{ source: "JEST", field: "STAT", value: "MSPT", label: "Status: falta de material" }],
    suggestedAction: { tcode: "CO24", description: "Lista de faltas" },
  }),
  LOCKED: () => ({
    code: "PP03.LOCKED",
    severity: "BLOCKING",
    title: "Ordem bloqueada",
    detail: "A ordem está bloqueada (LKD).",
    evidence: [{ source: "JEST", field: "STAT", value: "LKD", label: "Status: bloqueada" }],
    suggestedAction: { tcode: "CO02", description: "Desbloquear a ordem" },
  }),
  CONFIRMED_NOT_RECEIVED: (o) => ({
    code: "PP03.CONFIRMED_NOT_RECEIVED",
    severity: "WARNING",
    title: "Confirmada sem entrada de mercadoria",
    detail: `Foram confirmados ${formatQty(o.confirmed, o.unit)}, mas só ${formatQty(o.delivered, o.unit)} deram entrada no estoque.`,
    evidence: [{ source: "AFPO", field: "WEMNG", value: String(o.delivered), label: "Quantidade entregue" }],
    suggestedAction: { tcode: "MIGO", description: "Lançar a entrada de mercadoria da ordem (movimento 101)" },
  }),
  SALES_ORDER_AT_RISK: (o, ctx) => ({
    code: "PP03.SALES_ORDER_AT_RISK",
    severity: "WARNING",
    title: "Risco para o pedido do cliente",
    detail: `A ordem atende o pedido ${o.salesOrder?.vbeln}/${o.salesOrder?.posnr} (${o.salesOrder?.customer}), com data pedida ${day(ctx, o.salesOrder?.requestedDate ?? 0)}.`,
    evidence: [
      {
        source: "VBEP",
        field: "EDATU",
        value: day(ctx, o.salesOrder?.requestedDate ?? 0),
        label: "Data pedida pelo cliente",
      },
    ],
    suggestedAction: { tcode: "VA03", description: "Avisar a área comercial sobre o novo prazo" },
  }),
  REVERSED_CONFIRMATION: () => ({
    code: "PP03.REVERSED_CONFIRMATION",
    severity: "INFO",
    title: "Apontamento estornado recentemente",
    detail: "Houve estorno de apontamento nos últimos 7 dias.",
    evidence: [{ source: "AFRU", field: "STOKZ", value: "X", label: "Apontamento estornado" }],
    suggestedAction: { tcode: "CO14", description: "Exibir os apontamentos da ordem" },
  }),
};

export function pp03(ctx: MockContext, params: Record<string, string>): DiagnosticResult {
  const aufnr = stripLeadingZeros(params.productionOrder ?? "");
  const order = findOrder(aufnr);
  if (!order) return orderNotFound(ctx, "PP-03", "PP03", aufnr);

  const c = classify(order);
  const r = emptyResult(ctx, "PP-03", { kind: "PRODUCTION_ORDER", id: aufnr });
  const dateOrDash = (offset?: number) => (offset === undefined ? "—" : day(ctx, offset));

  r.facts.push(
    { id: "material", label: "Material", value: `${order.material} · ${order.description}` },
    { id: "plant", label: "Centro / tipo", value: `${order.plant} / ${order.orderType}` },
    {
      id: "mrpController",
      label: "Planejador MRP / responsável",
      value: `${order.mrpController} / ${order.scheduler}`,
    },
    { id: "situation", label: "Situação", value: PP_SITUATION_LABELS[c.situation] },
    { id: "flags", label: "Sinalizadores", value: c.flags.map((f) => PP_FLAG_LABELS[f]).join(", ") || "Nenhum" },
    { id: "systemStatus", label: "Status de sistema", value: statusText(order) },
    { id: "userStatus", label: "Status de usuário", value: order.userStatus.map((u) => u.text).join(", ") || "—" },
    { id: "planned", label: "Quantidade planejada", value: formatQty(order.planned, order.unit) },
    {
      id: "confirmed",
      label: "Confirmada (apontada)",
      value: `${formatQty(order.confirmed, order.unit)} (${percent(order.confirmed, order.planned)})`,
    },
    { id: "scrap", label: "Refugo", value: formatQty(order.scrap, order.unit) },
    {
      id: "delivered",
      label: "Entregue no estoque",
      value: `${formatQty(order.delivered, order.unit)} (${percent(order.delivered, order.planned)})`,
    },
    { id: "basicDates", label: "Datas base", value: `${day(ctx, order.basicStart)} → ${day(ctx, order.basicFinish)}` },
    {
      id: "scheduledDates",
      label: "Datas programadas",
      value: `${day(ctx, order.schedStart)} → ${day(ctx, order.schedFinish)}`,
    },
    {
      id: "actualDates",
      label: "Datas reais",
      value: `${dateOrDash(order.actualStart)} → ${dateOrDash(order.actualFinish)}`,
    },
    {
      id: "delay",
      label: "Atraso",
      value:
        c.startDelayDays === 0 && c.finishDelayDays === 0
          ? "No prazo"
          : `Início: ${c.startDelayDays} dia(s) · Fim: ${c.finishDelayDays} dia(s)`,
    },
  );
  if (order.salesOrder) {
    r.facts.push({
      id: "salesOrder",
      label: "Pedido de venda",
      value: `${order.salesOrder.vbeln}/${order.salesOrder.posnr} · ${order.salesOrder.customer} · pedido para ${day(ctx, order.salesOrder.requestedDate)}`,
    });
    r.related.push({ kind: "SALES_ORDER", id: order.salesOrder.vbeln });
  }

  r.tables.push(
    {
      id: "operations",
      title: "Operações",
      columns: [
        "Operação",
        "Centro de trabalho",
        "Descrição",
        "Status",
        "Fim programado",
        "Fim real",
        "Confirmado",
        "Refugo",
      ],
      rows: order.operations.map((op) => [
        op.vornr,
        op.workCenter,
        op.text,
        op.systemStatus.join(" "),
        day(ctx, op.schedFinish),
        dateOrDash(op.actualFinish),
        formatQty(op.confirmed, order.unit),
        formatQty(op.scrap, order.unit),
      ]),
      truncated: false,
    },
    componentsTable(order),
    {
      id: "confirmations",
      title: "Últimos apontamentos",
      columns: ["Data", "Operação", "Qtd. boa", "Refugo", "Usuário", "Estornado?"],
      rows: order.confirmations.map((cf) => [
        day(ctx, cf.date),
        cf.vornr,
        formatQty(cf.yield, order.unit),
        formatQty(cf.scrap, order.unit),
        cf.user,
        cf.reversed ? "Sim" : "Não",
      ]),
      truncated: false,
    },
  );

  for (const flag of c.flags) r.findings.push(PP03_FINDINGS[flag](order, ctx, c));
  return settleStatus(r);
}

// ---------------------------------------------------------------------------
// PP-04: Lista de ordens por situação
// ---------------------------------------------------------------------------

const MAX_ROWS = 500;
const DEFAULT_ROWS = 100;

export function pp04(ctx: MockContext, params: Record<string, string>): DiagnosticResult {
  const plant = params.plant ?? "";
  const r = emptyResult(ctx, "PP-04", { kind: "PLANT", id: plant });
  const inPlant = ORDERS.filter((o) => o.plant === plant);
  if (inPlant.length === 0) {
    r.status = "NOT_FOUND";
    r.findings.push({
      code: "PP04.NO_ORDERS",
      severity: "INFO",
      title: "Nenhuma ordem no centro",
      detail: `Não há ordens de produção no centro ${plant}.`,
      evidence: [{ source: "AUFK", field: "WERKS", value: plant, label: "Centro" }],
    });
    return r;
  }

  const toOffset = (iso?: string) => {
    if (!iso) return undefined;
    const today = Date.UTC(ctx.today.getUTCFullYear(), ctx.today.getUTCMonth(), ctx.today.getUTCDate());
    return Math.round((Date.parse(`${iso}T00:00:00Z`) - today) / 86_400_000);
  };
  const from = toOffset(params.dateFrom);
  const to = toOffset(params.dateTo);

  const classified = inPlant
    .map((order) => ({ order, c: classify(order) }))
    .filter(({ order, c }) => {
      if (params.situation && c.situation !== params.situation && !c.flags.includes(params.situation as PpFlag))
        return false;
      if (params.mrpController && order.mrpController !== params.mrpController) return false;
      if (params.orderType && order.orderType !== params.orderType) return false;
      if (params.material && order.material !== params.material) return false;
      if (from !== undefined && order.schedFinish < from) return false;
      if (to !== undefined && order.schedFinish > to) return false;
      return true;
    })
    .sort((a, b) => b.c.finishDelayDays - a.c.finishDelayDays || b.c.startDelayDays - a.c.startDelayDays);

  const maxRows = Math.min(Number(params.maxRows) || DEFAULT_ROWS, MAX_ROWS);
  const page = Math.max(Number(params.page) || 1, 1);
  const pageRows = classified.slice((page - 1) * maxRows, page * maxRows);

  const countBy = new Map<string, number>();
  for (const { c } of classified) {
    countBy.set(PP_SITUATION_LABELS[c.situation], (countBy.get(PP_SITUATION_LABELS[c.situation]) ?? 0) + 1);
    for (const f of c.flags) countBy.set(PP_FLAG_LABELS[f], (countBy.get(PP_FLAG_LABELS[f]) ?? 0) + 1);
  }
  r.facts.push({ id: "total", label: "Ordens encontradas", value: String(classified.length) });
  for (const [label, count] of countBy) r.facts.push({ id: `count:${label}`, label, value: String(count) });

  r.tables.push({
    id: "orders",
    title: "Ordens de produção",
    columns: [
      "Ordem",
      "Material",
      "Descrição",
      "Planejada",
      "Confirmada",
      "Entregue",
      "Situação",
      "Sinalizadores",
      "Fim programado",
      "Dias de atraso",
      "Pedido de venda",
    ],
    rows: pageRows.map(({ order, c }) => [
      order.aufnr,
      order.material,
      order.description,
      formatQty(order.planned, order.unit),
      formatQty(order.confirmed, order.unit),
      formatQty(order.delivered, order.unit),
      PP_SITUATION_LABELS[c.situation],
      c.flags.map((f) => PP_FLAG_LABELS[f]).join(", "),
      day(ctx, order.schedFinish),
      String(c.finishDelayDays),
      order.salesOrder ? `${order.salesOrder.vbeln}/${order.salesOrder.posnr}` : "",
    ]),
    truncated: page * maxRows < classified.length,
  });

  const late = classified.filter(({ c }) => c.flags.includes("LATE_START") || c.flags.includes("LATE_FINISH"));
  if (late.length > 0) {
    r.findings.push({
      code: "PP04.LATE_ORDERS",
      severity: "WARNING",
      title: `${late.length} ordem(ns) atrasada(s)`,
      detail: `Ordens atrasadas: ${late.map(({ order }) => order.aufnr).join(", ")}. Use o PP-03 para ver cada uma.`,
      evidence: [],
      suggestedAction: { tcode: "COOIS", description: "Sistema de informação de ordens" },
    });
  }
  const missing = classified.filter(({ c }) => c.flags.includes("MISSING_PARTS"));
  if (missing.length > 0) {
    r.findings.push({
      code: "PP04.MISSING_PARTS",
      severity: "WARNING",
      title: `${missing.length} ordem(ns) com falta de material`,
      detail: `Ordens: ${missing.map(({ order }) => order.aufnr).join(", ")}. Use o PP-01 para o detalhe.`,
      evidence: [],
      suggestedAction: { tcode: "CO24", description: "Lista de faltas" },
    });
  }
  return settleStatus(r);
}
