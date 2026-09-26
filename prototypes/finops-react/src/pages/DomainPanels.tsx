import { useState } from "react";
import { ArrowRight, Check, Clock, Info, ShieldCheck } from "lucide-react";
import type { Screen, Scope } from "../types";
import {
  Button,
  Panel,
  LinkCard,
  Badge,
  LocalForm,
  Overlay,
} from "../components/ui";
import {
  SpendChart,
  ServiceBreakdown,
  BudgetChart,
} from "../components/Charts";
import { DataTable } from "../components/DataTable";
import { navigate } from "../app/navigation";
import { allocation, usd, savings } from "../data/financial";

export function DomainPanels({
  screen,
  scope,
}: {
  screen: Screen;
  scope: Scope;
}) {
  const [policy, setPolicy] = useState<"proportional" | "platform">(
    "proportional",
  );
  const [selectedNode, setSelectedNode] = useState<string | null>(null),
    [step, setStep] = useState(0),
    [ack, setAck] = useState(false);
  const p = screen;
  const values = allocation(policy);
  if (p.kind === "home")
    return (
      <>
        <div className="analytics-grid">
          <SpendChart scope={scope} />
          <ServiceBreakdown scope={scope} />
        </div>
        <div className="three-columns">
          <LinkCard
            title="One control needs review"
            body="Investigate the $100 reconciliation scenario."
            onClick={() => navigate("reconciliation-detail")}
          />
          <LinkCard
            title="Make ownership explicit"
            body="Inspect the conserved warehouse allocation book."
            onClick={() => navigate("allocation")}
          />
          <LinkCard
            title="An opportunity worth reviewing"
            body="$8,000 estimated · separate savings study."
            onClick={() => navigate("insight-detail")}
          />
        </div>
      </>
    );
  if (p.kind === "explorer")
    return (
      <div className="analytics-grid">
        <SpendChart scope={scope} />
        <ServiceBreakdown scope={scope} />
      </div>
    );
  if (p.kind === "budget")
    return (
      <div className="analytics-grid">
        <BudgetChart />
        <Panel
          title="At risk, with time to act"
          subtitle="Forecast exceeds budget by 7.14%"
        >
          <div className="budget-ring">
            <div>
              <strong>
                53.6<span>%</span>
              </strong>
              <small>of budget spent</small>
            </div>
          </div>
          <div className="two-stat">
            <span>
              Remaining<strong>$13,000</strong>
            </span>
            <span>
              Daily burn<strong>$1,000</strong>
            </span>
          </div>
          <Button onClick={() => navigate("forecast")}>
            Inspect forecast method <ArrowRight size={14} />
          </Button>
        </Panel>
      </div>
    );
  if (p.kind === "allocation")
    return (
      <Panel
        title="Every dollar has a destination"
        subtitle="Teams book · warehouse compute · August 2026"
      >
        <div
          className="segmented"
          role="group"
          aria-label="Idle allocation policy"
        >
          <button
            aria-pressed={policy === "proportional"}
            onClick={() => setPolicy("proportional")}
          >
            Proportional idle
          </button>
          <button
            aria-pressed={policy === "platform"}
            onClick={() => setPolicy("platform")}
          >
            Platform owns idle
          </button>
        </div>
        <div className="allocation-flow">
          <div className="flow-source">
            <small>Source charge</small>
            <strong>$20,000</strong>
            <span>Warehouse compute</span>
          </div>
          <ArrowRight size={24} />
          <div className="allocation-targets">
            {["Finance", "Marketing", "Platform"].map((label, i) => (
              <div key={label}>
                <span>
                  <i
                    className="dot"
                    style={{ background: ["#d97706", "#8b5cf6", "#64748b"][i] }}
                  />
                  {label}
                </span>
                <strong>{usd(values[i])}</strong>
              </div>
            ))}
          </div>
          <Badge tone="success">Conserved: $20,000</Badge>
        </div>
        <p className="panel-footnote">
          This switch is a policy simulation. The published table below remains
          Teams v1 (proportional). No new version is issued.
        </p>
      </Panel>
    );
  if (p.kind === "warehouse")
    return (
      <Panel
        title="Billed compute, explained"
        subtitle="Classic warehouse · cloud services excluded"
      >
        <div className="composition-value">
          $20,000<span> total compute</span>
        </div>
        <div className="composition-bar">
          <div style={{ width: "70%" }}>Query compute · 70%</div>
          <div style={{ width: "30%" }}>Idle · 30%</div>
        </div>
        <div className="two-stat">
          <span>
            Attributed query compute<strong>$14,000</strong>
          </span>
          <span>
            Classic idle compute<strong>$6,000</strong>
          </span>
        </div>
        <div className="inline-actions">
          <Button onClick={() => navigate("queries")}>
            Explore query costs <ArrowRight size={14} />
          </Button>
          <Button onClick={() => navigate("workloads")}>View workloads</Button>
        </div>
      </Panel>
    );
  if (p.kind === "savings") {
    const s = savings();
    return (
      <Panel
        title="A transparent savings bridge"
        subtitle="Independent normalized study · USD"
      >
        <div className="savings-bridge">
          {[
            ["Baseline", s.baseline, "100 units"],
            ["Normalized", s.expected, "120 units at baseline rate"],
            ["Observed", s.post, "120 post-change units"],
            ["Verified savings", s.realized, "Expected − observed"],
          ].map(([label, value, hint], i) => (
            <div key={String(label)}>
              <span
                className="bridge-bar"
                style={{
                  height: 60 + Number(value) / 15000,
                  background:
                    i === 3 ? "#d1fae5" : i === 1 ? "#fef3c7" : "#f5f5f5",
                }}
              >
                <strong>{usd(Number(value))}</strong>
              </span>
              <b>{label}</b>
              <small>{hint}</small>
            </div>
          ))}
        </div>
        <Button onClick={() => navigate("savings-detail")}>
          Inspect verification <ArrowRight size={14} />
        </Button>
      </Panel>
    );
  }
  if (p.kind === "pipeline")
    return (
      <Panel
        title="Verified execution lineage"
        subtitle="Select a node to inspect its cost and evidence"
      >
        <div
          className={
            "pipeline-graph " +
            (p.id === "dbt-invocation" ? "parallel-dbt" : "")
          }
        >
          {p.rows.map((row, i) => (
            <div className="graph-item" key={row[0]}>
              {i > 0 && p.id !== "dbt-invocation" && <ArrowRight size={20} />}
              <button
                className={
                  "graph-node " + (selectedNode === row[0] ? "selected" : "")
                }
                onClick={() => setSelectedNode(row[0])}
              >
                <GitNode />
                <strong>{row[0]}</strong>
                <span>
                  {row[1]} · {row[3]}
                </span>
              </button>
            </div>
          ))}
        </div>
        {selectedNode && (
          <div className="notice">
            <Info size={16} />
            <span>
              {selectedNode}: verified synthetic parent/node evidence. Cost
              belongs to the parent aggregate.
            </span>
          </div>
        )}
        <p className="panel-footnote">
          {p.id === "dbt-invocation"
            ? "Parallel inputs: fct_sales and dim_customer. Both precede agg_revenue. "
            : ""}
          {p.panels[0].body}
        </p>
      </Panel>
    );
  if (p.kind === "execution")
    return (
      <Panel
        title={
          p.id === "ai-execution"
            ? "Cost layers, not duplicate charges"
            : "Execution evidence"
        }
        subtitle="Representative execution · separate from monthly aggregate"
      >
        <div className="execution-track">
          {p.rows.map((row, i) => (
            <div key={row[0]} style={{ flex: i + 1 }}>
              <small>{row[0]}</small>
              <strong>{row[1]}</strong>
              <span>{row[2]}</span>
            </div>
          ))}
        </div>
        {p.id === "query-detail" && (
          <>
            <pre className="sql">
              <code>
                SELECT region, SUM(amount){"\n"}FROM analytics.sales{"\n"}WHERE
                customer_id = ?{"\n"}GROUP BY region;
              </code>
            </pre>
            <Badge>
              Sanitized SQL · historical operator profile unavailable
            </Badge>
          </>
        )}
        <p className="panel-footnote">{p.note}</p>
      </Panel>
    );
  if (p.kind === "wizard")
    return (
      <Panel
        title="Your connection checklist"
        subtitle="No real connection is established"
      >
        <div className="wizard-steps">
          {[
            "Organization",
            "WIF trust",
            "Capabilities",
            "History",
            "First value",
          ].map((s, i) => (
            <button
              key={s}
              className={step === i ? "current" : ""}
              onClick={() => setStep(i)}
            >
              <span>{i < step ? <Check size={15} /> : i + 1}</span>
              {s}
            </button>
          ))}
        </div>
        <div className="wizard-content">
          <Badge>Step {step + 1} of 5 · demonstration</Badge>
          <h3>{p.rows[step][0]}</h3>
          <p>
            Required evidence: {p.rows[step][3]}.{" "}
            {p.panels[step === 4 ? 1 : 0].body}
          </p>
          {step === 1 && (
            <pre className="sql">
              <code>
                Identity: temporary AWS workload identity{"\n"}Account:
                &lt;authorized-account-locator&gt;{"\n"}Authentication:
                WORKLOAD_IDENTITY{"\n"}Trust and grants: use canonical
                connectivity contract
              </code>
            </pre>
          )}
          <Button
            variant="primary"
            onClick={() => setStep(Math.min(4, step + 1))}
            disabled={step === 4}
          >
            Continue demo <ArrowRight size={14} />
          </Button>
        </div>
      </Panel>
    );
  if (p.kind === "incident")
    return (
      <Panel
        title="One incident, a continuous story"
        subtitle="Synthetic episode · daily evaluation"
      >
        <div className="incident-top">
          <Badge tone={ack ? "neutral" : "warning"}>
            {ack ? "ACKNOWLEDGED" : "OPEN"}
          </Badge>
          <Button onClick={() => setAck(!ack)}>
            {ack ? "Reset demo incident" : "Acknowledge demo incident"}
          </Button>
        </div>
        <ol className="timeline">
          {p.rows.map((r, i) => (
            <li key={r[0]}>
              <span className="timeline-dot">{i + 1}</span>
              <div>
                <strong>
                  {r[3]} <span>{r[0]}</span>
                </strong>
                <p>
                  {r[1]} USD · {r[2]} coverage
                </p>
              </div>
            </li>
          ))}
        </ol>
        {ack && (
          <p className="success-text" role="status">
            Acknowledged locally. No notification sent.
          </p>
        )}
      </Panel>
    );
  if (p.kind === "statement")
    return (
      <Panel
        title="Internal cost statement"
        subtitle="Issued document preview · closed version"
      >
        <div className="statement-brand">
          <span className="brand-mark">b</span>
          <span>Bridge Data FinOps</span>
          <Badge tone="success">RECONCILED</Badge>
        </div>
        <div className="statement-meta">
          <div>
            <small>Issued to</small>
            <h3>Finance</h3>
            <p>Teams book · August 2026</p>
          </div>
          <div>
            <small>Statement</small>
            <h3>ST-2026-08-FIN</h3>
            <p>Issued Sep 02 · USD · CLOSED</p>
          </div>
        </div>
        <div className="statement-total">
          <span>Amount allocated</span>
          <strong>$12,000.00</strong>
        </div>
        <p>
          Owned query compute $8,400.00 + allocated idle $3,600.00. This is an
          internal cost statement, not a sales invoice.
        </p>
        <Button onClick={() => window.print()}>
          Print / save PDF with browser
        </Button>
      </Panel>
    );
  if (p.kind === "auth")
    return (
      <Panel title={p.title} subtitle="Identity experience preview">
        <div className="auth-art">
          <ShieldCheck size={48} />
          <h3>Clarity starts with secure access.</h3>
          <p>
            Production identity is provided by Cognito and your organization's
            identity provider. This prototype collects no passwords or MFA
            codes.
          </p>
        </div>
        <Button
          variant="primary"
          onClick={() => navigate(p.id === "sign-in" ? "mfa" : "home")}
        >
          {p.action}
          <ArrowRight size={15} />
        </Button>
      </Panel>
    );
  if (p.kind === "editor")
    return (
      <div className="editor-grid">
        <Panel
          title="Configuration"
          subtitle="Local draft · no production mutation"
        >
          <LocalForm id={p.id} fields={p.form} action={p.action} />
        </Panel>
        <Panel
          title="Preview & guardrails"
          subtitle="Keep the decision reviewable"
        >
          {p.panels.map((x) => (
            <div className="guardrail" key={x.title}>
              <ShieldCheck size={18} />
              <div>
                <h3>{x.title}</h3>
                <p>{x.body}</p>
              </div>
            </div>
          ))}
          <div className="notice">
            <Info size={16} />
            <span>{p.note}</span>
          </div>
        </Panel>
      </div>
    );
  if (p.kind === "review")
    return (
      <Panel
        title="Review the evidence"
        subtitle="Read-only preview · approvals are simulated"
      >
        <div className="review-checks">
          {p.panels.map((x, i) => (
            <div key={x.title}>
              <span className="review-number">0{i + 1}</span>
              <h3>{x.title}</h3>
              <p>{x.body}</p>
            </div>
          ))}
        </div>
        <Overlay
          title="Review confirmation"
          trigger={<Button variant="primary">{p.action}</Button>}
        >
          <p>{p.note}</p>
          <LocalForm
            id={p.id}
            fields={["Review reason", "Reviewer role"]}
            action="Record local review"
          />
        </Overlay>
      </Panel>
    );
  return (
    <div className="context-panels">
      {p.panels.map((panel, i) => (
        <Panel title={panel.title} key={panel.title}>
          <div className="context-icon">
            {i === 0 ? <Info size={20} /> : <ShieldCheck size={20} />}
          </div>
          <p className="context-body">{panel.body}</p>
        </Panel>
      ))}
    </div>
  );
}
function GitNode() {
  return (
    <span className="node-icon">
      <Clock size={15} />
    </span>
  );
}
