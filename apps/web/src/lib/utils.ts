import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/** Converte "AAAA-MM-DD" em "09/10/2026" (sem fuso: é uma data do SAP). */
export function formatDate(iso: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  return match ? `${match[3]}/${match[2]}/${match[1]}` : iso;
}

/** Diferença em dias entre uma data "AAAA-MM-DD" e hoje (negativo = passado). */
export function daysFromToday(iso: string): number | undefined {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (!match) return undefined;
  const target = Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
  const now = new Date();
  const today = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
  return Math.round((target - today) / 86_400_000);
}

export function relativeDays(days: number): string {
  if (days === 0) return "hoje";
  if (days === 1) return "amanhã";
  if (days === -1) return "ontem";
  return days > 0 ? `em ${days} dias` : `há ${-days} dias`;
}

export function greeting(date = new Date()): string {
  const h = date.getHours();
  if (h < 12) return "Bom dia";
  if (h < 18) return "Boa tarde";
  return "Boa noite";
}

/** Primeiro número de uma string como "600 PC (60%)" → 60 (o percentual), ou "1.000 PC" → 1000. */
export function parsePercent(text: string | undefined): number | undefined {
  const match = text ? /\((\d+)%\)/.exec(text) : null;
  return match ? Number(match[1]) : undefined;
}

/** Troca datas "AAAA-MM-DD" dentro de um texto por "DD/MM/AAAA". */
export function localizeDates(text: string): string {
  return text.replace(/\b(\d{4})-(\d{2})-(\d{2})\b/g, "$3/$2/$1");
}

/** "Início: 0 dia(s) · Fim: 3 dia(s)" → { start: 0, finish: 3 } */
export function parseDelay(text: string | undefined): { start: number; finish: number } | undefined {
  const match = text ? /In[íi]cio: (\d+).*Fim: (\d+)/.exec(text) : null;
  return match ? { start: Number(match[1]), finish: Number(match[2]) } : undefined;
}
