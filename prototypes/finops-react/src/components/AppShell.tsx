import { useState } from "react";
import type { ReactNode } from "react";
import {
  LayoutDashboard,
  Compass,
  Database,
  Zap,
  GitBranch,
  Layers,
  Tags,
  Split,
  Users,
  Wallet,
  ShieldCheck,
  Activity,
  FileBarChart,
  Lightbulb,
  CheckSquare,
  TrendingDown,
  HeartPulse,
  Plug,
  Settings,
  Search,
  Menu,
  ChevronDown,
  ArrowUpRight,
  Sparkles,
} from "lucide-react";
import { screens, groups, scopedPages } from "../data/catalog";
import { href, navigate, setParam, useRoute } from "../app/navigation";
import { Badge, Button, Overlay } from "./ui";
import type { Screen } from "../types";
const icons: Record<string, typeof Compass> = {
  home: LayoutDashboard,
  dashboards: Layers,
  explorer: Compass,
  warehouses: Database,
  queries: Zap,
  workloads: GitBranch,
  storage: Database,
  serverless: Zap,
  ai: Sparkles,
  spcs: Layers,
  tags: Tags,
  allocation: Split,
  "usage-groups": Users,
  showback: Users,
  chargeback: Wallet,
  reconciliation: ShieldCheck,
  budgets: Wallet,
  monitors: Activity,
  reports: FileBarChart,
  insights: Lightbulb,
  actions: CheckSquare,
  savings: TrendingDown,
  "data-health": HeartPulse,
  integrations: Plug,
  settings: Settings,
};
function Navigation({
  screen,
  close,
}: {
  screen?: Screen;
  close?: () => void;
}) {
  return (
    <>
      <a className="brand" href={href("home")} onClick={close}>
        <span className="brand-mark">
          b<span />
        </span>
        <span>
          Bridge<span className="brand-sub">DATA FINOPS</span>
        </span>
      </a>
      <nav aria-label="Main navigation">
        {groups.map((group) => (
          <div className="nav-group" key={group}>
            <div className="nav-label">{group}</div>
            {screens
              .filter((s) => s.group === group && !s.parent)
              .map((s) => {
                const Icon = icons[s.id] || Compass;
                let active = screen?.id === s.id;
                let parent = screen?.parent;
                while (parent) {
                  if (parent === s.id) active = true;
                  parent = screens.find((p) => p.id === parent)?.parent || null;
                }
                return (
                  <a
                    key={s.id}
                    href={href(s.id)}
                    className={"nav-item " + (active ? "active" : "")}
                    aria-current={active ? "page" : undefined}
                    onClick={close}
                  >
                    <Icon size={16} />
                    {s.id === "home" ? "Overview" : s.title}
                  </a>
                );
              })}
          </div>
        ))}
      </nav>
      <div className="sidebar-footer">
        <div className="workspace-health">
          <i className="dot green" />
          <span>
            Demo workspace <small>All data is synthetic</small>
          </span>
          <ArrowUpRight size={14} />
        </div>
        <div className="profile">
          <span className="avatar">AM</span>
          <span>
            Alex Morgan<small>FinOps workspace</small>
          </span>
        </div>
      </div>
    </>
  );
}
export function AppShell({
  screen,
  children,
}: {
  screen?: Screen;
  children: ReactNode;
}) {
  const { scope, review } = useRoute();
  const [search, setSearch] = useState(""),
    [searchOpen, setSearchOpen] = useState(false),
    [menu, setMenu] = useState(false);
  const matches = screens.filter((s) =>
    (
      s.title +
      " " +
      s.group +
      " " +
      s.id.replaceAll("-", " ") +
      " " +
      s.description
    )
      .toLowerCase()
      .includes(search.toLowerCase()),
  );
  const planning = screen?.id.startsWith("budget") || screen?.id === "forecast";
  return (
    <div className="app">
      <a
        className="skip-link"
        href="#main-content"
        onClick={(e) => {
          e.preventDefault();
          document.getElementById("main-content")?.focus();
        }}
      >
        Skip to content
      </a>
      <aside className="sidebar">
        <Navigation screen={screen} />
      </aside>
      <div className="app-body">
        <header className="topbar">
          <Overlay
            title="Navigation"
            open={menu}
            onOpenChange={setMenu}
            trigger={
              <Button className="mobile-menu" aria-label="Open navigation">
                <Menu size={18} />
              </Button>
            }
          >
            <div className="mobile-navigation">
              <Navigation screen={screen} close={() => setMenu(false)} />
            </div>
          </Overlay>
          <button
            className="workspace-select"
            onClick={() => navigate("connection-detail")}
          >
            <span className="workspace-icon">A</span> Acme Group{" "}
            <ChevronDown size={13} />
          </button>
          <span className="top-divider" />
          <label className="scope-select">
            <span className="sr-only">Account scope</span>
            <select
              aria-label="Account scope"
              value={scopedPages.has(screen?.id || "") ? scope : "all"}
              disabled={!scopedPages.has(screen?.id || "")}
              onChange={(e) => setParam("account", e.target.value)}
            >
              <option value="all">
                {scopedPages.has(screen?.id || "")
                  ? "All accounts + org"
                  : "Page-specific scope"}
              </option>
              <option value="production">PRODUCTION only</option>
            </select>
          </label>
          <span className="period">
            {planning ? "Sep 01 – 30, 2026" : "August 2026 / named fixture"}
          </span>
          <span className="currency">USD</span>
          <button
            className="global-search"
            onClick={() => setSearchOpen(true)}
            aria-label="Search pages"
          >
            <Search size={16} />
            <span>Search anything</span>
            <kbd>{screens.length}</kbd>
          </button>
          <span className="avatar small">AM</span>
        </header>
        <div className="demo-toolbar">
          <span>
            <i className="dot amber" /> Interactive design prototype <b>·</b>{" "}
            Synthetic data
          </span>
          <label>
            Review state{" "}
            <select
              aria-label="Review state"
              value={review}
              onChange={(e) => setParam("state", e.target.value)}
            >
              {[
                "ready",
                "loading",
                "empty",
                "partial",
                "stale",
                "error",
                "denied",
                "provisional",
                "final",
              ].map((s) => (
                <option key={s}>{s}</option>
              ))}
            </select>
          </label>
        </div>
        <main id="main-content" tabIndex={-1}>
          {children}
        </main>
        <footer className="app-footer">
          <span>Bridge Data FinOps · Design workbench</span>
          <span>No live Snowflake, AWS, payment or messaging connection</span>
        </footer>
      </div>
      <Overlay
        title="Find a page"
        description={`${screens.length} screens, including detail views and configuration flows.`}
        open={searchOpen}
        onOpenChange={setSearchOpen}
      >
        <label className="search-input command-search">
          <Search size={18} />
          <input
            aria-label="Search all pages"
            autoFocus
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Try dbt, allocation, security…"
          />
        </label>
        <div className="command-results">
          {matches.map((s) => (
            <button
              key={s.id}
              onClick={() => {
                navigate(s.id);
                setSearchOpen(false);
                setSearch("");
              }}
            >
              <span>
                {s.title}
                <small>
                  {s.group} / {s.id}
                </small>
              </span>
              <ArrowUpRight size={15} />
            </button>
          ))}
          {!matches.length && <p>No matching pages.</p>}
        </div>
      </Overlay>
    </div>
  );
}
