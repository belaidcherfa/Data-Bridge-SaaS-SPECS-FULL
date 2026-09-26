import rawScreens from "../catalog/screens.json";
import rawMetrics from "../catalog/metrics.json";
import type { Screen, Metric, Scope } from "../types";
import { spend, usd, budget, savings } from "./financial";
export const screens = rawScreens as Screen[];
export const metrics = rawMetrics as Record<string, Metric>;
export const groups = [
  "Overview",
  "Explore",
  "Allocate",
  "Govern",
  "Optimize",
  "Platform",
  "Settings",
];
export const getScreen = (id: string) => screens.find((s) => s.id === id);
export const scopedPages = new Set(["home", "explorer", "ledger", "services"]);
export function metricFor(id: string, scope: Scope = "all"): Metric {
  const value = metrics[id];
  if (!value) throw new Error("Unknown metric " + id);
  const b = budget(),
    s = savings();
  const amounts: Record<string, number> = {
    spend: spend(scope),
    accountcost: spend("production"),
    orgnet: scope === "all" ? 20000 : 0,
    budget: b.limit,
    budgetactual: b.actual,
    remaining: b.remaining,
    forecast: b.forecast,
    forecastvariance: b.variance,
    burnday: b.burn,
    verifiedsavings: s.realized,
    baseline: s.baseline,
    postcost: s.post,
    normalized: s.expected,
  };
  return id in amounts
    ? {
        ...value,
        cents: amounts[id],
        value: usd(amounts[id]),
        hint:
          id === "orgnet" && scope === "production"
            ? "Organization adjustments excluded by account scope"
            : value.hint,
        scope:
          id === "spend"
            ? scope === "all"
              ? "Organization + account / August 2026"
              : "PRODUCTION only / August 2026"
            : value.scope,
      }
    : value;
}
