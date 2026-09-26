import {
  AreaChart,
  Area,
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  ReferenceLine,
} from "recharts";
import { Panel, Button, Overlay } from "./ui";
import { DataTable } from "./DataTable";
import {
  dailySpend,
  forecastSeries,
  usd,
  charges,
  spend,
} from "../data/financial";
import type { Scope } from "../types";
const colors = [
  "#d97706",
  "#3b82f6",
  "#64748b",
  "#8b5cf6",
  "#db2777",
  "#059669",
  "#0891b2",
  "#78716c",
  "#52525b",
  "#9ca3af",
];
const axis = {
  tick: { fontSize: 11, fill: "#737373" },
  axisLine: false,
  tickLine: false,
};
export function SpendChart({ scope }: { scope: Scope }) {
  const data = dailySpend(scope);
  return (
    <Panel
      title="Daily spend"
      subtitle="August 2026 · net USD · complete synthetic period"
      action={
        <Overlay
          title="Daily spend data"
          wide
          trigger={<Button variant="ghost">View data</Button>}
        >
          <DataTable
            columns={["Day UTC", "Net USD"]}
            rows={data.map((d) => ["Aug " + d.day, (d.cents / 100).toFixed(2)])}
          />
        </Overlay>
      }
    >
      <div className="chart-total">
        {usd(spend(scope))}
        <span>across 31 complete days</span>
      </div>
      <div
        className="chart"
        role="img"
        aria-label="August daily net spend; use View data for exact amounts"
      >
        <ResponsiveContainer
          width="100%"
          height="100%"
          initialDimension={{ width: 600, height: 255 }}
        >
          <AreaChart
            data={data}
            margin={{ left: 0, right: 10, top: 10, bottom: 0 }}
          >
            <defs>
              <linearGradient id="spend-fill" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="#f59e0b" stopOpacity={0.19} />
                <stop offset="100%" stopColor="#f59e0b" stopOpacity={0} />
              </linearGradient>
            </defs>
            <CartesianGrid vertical={false} stroke="#ededed" />
            <XAxis
              {...axis}
              dataKey="day"
              tickFormatter={(v) => "Aug " + v}
              minTickGap={38}
            />
            <YAxis
              {...axis}
              width={48}
              tickFormatter={(v) => "$" + Math.round(v)}
            />
            <Tooltip
              formatter={(v) => ["$" + Number(v).toFixed(2), "Net spend"]}
              contentStyle={{
                borderRadius: 10,
                border: "1px solid #e5e5e5",
                fontSize: 12,
              }}
            />
            <Area
              type="monotone"
              dataKey="usd"
              stroke="#d97706"
              strokeWidth={2.5}
              fill="url(#spend-fill)"
              isAnimationActive={false}
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>
      <div className="chart-legend">
        <i className="dot amber" /> Signed net spend{" "}
        <span>Comparison unavailable · July is outside this fixture</span>
      </div>
    </Panel>
  );
}
export function ServiceBreakdown({ scope }: { scope: Scope }) {
  const data = charges.filter((c) => scope === "all" || c.account !== null);
  return (
    <Panel title="Where the money goes" subtitle="Billed charges · USD">
      <div className="breakdown">
        {data.map((c, i) => (
          <div className="breakdown-row" key={c.service}>
            <div>
              <span>
                <i className="dot" style={{ background: colors[i] }} />
                {c.service}
              </span>
              <strong>{usd(c.cents)}</strong>
            </div>
            <div className="bar-track">
              <span
                style={{
                  width: (Math.abs(c.cents) / 2_000_000) * 100 + "%",
                  background: colors[i],
                }}
              />
            </div>
          </div>
        ))}
      </div>
      <p className="panel-footnote">
        Rebates are negative adjustments. Bar length shows magnitude; signed
        values remain authoritative.
      </p>
    </Panel>
  );
}
export function BudgetChart() {
  const data = forecastSeries();
  return (
    <Panel
      title="The path to month end"
      subtitle="September 2026 · actual through Sep 15 · USD"
      action={
        <Overlay
          title="Forecast data"
          wide
          trigger={<Button variant="ghost">View data</Button>}
        >
          <DataTable
            columns={["Day UTC", "Actual USD", "Forecast USD", "Budget USD"]}
            rows={data.map((d) => [
              String(d.day),
              d.actual?.toFixed(2) || "—",
              d.forecast?.toFixed(2) || "—",
              "28000.00",
            ])}
          />
        </Overlay>
      }
    >
      <div className="chart">
        <ResponsiveContainer
          width="100%"
          height="100%"
          initialDimension={{ width: 600, height: 255 }}
        >
          <LineChart data={data}>
            <CartesianGrid vertical={false} stroke="#ededed" />
            <XAxis dataKey="day" {...axis} />
            <YAxis
              {...axis}
              width={45}
              tickFormatter={(v) => "$" + v / 1000 + "k"}
            />
            <Tooltip />
            <ReferenceLine y={28000} stroke="#525252" strokeDasharray="3 4" />
            <Line
              type="linear"
              dataKey="actual"
              stroke="#d97706"
              strokeWidth={3}
              dot={false}
              isAnimationActive={false}
            />
            <Line
              type="linear"
              dataKey="forecast"
              stroke="#d97706"
              strokeDasharray="5 5"
              strokeWidth={2}
              dot={false}
              isAnimationActive={false}
            />
          </LineChart>
        </ResponsiveContainer>
      </div>
      <div className="chart-legend">
        <i className="dot amber" /> Actual{" "}
        <span>Dashed: run-rate estimate · grey: $28,000 budget</span>
      </div>
      <p className="panel-footnote">
        15 complete days. No calibrated prediction interval. Forecast is an
        estimate.
      </p>
    </Panel>
  );
}
