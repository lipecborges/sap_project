/**
 * Base de ordens de produção do simulador, usada por PP-01, PP-03 e PP-04.
 * As datas são deslocamentos em dias a partir de "hoje", para que os
 * cenários (atrasada, no prazo…) continuem válidos com o passar do tempo.
 */

export interface UserStatus {
  profile: string;
  code: string;
  text: string;
}

export interface PpOperation {
  vornr: string;
  workCenter: string;
  text: string;
  systemStatus: string[];
  schedStart: number;
  schedFinish: number;
  actualStart?: number;
  actualFinish?: number;
  confirmed: number;
  scrap: number;
}

export interface PpComponent {
  material: string;
  text: string;
  unit: string;
  required: number;
  withdrawn: number;
  /** Estoque de utilização livre no depósito de produção. */
  stock: number;
  /** Equivalente ao indicador de falta na reserva (RESB-XFEHL, a validar). */
  missing: boolean;
}

export interface PpConfirmation {
  date: number;
  vornr: string;
  yield: number;
  scrap: number;
  user: string;
  reversed: boolean;
}

export interface PpOrder {
  aufnr: string;
  material: string;
  description: string;
  plant: string;
  orderType: string;
  mrpController: string;
  scheduler: string;
  unit: string;
  /** Status de sistema ativos (abreviação EN da TJ02T). */
  systemStatus: string[];
  userStatus: UserStatus[];
  planned: number;
  confirmed: number;
  scrap: number;
  delivered: number;
  basicStart: number;
  basicFinish: number;
  schedStart: number;
  schedFinish: number;
  actualStart?: number;
  actualFinish?: number;
  salesOrder?: { vbeln: string; posnr: string; requestedDate: number; customer: string };
  operations: PpOperation[];
  components: PpComponent[];
  confirmations: PpConfirmation[];
}

/**
 * Mapeamento de status de usuário → situação/bloqueio (equivalente à ZRX_PP_STATUS_MAP).
 * A fonte real do "Aprovada" ainda será definida (catálogo, V07).
 */
export const USER_STATUS_MAP: Record<string, "APPROVED" | "BLOCKS_RELEASE"> = {
  "ZPP00001/E0002": "APPROVED",
  "ZPP00001/E0003": "BLOCKS_RELEASE",
};

const comp = (
  material: string,
  text: string,
  required: number,
  withdrawn: number,
  stock: number,
  missing = false,
): PpComponent => ({
  material,
  text,
  unit: "PC",
  required,
  withdrawn,
  stock,
  missing,
});

const op = (
  vornr: string,
  workCenter: string,
  text: string,
  systemStatus: string[],
  schedStart: number,
  schedFinish: number,
  confirmed = 0,
  extra: Partial<PpOperation> = {},
): PpOperation => ({ vornr, workCenter, text, systemStatus, schedStart, schedFinish, confirmed, scrap: 0, ...extra });

const base = {
  plant: "1000",
  orderType: "PP01",
  mrpController: "001",
  scheduler: "101",
  unit: "PC",
  userStatus: [] as UserStatus[],
  scrap: 0,
  confirmations: [] as PpConfirmation[],
};

