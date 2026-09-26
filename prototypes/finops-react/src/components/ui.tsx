import { useState } from "react";
import type { ReactNode, ButtonHTMLAttributes } from "react";
import { Dialog } from "radix-ui";
import { X, ArrowUpRight, Info, Check, AlertTriangle } from "lucide-react";
export function Button({
  children,
  variant = "secondary",
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "primary" | "secondary" | "ghost";
}) {
  return (
    <button
      {...props}
      className={"button " + variant + " " + (props.className || "")}
    >
      {children}
    </button>
  );
}
export function Badge({
  children,
  tone = "neutral",
}: {
  children: ReactNode;
  tone?: string;
}) {
  return (
    <span className={"badge " + tone}>
      {tone === "success" ? (
        <Check size={12} />
      ) : tone === "warning" ? (
        <AlertTriangle size={12} />
      ) : null}
      {children}
    </span>
  );
}
export function Panel({
  title,
  subtitle,
  children,
  action,
  className = "",
}: {
  title: string;
  subtitle?: string;
  children: ReactNode;
  action?: ReactNode;
  className?: string;
}) {
  return (
    <section className={"panel " + className}>
      <div className="panel-head">
        <div>
          <h2>{title}</h2>
          {subtitle && <p>{subtitle}</p>}
        </div>
        {action}
      </div>
      {children}
    </section>
  );
}
export function Overlay({
  title,
  description,
  children,
  trigger,
  wide = false,
  open,
  onOpenChange,
}: {
  title: string;
  description?: string;
  children: ReactNode;
  trigger?: ReactNode;
  wide?: boolean;
  open?: boolean;
  onOpenChange?: (open: boolean) => void;
}) {
  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      {trigger && <Dialog.Trigger asChild>{trigger}</Dialog.Trigger>}
      <Dialog.Portal>
        <Dialog.Overlay className="dialog-overlay" />
        <Dialog.Content className={"dialog " + (wide ? "wide" : "")}>
          <Dialog.Title>{title}</Dialog.Title>
          <Dialog.Description className="muted">
            {description ||
              "Synthetic design preview. No external service is modified."}
          </Dialog.Description>
          <Dialog.Close asChild>
            <button
              className="icon-button dialog-close"
              aria-label="Close dialog"
            >
              <X size={20} />
            </button>
          </Dialog.Close>
          {children}
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
export function Explain({
  label,
  value,
  children,
}: {
  label: string;
  value: string;
  children: ReactNode;
}) {
  return (
    <Overlay
      title={label}
      trigger={
        <button className="explain" aria-label={"Explain " + label}>
          <Info size={15} />
        </button>
      }
    >
      <div className="explain-value">{value}</div>
      {children}
    </Overlay>
  );
}
export function LinkCard({
  title,
  body,
  onClick,
}: {
  title: string;
  body: string;
  onClick: () => void;
}) {
  return (
    <button className="link-card" onClick={onClick}>
      <span>
        <strong>{title}</strong>
        <small>{body}</small>
      </span>
      <ArrowUpRight size={17} />
    </button>
  );
}
export function StateBlock({
  kind,
  onRetry,
}: {
  kind: string;
  onRetry: () => void;
}) {
  const copy: Record<string, [string, string]> = {
    empty: [
      "No activity for this selection",
      "This is a confirmed empty demo state. Choose another scope to continue.",
    ],
    error: [
      "We could not load this view",
      "Your scope is preserved. Retry the synthetic data request. Reference: DEMO-042.",
    ],
    denied: [
      "This view needs additional access",
      "No resource names, financial values or exports are available in this state. Contact your workspace administrator.",
    ],
  };
  if (kind === "loading")
    return (
      <div role="status" aria-label="Loading view" className="skeleton-layout">
        <div className="skeleton" />
        <div className="skeleton" />
        <div className="skeleton large" />
      </div>
    );
  const [title, body] = copy[kind] || copy.error;
  return (
    <section className="state-block" role="status">
      <div className="state-symbol">{kind === "denied" ? "↗" : "○"}</div>
      <h2>{title}</h2>
      <p>{body}</p>
      <Button onClick={onRetry}>
        {kind === "error" ? "Retry" : "Return to demo data"}
      </Button>
    </section>
  );
}
export function LocalForm({
  id,
  fields,
  action,
}: {
  id: string;
  fields: string[];
  action: string;
}) {
  const key = "bridge-design:draft:" + id;
  const [values, setValues] = useState<Record<string, string>>(() => {
    try {
      return JSON.parse(localStorage.getItem(key) || "{}");
    } catch {
      return {};
    }
  });
  const [saved, setSaved] = useState(false),
    [error, setError] = useState("");
  return (
    <form
      className="local-form"
      onSubmit={(e) => {
        e.preventDefault();
        if (fields.some((f) => !values[f]?.trim())) {
          setError("Complete each required field before saving.");
          return;
        }
        try {
          localStorage.setItem(key, JSON.stringify(values));
          setSaved(true);
          setError("");
        } catch {
          setError(
            "Browser storage is unavailable. Keep this draft open and copy your values.",
          );
        }
      }}
    >
      {fields.map((f) => (
        <label key={f}>
          {f} <span className="muted">*</span>
          <input
            required
            value={values[f] || ""}
            onChange={(e) => {
              setValues({ ...values, [f]: e.target.value });
              setSaved(false);
            }}
            placeholder={"Enter " + f.toLowerCase()}
          />
        </label>
      ))}
      <p className="muted">
        Demo only. Use synthetic values; no credentials or personal data. Drafts
        remain in this browser.
      </p>
      {error && (
        <p className="error-text" role="alert">
          {error}
        </p>
      )}
      {saved && (
        <p className="success-text" role="status">
          Draft saved locally. No production change or external message.
        </p>
      )}
      <Button type="submit" variant="primary">
        {action}
      </Button>
    </form>
  );
}
