import { Loader2, X } from "lucide-react";
import { Dialog } from "radix-ui";
import type { ReactNode } from "react";
import { cn } from "../../lib/utils";
import { Button } from "./button";

/** Janela modal centralizada; em telas estreitas ocupa a largura toda menos a margem. */
export function Modal({
  open,
  onOpenChange,
  title,
  description,
  children,
  footer,
  className,
  dismissible = true,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: ReactNode;
  description?: ReactNode;
  children?: ReactNode;
  footer?: ReactNode;
  className?: string;
  /** false impede fechar por clique fora ou Esc (ex.: token que aparece uma única vez). */
  dismissible?: boolean;
}) {
  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-50 grid grid-cols-[minmax(0,1fr)] place-items-center overflow-y-auto bg-zinc-950/45 p-4 backdrop-blur-[2px]">
          <Dialog.Content
            onPointerDownOutside={dismissible ? undefined : (e) => e.preventDefault()}
            onEscapeKeyDown={dismissible ? undefined : (e) => e.preventDefault()}
            className={cn(
              "animate-fade-in w-full max-w-lg rounded-xl border border-zinc-200 bg-white shadow-2xl outline-none dark:border-zinc-800 dark:bg-zinc-900",
              className,
            )}
          >
            <div className="flex items-start gap-3 px-5 pt-5">
              <div className="min-w-0 flex-1">
                <Dialog.Title className="text-base font-semibold tracking-tight">{title}</Dialog.Title>
                {description ? (
                  <Dialog.Description asChild>
                    <div className="mt-1.5 text-sm leading-relaxed text-zinc-500 dark:text-zinc-400">{description}</div>
                  </Dialog.Description>
                ) : (
                  <Dialog.Description className="sr-only">{typeof title === "string" ? title : ""}</Dialog.Description>
                )}
              </div>
              {dismissible && (
                <Dialog.Close
                  aria-label="Fechar"
                  className="-mt-1 -mr-1.5 rounded-md p-1.5 text-zinc-400 hover:bg-zinc-100 hover:text-zinc-700 dark:hover:bg-zinc-800 dark:hover:text-zinc-200"
                >
                  <X className="size-4" />
                </Dialog.Close>
              )}
            </div>
            {children && <div className="px-5 py-4">{children}</div>}
            {footer && (
              <div className="flex flex-col-reverse gap-2 px-5 pt-1 pb-5 sm:flex-row sm:justify-end">{footer}</div>
            )}
          </Dialog.Content>
        </Dialog.Overlay>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

/** Confirmação de ação que muda dados: explica a consequência e só fecha quando a operação termina. */
export function ConfirmDialog({
  open,
  onOpenChange,
  title,
  description,
  confirmLabel,
  destructive = false,
  pending = false,
  onConfirm,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: ReactNode;
  description: ReactNode;
  confirmLabel: string;
  destructive?: boolean;
  pending?: boolean;
  onConfirm: () => void;
}) {
  return (
    <Modal
      open={open}
      onOpenChange={(o) => !pending && onOpenChange(o)}
      title={title}
      description={description}
      className="max-w-md"
      footer={
        <>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={pending}>
            Cancelar
          </Button>
          <Button variant={destructive ? "danger" : "primary"} onClick={onConfirm} disabled={pending}>
            {pending && <Loader2 className="animate-spin" />}
            {confirmLabel}
          </Button>
        </>
      }
    />
  );
}

/** Painel lateral (gaveta) usado no celular para o histórico de conversas. */
export function Sheet({
  open,
  onOpenChange,
  title,
  children,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  children: ReactNode;
}) {
  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-50 bg-zinc-950/45" />
        <Dialog.Content className="fixed inset-y-0 left-0 z-50 flex w-80 max-w-[88vw] flex-col bg-zinc-50 shadow-2xl outline-none dark:bg-zinc-950">
          <div className="flex items-center justify-between border-b border-zinc-200 px-4 py-3 dark:border-zinc-800">
            <Dialog.Title className="text-sm font-semibold">{title}</Dialog.Title>
            <Dialog.Close aria-label="Fechar" className="rounded-md p-1 text-zinc-500 hover:bg-zinc-200/60">
              <X className="size-5" />
            </Dialog.Close>
          </div>
          <Dialog.Description className="sr-only">{title}</Dialog.Description>
          <div className="min-h-0 flex-1">{children}</div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