export const ORDERS: PpOrder[] = [
  {
    ...base,
    aufnr: "1000001",
    material: "FG-1001",
    description: "Bomba centrífuga BC-200",
    systemStatus: ["CRTD", "MSPT", "PRC"],
    planned: 500,
    confirmed: 0,
    delivered: 0,
    basicStart: -2,
    basicFinish: 5,
    schedStart: -2,
    schedFinish: 5,
    operations: [
      op("0010", "MONT01", "Montagem do conjunto", ["CRTD"], -2, 2),
      op("0020", "TEST01", "Teste hidrostático", ["CRTD"], 2, 5),
    ],
    components: [
      comp("RM-2001", "Carcaça fundida BC-200", 500, 0, 120, true),
      comp("RM-2002", "Rotor inox 200 mm", 500, 0, 600),
      comp("RM-2003", 'Selo mecânico 1 1/2"', 500, 0, 0, true),
    ],
  },
  {
    ...base,
    aufnr: "1000002",
    material: "FG-1002",
    description: "Bomba centrífuga BC-300",
    systemStatus: ["CRTD", "PRC"],
    userStatus: [{ profile: "ZPP00001", code: "E0003", text: "BLQQ - Bloqueio da qualidade" }],
    planned: 200,
    confirmed: 0,
    delivered: 0,
    basicStart: 1,
    basicFinish: 6,
    schedStart: 1,
    schedFinish: 6,
    operations: [op("0010", "MONT01", "Montagem do conjunto", ["CRTD"], 1, 6)],
    components: [comp("RM-2101", "Carcaça fundida BC-300", 200, 0, 400)],
  },
  {
    ...base,
    aufnr: "1000003",
    material: "FG-1003",
    description: "Válvula gaveta VG-50",
    systemStatus: ["REL", "PRC", "MACM"],
    planned: 1000,
    confirmed: 0,
    delivered: 0,
    basicStart: 1,
    basicFinish: 8,
    schedStart: 1,
    schedFinish: 8,
    operations: [op("0010", "USIN01", "Usinagem do corpo", ["REL"], 1, 8)],
    components: [comp("RM-2201", "Corpo forjado VG-50", 1000, 0, 2500)],
  },
  {
    ...base,
    aufnr: "1000004",
    material: "FG-1004",
    description: "Válvula esfera VE-25",
    systemStatus: ["REL", "LKD", "PRC"],
    planned: 300,
    confirmed: 0,
    delivered: 0,
    basicStart: 0,
    basicFinish: 4,
    schedStart: 0,
    schedFinish: 4,
    operations: [op("0010", "USIN01", "Usinagem da esfera", ["REL"], 0, 4)],
    components: [comp("RM-2301", "Esfera inox 25 mm", 300, 0, 900)],
  },
  {
    ...base,
    aufnr: "1000005",
    material: "FG-1005",
    description: "Filtro Y FY-80",
    systemStatus: ["TECO", "PCNF", "PDLV", "PRC"],
    planned: 400,
    confirmed: 380,
    delivered: 380,
    basicStart: -30,
    basicFinish: -20,
    schedStart: -30,
    schedFinish: -20,
    actualStart: -30,
    actualFinish: -19,
    operations: [
      op("0010", "MONT02", "Montagem do filtro", ["CNF"], -30, -20, 380, { actualStart: -30, actualFinish: -19 }),
    ],
    components: [comp("RM-2401", "Corpo fundido FY-80", 400, 380, 50)],
  },
  {
    ...base,
    aufnr: "1000006",
    material: "FG-1006",
    description: "Bomba submersa BS-10",
    systemStatus: ["CRTD", "PRC"],
    userStatus: [{ profile: "ZPP00001", code: "E0002", text: "APRV - Aprovada" }],
    planned: 150,
    confirmed: 0,
    delivered: 0,
    basicStart: 3,
    basicFinish: 10,
    schedStart: 3,
    schedFinish: 10,
    operations: [op("0010", "MONT01", "Montagem da bomba", ["CRTD"], 3, 10)],
    components: [comp("RM-2501", "Motor 1 cv blindado", 150, 0, 300)],
  },
  {
    ...base,
    aufnr: "1000010",
    material: "FG-1010",
    description: "Conjunto motobomba MB-500",
    orderType: "PP02",
    systemStatus: ["REL", "PCNF", "PRC", "GMPS"],
    planned: 1000,
    confirmed: 600,
    scrap: 12,
    delivered: 0,
    basicStart: -12,
    basicFinish: -3,
    schedStart: -12,
    schedFinish: -3,
    actualStart: -12,
    salesOrder: { vbeln: "4500020", posnr: "10", requestedDate: -1, customer: "100777 · Saneamento Litoral S.A." },
    operations: [
      op("0010", "MONT01", "Montagem do conjunto", ["CNF"], -12, -7, 1000, { actualStart: -12, actualFinish: -6 }),
      op("0020", "PINT02", "Pintura eletrostática", ["PCNF"], -7, -4, 600, { actualStart: -6, scrap: 12 }),
      op("0030", "TEST01", "Teste de desempenho", ["REL"], -4, -3, 0),
    ],
    components: [
      comp("RM-3001", "Motor 5 cv", 1000, 1000, 40),
      comp("RM-3002", "Bomba BC-500", 1000, 1000, 15),
      comp("RM-3003", "Tinta epóxi azul (L)", 250, 160, 30),
    ],
    confirmations: [
      { date: -6, vornr: "0010", yield: 1000, scrap: 0, user: "OPERADOR1", reversed: false },
      { date: -3, vornr: "0020", yield: 350, scrap: 12, user: "OPERADOR2", reversed: false },
      { date: -1, vornr: "0020", yield: 250, scrap: 0, user: "OPERADOR2", reversed: false },
    ],
  },
  {
    ...base,
    aufnr: "1000011",
    material: "FG-1011",
    description: "Bomba centrífuga BC-200",
    systemStatus: ["REL", "CNF", "DLV", "PRC", "GMPS"],
    planned: 300,
    confirmed: 300,
    delivered: 300,
    basicStart: -15,
    basicFinish: -8,
    schedStart: -15,
    schedFinish: -8,
    actualStart: -15,
    actualFinish: -9,
    operations: [
      op("0010", "MONT01", "Montagem do conjunto", ["CNF"], -15, -8, 300, { actualStart: -15, actualFinish: -9 }),
    ],
    components: [comp("RM-2001", "Carcaça fundida BC-200", 300, 300, 120)],
    confirmations: [{ date: -9, vornr: "0010", yield: 300, scrap: 0, user: "OPERADOR1", reversed: false }],
  },
  {
    ...base,
    aufnr: "1000012",
    material: "FG-1012",
    description: "Válvula gaveta VG-80",
    systemStatus: ["REL", "CNF", "PRC"],
    planned: 250,
    confirmed: 250,
    delivered: 0,
    basicStart: -6,
    basicFinish: -1,
    schedStart: -6,
    schedFinish: -1,
    actualStart: -6,
    operations: [
      op("0010", "USIN01", "Usinagem do corpo", ["CNF"], -6, -1, 250, { actualStart: -6, actualFinish: -1 }),
    ],
    components: [comp("RM-2202", "Corpo forjado VG-80", 250, 250, 10)],
    confirmations: [{ date: -1, vornr: "0010", yield: 250, scrap: 0, user: "OPERADOR3", reversed: false }],
  },
  {
    ...base,
    aufnr: "1000013",
    material: "FG-1013",
    description: "Filtro cesto FC-100",
    mrpController: "002",
    systemStatus: ["REL", "PCNF", "PRC"],
    planned: 120,
    confirmed: 40,
    delivered: 0,
    basicStart: -4,
    basicFinish: 3,
    schedStart: -4,
    schedFinish: 3,
    actualStart: -4,
    operations: [op("0010", "MONT02", "Montagem do filtro", ["PCNF"], -4, 3, 40, { actualStart: -4 })],
    components: [comp("RM-2402", "Cesto inox FC-100", 120, 40, 200)],
    confirmations: [
      { date: -3, vornr: "0010", yield: 60, scrap: 0, user: "OPERADOR4", reversed: true },
      { date: -2, vornr: "0010", yield: 40, scrap: 0, user: "OPERADOR4", reversed: false },
    ],
  },
  {
    ...base,
    aufnr: "1000014",
    material: "FG-1003",
    description: "Válvula gaveta VG-50",
    mrpController: "002",
    systemStatus: ["REL", "PRC", "MACM"],
    planned: 800,
    confirmed: 0,
    delivered: 0,
    basicStart: 5,
    basicFinish: 12,
    schedStart: 5,
    schedFinish: 12,
    operations: [op("0010", "USIN01", "Usinagem do corpo", ["REL"], 5, 12)],
    components: [comp("RM-2201", "Corpo forjado VG-50", 800, 0, 2500)],
  },
  {
    ...base,
    aufnr: "2000001",
    material: "FG-2001",
    description: "Redutor RD-40",
    plant: "2000",
    mrpController: "010",
    scheduler: "201",
    systemStatus: ["REL", "PRC"],
    planned: 60,
    confirmed: 0,
    delivered: 0,
    basicStart: -1,
    basicFinish: 6,
    schedStart: -1,
    schedFinish: 6,
    operations: [op("0010", "MONT10", "Montagem do redutor", ["REL"], -1, 6)],
    components: [comp("RM-4001", "Engrenagem helicoidal", 120, 0, 500)],
  },
];

/** Componente com falta: indicador de falta ou estoque menor que o pendente. */
export function isShort(c: PpComponent): boolean {
  return c.missing || c.stock < c.required - c.withdrawn;
}

export function findOrder(aufnr: string): PpOrder | undefined {
  return ORDERS.find((o) => o.aufnr === aufnr);
}
