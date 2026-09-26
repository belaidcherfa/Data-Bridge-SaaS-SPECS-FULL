import { useEffect, useState, lazy, Suspense } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  ArrowLeft,
  ArrowUpRight,
  Bookmark,
  Check,
  ChevronRight,
  Info,
  SlidersHorizontal,
} from "lucide-react";
import { getScreen, scopedPages, metrics } from "../data/catalog";
import { useRoute, navigate, setParam, href } from "./navigation";
import { AppShell } from "../components/AppShell";
import { MetricStrip } from "../components/MetricStrip";
import {
  Button,
  Badge,
  Overlay,
  Panel,
  StateBlock,
  LocalForm,
} from "../components/ui";
import { DataTable } from "../components/DataTable";
const DomainPanels = lazy(() =>
  import("../pages/DomainPanels").then((m) => ({ default: m.DomainPanels })),
);
import type { Screen, Scope } from "../types";
export function App() {
  const { id, scope, review } = useRoute();
  const screen = getScreen(id);
  const query = useQuery({
    queryKey: ["synthetic-workspace", id, scope],
    enabled: !!screen,
    queryFn: async ({ signal }) => {
      await new Promise<void>((resolve, reject) => {
        const t = setTimeout(resolve, 120);
        signal.addEventListener(
          "abort",
          () => {
            clearTimeout(t);
            reject(new Error("Request canceled"));
          },
          { once: true },
        );
      });
      return screen;
    },
    staleTime: 60_000,
    retry: false,
  });
  useEffect(() => {
    document.title =
      (screen?.title || "Page not found") + " · Bridge Data FinOps";
  }, [id, screen]);
  if (!screen)
    return (
      <AppShell>
        <h1>Page not found</h1>
        <p>This route is not in the design catalog.</p>
        <Button onClick={() => navigate("home")}>Return to overview</Button>
      </AppShell>
    );
  const excluded = ["loading", "empty", "error", "denied"];
  const state = excluded.includes(review)
    ? review
    : query.isPending
      ? "loading"
      : query.isError
        ? "error"
        : "ready";
  return (
    <AppShell screen={screen}>
      <div
        className="page"
        key={id + scope}
        data-page={id}
        data-ready={state === "ready"}
      >
        {state !== "ready" ? (
          <>
            <div className="eyebrow">
              {review === "denied" ? "Workspace access" : screen.group}
            </div>
            <h1>{review === "denied" ? "Access required" : screen.title}</h1>
            <StateBlock
              kind={state}
              onRetry={() => {
                setParam("state", "ready");
                void query.refetch();
              }}
            />
          </>
        ) : (
          <PageContent
            screen={screen}
            scope={scopedPages.has(id) ? scope : "all"}
          />
        )}
      </div>
    </AppShell>
  );
}
function PageContent({ screen: p, scope }: { screen: Screen; scope: Scope }) {
  const { review } = useRoute();
  const [saved, setSaved] = useState(false),
    [saveError, setSaveError] = useState(""),
    [view, setView] = useState("service");
  const [tab, setTab] = useState("Overview");
  const planning = p.id.startsWith("budget") || p.id === "forecast";
  const study = [
    "insights",
    "insight-detail",
    "savings",
    "savings-detail",
    "actions",
    "action-detail",
  ].includes(p.id);
  const parent = p.parent ? getScreen(p.parent) : null;
  const status =
    review === "provisional"
      ? "PROVISIONAL"
      : review === "final"
        ? "FINAL"
        : planning
          ? "PROVISIONAL"
          : p.id.startsWith("reconciliation") ||
              p.metrics.some(
                (id) =>
                  metrics[id]?.cents !== undefined &&
                  metrics[id]?.status === "FINAL",
              )
            ? "FINAL"
            : study
              ? "STUDY FIXTURE"
              : "RECONCILED";
  let rows = p.rows;
  if (scope === "production" && p.id === "explorer")
    rows = rows.filter((r) => !r[0].startsWith("Organization"));
  if (scope === "production" && p.id === "ledger")
    rows = rows.filter((r) => r[1] !== "Organization");
  let columns = p.columns;
  if (p.id === "explorer" && view === "account") {
    columns = ["Scope", "Net cost USD", "Basis", "Maturity"];
    rows =
      scope === "all"
        ? [
            ["PRODUCTION", "26,800.00", "Account charges", status],
            ["Organization", "200.00", "Support less rebate", status],
          ]
        : [["PRODUCTION", "26,800.00", "Account charges", status]];
  }
  function saveView() {
    try {
      localStorage.setItem(
        "bridge-design:view:" + p.id,
        JSON.stringify({
          hash: window.location.hash,
          view,
          savedAt: new Date().toISOString(),
        }),
      );
      setSaved(true);
      setSaveError("");
    } catch {
      setSaveError(
        "Browser storage unavailable; copy the page URL to retain this scope.",
      );
    }
  }
  const hasMoney = p.metrics.some((id) => metrics[id]?.cents !== undefined);
  const related =
    p.id === "home" ? ["explorer", "allocation", "budgets"] : p.children;
  return (
    <>
      <div className="breadcrumb">
        <span>{p.group}</span>
        {parent && (
          <>
            <ChevronRight size={12} />
            <a href={href(parent.id)}>{parent.title}</a>
          </>
        )}
        <ChevronRight size={12} />
        <span>{p.id === "home" ? "Overview" : p.title}</span>
      </div>
      <div className="page-heading">
        <div>
          <div className="eyebrow">
            {p.id === "home" ? "YOUR FINOPS WORKSPACE" : p.group.toUpperCase()}
          </div>
          <h1>{p.title}</h1>
          <p>{p.description}</p>
        </div>
        <div className="page-actions">
          {parent && (
            <Button
              aria-label="Back to parent"
              onClick={() => navigate(parent.id)}
            >
              <ArrowLeft size={15} />
            </Button>
          )}
          {p.kind === "editor" || p.kind === "auth" ? null : p.form.length ? (
            <Overlay
              title={p.action}
              trigger={<Button variant="primary">{p.action}</Button>}
            >
              <LocalForm id={p.id} fields={p.form} action={p.action} />
            </Overlay>
          ) : (
            <Button onClick={saveView}>
              {saved ? <Check size={15} /> : <Bookmark size={15} />}{" "}
              {saved ? "View saved" : "Save view"}
            </Button>
          )}
          <Overlay
            title="About this view"
            trigger={
              <Button aria-label="About this view">
                <SlidersHorizontal size={15} />
              </Button>
            }
          >
            <dl className="details">
              <dt>Audience</dt>
              <dd>{p.persona}</dd>
              <dt>Fixture contract</dt>
              <dd>{p.note}</dd>
              <dt>Route</dt>
              <dd>/{p.id}</dd>
              <dt>Documentation</dt>
              <dd>{p.document}</dd>
              <dt>Interaction boundary</dt>
              <dd>
                Local synthetic prototype. No backend, real RBAC, WIF connection
                or financial mutation.
              </dd>
            </dl>
          </Overlay>
        </div>
      </div>
      {saveError && (
        <p role="alert" className="error-text">
          {saveError}
        </p>
      )}
      {saved && (
        <div className="sr-only" role="status">
          View saved locally with its URL scope.
        </div>
      )}
      <div className="context-line">
        {hasMoney && (
          <button
            className="status-link"
            onClick={() => navigate("reconciliation")}
          >
            <Badge
              tone={
                status === "RECONCILED"
                  ? "success"
                  : status === "PROVISIONAL"
                    ? "warning"
                    : "neutral"
              }
            >
              {status}
            </Badge>
          </button>
        )}
        <span>
          {planning
            ? "September plan · actual through Sep 15"
            : study
              ? "Independent normalized study · named windows"
              : "August 2026 · demo publication v1"}
        </span>
        <span className="context-dot">·</span>
        <span>
          {planning ? "As of Sep 16, 00:00 UTC" : "Published Sep 01, 00:00 UTC"}
        </span>
        <span className="context-dot">·</span>
        <span>
          USD ·{" "}
          {scopedPages.has(p.id)
            ? scope === "all"
              ? "Organization + account"
              : "PRODUCTION only"
            : "Scope defined per panel"}
        </span>
      </div>
      {["partial", "stale", "provisional", "final"].includes(review) && (
        <div
          className={"notice " + (review === "partial" ? "warning" : "")}
          role="status"
        >
          <Info size={17} />
          <span>
            {review === "partial"
              ? "Partial-data review: affected totals are unavailable. Supporting rows remain a labelled known-data sample; no completeness claim."
              : review === "stale"
                ? "Stale review: retaining the last accepted publication and its timestamp. No mixed snapshot values."
                : `Financial maturity review: ${review.toUpperCase()}. Reconciliation and close remain separate dimensions.`}
          </span>
          <button
            className="text-button"
            onClick={() => navigate("data-health")}
          >
            Data Health →
          </button>
        </div>
      )}
      {related.length > 0 && (
        <nav className="local-nav" aria-label="Related pages">
          {related.map((id) => {
            const s = getScreen(id)!;
            return (
              <a href={href(id)} key={id}>
                {s.title}
                <ArrowUpRight size={12} />
              </a>
            );
          })}
        </nav>
      )}
      {p.metrics.length > 0 && (
        <MetricStrip ids={p.metrics} scope={scope} review={review} />
      )}
      {p.id === "warehouse-detail" && (
        <div className="tabs" role="tablist" aria-label="Warehouse detail tabs">
          {["Overview", "Queries", "Workloads", "Performance", "Evidence"].map(
            (t) => (
              <button
                key={t}
                role="tab"
                id={"tab-" + t}
                aria-controls="warehouse-tab-panel"
                aria-selected={tab === t}
                tabIndex={tab === t ? 0 : -1}
                onKeyDown={(e) => {
                  const tabs = [
                    "Overview",
                    "Queries",
                    "Workloads",
                    "Performance",
                    "Evidence",
                  ];
                  let i = tabs.indexOf(t);
                  if (e.key === "ArrowRight") i = (i + 1) % tabs.length;
                  else if (e.key === "ArrowLeft")
                    i = (i + tabs.length - 1) % tabs.length;
                  else if (e.key === "Home") i = 0;
                  else if (e.key === "End") i = tabs.length - 1;
                  else return;
                  e.preventDefault();
                  setTab(tabs[i]);
                  document.getElementById("tab-" + tabs[i])?.focus();
                }}
                onClick={() => setTab(t)}
              >
                {t}
              </button>
            ),
          )}
        </div>
      )}
      {p.id === "warehouse-detail" && tab !== "Overview" ? (
        <Panel title={tab}>
          <div
            id="warehouse-tab-panel"
            role="tabpanel"
            aria-labelledby={"tab-" + tab}
          >
            {tab === "Queries" ? (
              <Button onClick={() => navigate("queries")}>
                Open query explorer →
              </Button>
            ) : tab === "Workloads" ? (
              <Button onClick={() => navigate("workloads")}>
                Open workload evidence →
              </Button>
            ) : tab === "Performance" ? (
              <p>
                P50: 2.4 s · P95: 18.6 s · 12,480 completed executions.
                Percentiles use individual query observations.
              </p>
            ) : (
              <p>
                Classic warehouse · Medium · auto suspend 300 s. Configuration
                is synthetic evidence, not a live control.
              </p>
            )}
          </div>
        </Panel>
      ) : review === "partial" && ["home", "explorer"].includes(p.kind) ? (
        <Panel title="Spend trend unavailable">
          <p>
            Partial source coverage suppresses the complete-period chart.
            Inspect the known rows below and open Data Health.
          </p>
        </Panel>
      ) : (
        <Suspense
          fallback={
            <div
              className="skeleton"
              role="status"
              aria-label="Loading visualization"
            />
          }
        >
          <div
            id={p.id === "warehouse-detail" ? "warehouse-tab-panel" : undefined}
            role={p.id === "warehouse-detail" ? "tabpanel" : undefined}
            aria-labelledby={p.id === "warehouse-detail" ? "tab-Overview" : undefined}
          >
            <DomainPanels screen={p} scope={scope} />
          </div>
        </Suspense>
      )}
      {p.id === "explorer" && (
        <div className="analysis-controls">
          <span>
            <SlidersHorizontal size={16} /> Group costs by
          </span>
          <div className="segmented">
            <button
              aria-pressed={view === "service"}
              onClick={() => setView("service")}
            >
              Service
            </button>
            <button
              aria-pressed={view === "account"}
              onClick={() => setView("account")}
            >
              Account
            </button>
          </div>
          <span className="muted">
            Same publication · additive charges only
          </span>
        </div>
      )}
      {p.kind !== "auth" && (
        <DataTable
          key={p.id + view + scope}
          columns={columns}
          rows={rows}
          title={
            p.kind === "allocation"
              ? "Published allocation · Teams v1"
              : p.kind === "home"
                ? "Leading cost drivers"
                : p.title + " · detail"
          }
        />
      )}
      <div className="page-note">
        <Info size={15} />
        <p>{p.note}</p>
      </div>
    </>
  );
}
