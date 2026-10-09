import { LicenseInstall, type LicenseStatus } from "@raiox/contracts";
import { AlertTriangle, FileUp, Loader2 } from "lucide-react";
import { type ReactNode, useRef, useState } from "react";
import { Badge } from "../../components/ui/badge";
import { Button } from "../../components/ui/button";
import { Card, CardHeader } from "../../components/ui/card";
import { Callout } from "../../components/ui/form";
import { ErrorState, Progress, Skeleton } from "../../components/ui/misc";
import { PageHeader } from "../../components/ui/page";
import { formatDay, isLicenseFile, LICENSE_STATE, seatPercent } from "../../lib/admin";
import { errorMessage, useAdminLicense, useAdminMutation } from "../../lib/admin-queries";
import { api } from "../../lib/api";
import { cn } from "../../lib/utils";

function Item({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="min-w-0">
      <dt className="text-xs text-zinc-500 dark:text-zinc-400">{label}</dt>
      <dd className="mt-0.5 truncate text-sm font-medium">{children}</dd>
    </div>
  );
}

function StatusCard({ license }: { license: LicenseStatus }) {
  const meta = LICENSE_STATE[license.state];
  const pct = seatPercent(license.usedSeats, license.maxNamedUsers);
  const stripe = {
    good: "bg-emerald-500",
    info: "bg-sky-500",
    warning: "bg-amber-500",
    critical: "bg-red-500",
  } as Record<string, string>;
  return (
    <Card className="overflow-hidden">
      <div className={cn("h-1", stripe[meta.tone] ?? "bg-zinc-300")} />
      <div className="flex flex-wrap items-center gap-3 px-5 pt-4">
        <h2 className="text-sm font-semibold">Situação da licença</h2>
        <Badge tone={meta.tone}>{meta.label}</Badge>
      </div>
      <p className="px-5 pt-1 text-sm text-zinc-500 dark:text-zinc-400">{meta.hint}</p>

      <dl className="grid grid-cols-2 gap-x-6 gap-y-4 px-5 pt-5 sm:grid-cols-3">
        <Item label="Cliente">{license.customer ?? "—"}</Item>
        <Item label="Edição">{license.edition ?? "—"}</Item>
        <Item label="Validade">{license.expiresAt ? formatDay(license.expiresAt) : "Sem vencimento"}</Item>
        <Item label="Identificador">
          <span className="font-mono text-[0.8125rem]">{license.licenseId ?? "—"}</span>
        </Item>
      </dl>

      <div className="px-5 pt-5">
        <div className="flex items-baseline justify-between text-sm">
          <span className="text-zinc-500 dark:text-zinc-400">Usuários nomeados</span>
          <span className="tabular-nums">
            <strong className="text-base">{license.usedSeats}</strong> de {license.maxNamedUsers}
          </span>
        </div>
        <Progress value={pct} tone={pct >= 100 ? "critical" : pct >= 90 ? "warning" : "brand"} className="mt-2" />
      </div>

      <div className="px-5 pt-5 pb-5">
        <p className="text-xs text-zinc-500 dark:text-zinc-400">Recursos incluídos</p>
        {license.features.length > 0 ? (
          <ul className="mt-2 flex flex-wrap gap-1.5">
            {license.features.map((f) => (
              <li key={f}>
                <Badge tone="neutral">{f}</Badge>
              </li>
            ))}
          </ul>
        ) : (
          <p className="mt-1 text-sm text-zinc-500">Nenhum recurso adicional.</p>
        )}
      </div>

      {license.warnings.length > 0 && (
        <ul className="space-y-2 border-t border-zinc-100 px-5 py-4 dark:border-zinc-800">
          {license.warnings.map((w) => (
            <li key={w}>
              <Callout tone="warning" className="flex items-start gap-2">
                <AlertTriangle className="mt-0.5 size-4 shrink-0" /> {w}
              </Callout>
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}

function InstallCard() {
  const [text, setText] = useState("");
  const [error, setError] = useState<string>();
  const file = useRef<HTMLInputElement>(null);

  const install = useAdminMutation((license: string) => api.admin.installLicense(license), {
    success: "Licença instalada",
    invalidate: [
      ["admin", "license"],
      ["admin", "users"],
    ],
    onSuccess: () => setText(""),
    onError: (err) => setError(errorMessage(err)),
    toastError: false,
  });

  async function onFile(f: File | undefined) {
    if (!f) return;
    setError(undefined);
    if (!isLicenseFile(f)) {
      setError("Escolha o arquivo de licença (.txt ou .lic) recebido do fornecedor.");
    } else {
      setText((await f.text()).trim());
    }
    if (file.current) file.current.value = "";
  }

  function submit() {
    setError(undefined);
    const parsed = LicenseInstall.safeParse({ license: text });
    if (!parsed.success) {
      setError("O texto da licença está vazio ou incompleto. Cole-o por inteiro.");
      return;
    }
    install.mutate(parsed.data.license);
  }

  return (
    <Card>
      <CardHeader
        title="Instalar licença"
        description="Cole o texto da licença assinada ou envie o arquivo recebido do fornecedor. A nova licença substitui a atual."
      />
      <div className="space-y-3 px-5 pb-5">
        <textarea
          value={text}
          onChange={(e) => setText(e.target.value)}
          rows={7}
          spellCheck={false}
          placeholder="Cole aqui o texto da licença"
          aria-label="Texto da licença"
          className="block w-full resize-y rounded-lg border border-zinc-300 bg-white p-3 font-mono text-xs leading-relaxed shadow-xs outline-none transition placeholder:text-zinc-400 focus:border-brand-500 focus:ring-4 focus:ring-brand-500/15 dark:border-zinc-700 dark:bg-zinc-900"
        />
        {error && <Callout tone="critical">{error}</Callout>}
        <div className="flex flex-wrap items-center gap-2">
          <input
            ref={file}
            type="file"
            accept=".txt,.lic,text/plain"
            className="sr-only"
            aria-label="Arquivo de licença"
            onChange={(e) => void onFile(e.target.files?.[0])}
          />
          <Button variant="outline" onClick={() => file.current?.click()}>
            <FileUp /> Enviar arquivo
          </Button>
          <Button className="sm:ml-auto" onClick={submit} disabled={install.isPending || !text.trim()}>
            {install.isPending && <Loader2 className="animate-spin" />}
            Instalar licença
          </Button>
        </div>
      </div>
    </Card>
  );
}

export function LicensePage() {
  const { data, isLoading, error, refetch } = useAdminLicense();
  return (
    <>
      <PageHeader title="Licença" description="Situação do licenciamento e instalação de uma nova licença." />
      <div className="grid items-start gap-6 xl:grid-cols-2">
        {isLoading ? (
          <Skeleton className="h-96 w-full rounded-xl" />
        ) : error ? (
          <Card>
            <ErrorState error={error} onRetry={() => refetch()} />
          </Card>
        ) : data ? (
          <StatusCard license={data} />
        ) : null}
        <InstallCard />
      </div>
    </>
  );
}
