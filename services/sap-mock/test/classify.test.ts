import { describe, expect, it } from "vitest";
import { classify } from "../src/pp/classify";
import { findOrder, ORDERS } from "../src/pp/orders";

const order = (aufnr: string) => {
  const o = findOrder(aufnr);
  if (!o) throw new Error(`ordem ${aufnr} não existe na base`);
  return o;
};

describe("classificação de ordens (regras do catálogo PP-03)", () => {
  it.each([
    ["1000001", "CREATED"],
    ["1000003", "RELEASED"],
    ["1000005", "TECHNICALLY_COMPLETED"],
    ["1000006", "APPROVED"],
    ["1000010", "IN_PRODUCTION"],
    ["1000011", "DELIVERED"],
    ["1000012", "CONFIRMED"],
  ])("ordem %s → %s", (aufnr, situation) => {
    expect(classify(order(aufnr)).situation).toBe(situation);
  });

  it("calcula os dias de atraso", () => {
    const c = classify(order("1000010"));
    expect(c.finishDelayDays).toBe(3);
    expect(c.startDelayDays).toBe(0);
    expect(classify(order("1000001")).startDelayDays).toBe(2);
  });

  it("respeita a tolerância", () => {
    expect(classify(order("1000010"), { toleranceDays: 5 }).flags).not.toContain("LATE_FINISH");
  });

  it("ordens encerradas não ficam atrasadas", () => {
    expect(classify(order("1000005")).flags).toEqual([]);
    expect(classify(order("1000011")).flags).toEqual([]);
  });

  it("PCNF sem entrada não é 'confirmada sem entrada'", () => {
    expect(classify(order("1000010")).flags).not.toContain("CONFIRMED_NOT_RECEIVED");
  });

  it("números de ordem são únicos", () => {
    expect(new Set(ORDERS.map((o) => o.aufnr)).size).toBe(ORDERS.length);
  });
});
