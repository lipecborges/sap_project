import type { DiagnosticMeta, DiagnosticResult, ParamMeta } from "@raiox/contracts";
import { type FormEvent, type ReactNode, useId, useState } from "react";
import { api, type Credentials, RequestError } from "../api";
import { enumLabel, MOCK_EXAMPLES } from "../labels";
import { ResultView } from "./ResultView";

interface Props {
  credentials: Credentials;
  diagnostics: DiagnosticMeta[];
  /** Mostra os documentos de exemplo do sap-mock. */
  showExamples: boolean;
}

export function DiagnosticRunner({ credentials, diagnostics, showExamples }: Props) {
  const [selectedId, setSelectedId] = useState(diagnostics[0]?.id ?? "");
  const [params, setParams] = useState<Record<string, string>>({});
  const [result, setResult] = useState<DiagnosticResult>();
  const [error, setError] = useState<RequestError>();
  const [busy, setBusy] = useState(false);
  const selected = diagnostics.find((d) => d.id === selectedId);

  function select(id: string) {
    setSelectedId(id);
    setParams({});
    setResult(undefined);
    setError(undefined);
  }

  async function run(values: Record<string, string>) {
    if (!selected) return;
    setBusy(true);
    setError(undefined);
    try {
      const filled = Object.fromEntries(Object.entries(values).filter(([, v]) => v.trim() !== ""));
      setResult(await api.run(credentials, selected.id, filled));
    } catch (err) {
      setResult(undefined);
      setError(err instanceof RequestError ? err : new RequestError(0, "UNKNOWN", String(err)));
    } finally {
      setBusy(false);
    }
  }

  function submit(event: FormEvent) {
    event.preventDefault();
    void run(params);
  }

  return (
    <div className="grid gap-6 lg:grid-cols-[18rem_1fr]">
      <nav
        aria-label="Diagnósticos"
        className="-mx-4 flex gap-2 overflow-x-auto px-4 pb-1 lg:mx-0 lg:block lg:space-y-1 lg:overflow-visible lg:px-0"
      >
        {diagnostics.map((d) => (
          <button
            key={d.id}
            type="button"
            onClick={() => select(d.id)}
            aria-current={d.id === selectedId}
            className={`block w-60 shrink-0 rounded-lg px-3 py-2 text-left text-sm lg:w-full ${
              d.id === selectedId ? "bg-brand-700 text-white" : "hover:bg-slate-200/70 dark:hover:bg-slate-800"
            }`}
          >
            <span className="font-mono text-xs opacity-80">{d.id}</span>
            <span className="block font-medium">{d.title}</span>
          </button>
        ))}
      </nav>

      {selected && (
        <div className="min-w-0 space-y-6">
          <form
            onSubmit={submit}
            className="space-y-4 rounded-2xl border border-slate-200 bg-white p-4 sm:p-5 dark:border-slate-800 dark:bg-slate-900"
          >
            <h2 className="text-lg font-semibold">{selected.title}</h2>
            <div className="grid gap-4 sm:grid-cols-2">
              {selected.params.map((p) => (
                <ParamField
                  key={p.name}
                  param={p}
                  value={params[p.name] ?? ""}
                  error={error?.params?.[p.name]}
                  onChange={(value) => setParams((prev) => ({ ...prev, [p.name]: value }))}
                />
              ))}
            </div>
            <div className="flex flex-wrap items-center gap-2">
              <button
                type="submit"
                disabled={busy}
                className="rounded-lg bg-brand-700 px-4 py-2 font-medium text-white hover:bg-brand-800 disabled:opacity-60"
              >
                {busy ? "Consultando o SAP…" : "Diagnosticar"}
              </button>
              {showExamples &&
                MOCK_EXAMPLES[selected.id]?.map((ex) => (
                  <button
                    key={ex.label}
                    type="button"
                    onClick={() => {
                      setParams(ex.params);
                      void run(ex.params);
                    }}
                    className="rounded-full border border-slate-300 px-3 py-1 text-xs hover:bg-slate-100 dark:border-slate-700 dark:hover:bg-slate-800"
                  >
                    {ex.label}
                  </button>
                ))}
            </div>
            {error && !error.params && (
              <p
                role="alert"
                className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-800 dark:bg-red-950/50 dark:text-red-200"
              >
                {error.message}
              </p>
            )}
          </form>
          {result && <ResultView result={result} />}
        </div>
      )}
    </div>
  );
}

const inputClass =
  "mt-1 w-full rounded-lg border border-slate-300 bg-white px-3 py-2 outline-none focus:border-brand-600 focus:ring-2 focus:ring-brand-100 dark:border-slate-700 dark:bg-slate-950 dark:focus:ring-brand-800";

function ParamField({
  param,
  value,
  error,
  onChange,
}: {
  param: ParamMeta;
  value: string;
  error?: string;
  onChange: (value: string) => void;
}) {
  const id = useId();
  const label = `${param.label}${param.required ? " *" : ""}`;
  let input: ReactNode;
  if (param.dataType === "ENUM") {
    input = (
      <select id={id} className={inputClass} value={value} onChange={(e) => onChange(e.target.value)}>
        <option value="">Todas</option>
        {param.options.map((o) => (
          <option key={o} value={o}>
            {enumLabel(o)}
          </option>
        ))}
      </select>
    );
  } else {
    const numeric = param.dataType === "DOCUMENT" || param.dataType === "INTEGER";
    input = (
      <input
        id={id}
        className={inputClass}
        type={param.dataType === "DATE" ? "date" : "text"}
        inputMode={numeric ? "numeric" : undefined}
        value={value}
        required={param.required}
        onChange={(e) => onChange(e.target.value)}
      />
    );
  }
  return (
    <div className="text-sm font-medium">
      <label htmlFor={id}>{label}</label>
      {input}
      {error && <span className="mt-1 block text-xs text-red-700 dark:text-red-300">{error}</span>}
    </div>
  );
}
