import { metricFor } from "../data/catalog";
import { Explain, Badge } from "./ui";
import type { Scope, ReviewState } from "../types";
import { navigate } from "../app/navigation";
export function MetricStrip({
  ids,
  scope,
  review,
}: {
  ids: string[];
  scope: Scope;
  review: ReviewState;
}) {
  return (
    <div className="metric-grid">
      {ids.map((id) => {
        const m = metricFor(id, scope);
        const qualified =
          review === "partial" &&
          ["spend", "querycompute", "forecast"].includes(id);
        const maturity =
          review === "provisional" && m.status === "RECONCILED"
            ? "PROVISIONAL"
            : review === "final" && m.status === "RECONCILED"
              ? "FINAL"
              : m.status;
        return (
          <section className="metric" key={id}>
            <div className="metric-label">
              {m.label}
              <Explain label={m.label} value={qualified ? "—" : m.value}>
                <dl className="details">
                  <dt>Metric fixture ID</dt>
                  <dd>{id}</dd>
                  <dt>Formula / basis</dt>
                  <dd>{m.formula}</dd>
                  <dt>Scope</dt>
                  <dd>{m.scope}</dd>
                  <dt>Publication</dt>
                  <dd>demo-2026-08-v1</dd>
                  <dt>Status</dt>
                  <dd>{maturity}</dd>
                  <dt>Coverage</dt>
                  <dd>
                    {qualified
                      ? "Unavailable in partial-data review scenario"
                      : "Synthetic complete observations for the named fixture"}
                  </dd>
                </dl>
                <button
                  className="text-button"
                  onClick={() => navigate("ledger")}
                >
                  Open billing ledger →
                </button>
              </Explain>
            </div>
            <div className="metric-value">{qualified ? "—" : m.value}</div>
            <p>{qualified ? "Missing source evidence" : m.hint}</p>
            {m.cents !== undefined && (
              <Badge
                tone={
                  maturity === "RECONCILED" || maturity === "VERIFIED"
                    ? "success"
                    : "neutral"
                }
              >
                {maturity}
              </Badge>
            )}
          </section>
        );
      })}
    </div>
  );
}
