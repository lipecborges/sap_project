import { useNavigate } from "@tanstack/react-router";
import { ArrowRight, Factory, Loader2, Lock, Receipt, ShoppingCart, Sparkles } from "lucide-react";
import { type FormEvent, useState } from "react";
import { Button } from "../components/ui/button";
import { RequestError } from "../lib/api";
import { useAuth } from "../lib/auth";

const FEATURES = [
  {
    icon: Sparkles,
    title: "Pergunte em português",
    text: "“Por que o pedido 4500001 não faturou?” e receba causa, evidência e transação.",
  },
  {
    icon: Factory,
    title: "Produção sob controle",
    text: "Ordens atrasadas, falta de material e risco para o pedido do cliente.",
  },
  {
    icon: ShoppingCart,
    title: "Pedidos travados",
    text: "Crédito, remessa, saída de mercadoria e faturamento num só lugar.",
  },
  { icon: Receipt, title: "Faturas bloqueadas", text: "Divergências de preço, quantidade e data antes do vencimento." },
];

export function LoginPage({ redirect }: { redirect?: string }) {
  const { login } = useAuth();
  const navigate = useNavigate();
  const [user, setUser] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string>();
  const [busy, setBusy] = useState(false);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(undefined);
    try {
      await login({ user: user.trim(), password });
      navigate({ to: redirect?.startsWith("/") ? redirect : "/" });
    } catch (err) {
      setError(err instanceof RequestError ? err.message : "Não foi possível entrar");
    } finally {
      setBusy(false);
    }
  }

  const input =
    "mt-1.5 block h-11 w-full rounded-lg border border-zinc-300 bg-white px-3.5 text-sm shadow-xs outline-none transition focus:border-brand-500 focus:ring-4 focus:ring-brand-500/15 dark:border-zinc-700 dark:bg-zinc-900";

  return (
    <div className="grid min-h-full lg:grid-cols-[1.1fr_1fr]">
      <section className="relative hidden overflow-hidden bg-zinc-950 p-12 text-white lg:flex lg:flex-col">
        <div className="pointer-events-none absolute -top-40 -left-40 size-[36rem] rounded-full bg-brand-600/30 blur-3xl" />
        <div className="pointer-events-none absolute -right-32 bottom-0 size-[28rem] rounded-full bg-violet-600/20 blur-3xl" />
        <div className="relative flex items-center gap-2.5">
          <div className="flex size-9 items-center justify-center rounded-lg bg-gradient-to-br from-brand-400 to-brand-700 text-sm font-bold">
            RX
          </div>
          <span className="text-lg font-semibold">Raio-X</span>
        </div>
        <div className="relative mt-auto max-w-lg">
          <h1 className="text-4xl leading-tight font-semibold tracking-tight">
            Descubra por que o processo travou, <span className="text-brand-300">em segundos.</span>
          </h1>
          <p className="mt-4 text-zinc-400">
            Diagnósticos de SD, MM e PP direto no seu SAP ECC ou S/4HANA, com IA que explica a causa e o próximo passo.
          </p>
          <ul className="mt-10 grid grid-cols-2 gap-5">
            {FEATURES.map((f) => (
              <li key={f.title} className="rounded-xl border border-white/10 bg-white/5 p-4">
                <f.icon className="size-5 text-brand-300" />
                <p className="mt-3 text-sm font-medium">{f.title}</p>
                <p className="mt-1 text-xs leading-relaxed text-zinc-400">{f.text}</p>
              </li>
            ))}
          </ul>
        </div>
        <p className="relative mt-10 flex items-center gap-2 text-xs text-zinc-500">
          <Lock className="size-3.5" /> Somente leitura · respeita as autorizações SAP de cada usuário
        </p>
      </section>

      <section className="flex items-center justify-center px-6 py-12">
        <form onSubmit={submit} className="w-full max-w-sm">
          <div className="mb-8 lg:hidden">
            <div className="flex size-10 items-center justify-center rounded-lg bg-gradient-to-br from-brand-500 to-brand-700 font-bold text-white">
              RX
            </div>
          </div>
          <h2 className="text-2xl font-semibold tracking-tight">Entrar</h2>
          <p className="mt-1 text-sm text-zinc-500 dark:text-zinc-400">Use o mesmo usuário e senha do SAP.</p>

          <div className="mt-8 space-y-4">
            <label className="block text-sm font-medium">
              Usuário SAP
              <input
                className={`${input} uppercase`}
                autoComplete="username"
                autoCapitalize="characters"
                value={user}
                onChange={(e) => setUser(e.target.value)}
                required
              />
            </label>
            <label className="block text-sm font-medium">
              Senha
              <input
                className={input}
                type="password"
                autoComplete="current-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
              />
            </label>
          </div>

          {error && (
            <p
              role="alert"
              className="mt-4 rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700 dark:border-red-900 dark:bg-red-950/50 dark:text-red-300"
            >
              {error}
            </p>
          )}

          <Button type="submit" size="lg" className="mt-6 w-full" disabled={busy}>
            {busy ? <Loader2 className="animate-spin" /> : null}
            {busy ? "Validando no SAP…" : "Entrar"}
            {!busy && <ArrowRight />}
          </Button>
          <p className="mt-6 text-center text-xs text-zinc-500">
            A senha é validada pelo próprio SAP e não é armazenada.
          </p>
        </form>
      </section>
    </div>
  );
}
