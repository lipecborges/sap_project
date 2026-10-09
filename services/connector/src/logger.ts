import type { LogLevel } from "./config";

const ORDER: Record<LogLevel, number> = { debug: 10, info: 20, warn: 30, error: 40, silent: 100 };

export interface Logger {
  debug(fields: Record<string, unknown>, msg: string): void;
  info(fields: Record<string, unknown>, msg: string): void;
  warn(fields: Record<string, unknown>, msg: string): void;
  error(fields: Record<string, unknown>, msg: string): void;
}

/**
 * Logs estruturados em JSON, uma linha por evento. Nunca recebem credenciais, cabeçalhos nem corpos:
 * quem chama passa só metadados (método, caminho sem query, status, duração).
 */
export function createLogger(
  level: LogLevel,
  write: (line: string) => void = (l) => process.stdout.write(`${l}\n`),
): Logger {
  const emit = (name: Exclude<LogLevel, "silent">) => (fields: Record<string, unknown>, msg: string) => {
    if (ORDER[name] < ORDER[level]) return;
    write(JSON.stringify({ level: name, time: new Date().toISOString(), msg, ...fields }));
  };
  return { debug: emit("debug"), info: emit("info"), warn: emit("warn"), error: emit("error") };
}

export const silentLogger: Logger = createLogger("silent");
