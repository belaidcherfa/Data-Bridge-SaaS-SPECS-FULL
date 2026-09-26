import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";
import {
  charges,
  spend,
  allocateCents,
  allocation,
  budget,
  savings,
  dailySpend,
  forecastSeries,
  csvCell,
} from "../src/data/financial.ts";
const screens = JSON.parse(
  readFileSync(new URL("../src/catalog/screens.json", import.meta.url), "utf8"),
);
const metrics = JSON.parse(
  readFileSync(new URL("../src/catalog/metrics.json", import.meta.url), "utf8"),
);
test("ledger conserves net, account and organization charges", () => {
  assert.equal(spend(), 2_700_000);
  assert.equal(spend("production"), 2_680_000);
  assert.equal(
    charges.filter((c) => c.account === null).reduce((a, c) => a + c.cents, 0),
    20_000,
  );
  assert.equal(2_000_000, 1_400_000 + 600_000);
});
test("signed minor-unit allocation is deterministic and conserved", () => {
  assert.deepEqual(allocateCents(100, [1 / 3, 1 / 3, 1 / 3]), [34, 33, 33]);
  assert.deepEqual(allocateCents(-100, [1 / 3, 1 / 3, 1 / 3]), [-34, -33, -33]);
  assert.deepEqual(allocateCents(0, [0.6, 0.4]), [0, 0]);
  assert.throws(() => allocateCents(100, [0.5, 0.2]));
  assert.throws(() => allocateCents(1.2, [1]));
  for (let n = -101; n <= 101; n++)
    assert.equal(
      allocateCents(n, [0.17, 0.33, 0.5]).reduce((a, b) => a + b, 0),
      n,
    );
});
test("allocation books and policies never become additional spend", () => {
  assert.deepEqual(allocation("proportional"), [1_200_000, 800_000, 0]);
  assert.deepEqual(allocation("platform"), [840_000, 560_000, 600_000]);
  for (const p of ["proportional", "platform"] as const)
    assert.equal(
      allocation(p).reduce((a, b) => a + b, 0),
      2_000_000,
    );
});
test("budget and forecast preserve units and actual-estimate boundary", () => {
  assert.deepEqual(budget(), {
    limit: 2_800_000,
    actual: 1_500_000,
    remaining: 1_300_000,
    burn: 100_000,
    forecast: 3_000_000,
    variance: 200_000,
  });
  const data = forecastSeries();
  assert.equal(data[14].actual, 15000);
  assert.equal(data[15].actual, null);
  assert.equal(data[29].forecast, 30000);
});
test("normalized savings keeps adverse outcomes negative", () => {
  assert.equal(savings().realized, 600_000);
  assert.equal(savings(2_600_000).realized, -200_000);
  assert.equal(savings().expected, 2_400_000);
});
test("chart daily amounts reconcile to the selected ledger", () => {
  for (const scope of ["all", "production"] as const) {
    const d = dailySpend(scope);
    assert.equal(d.length, 31);
    assert.equal(
      d.reduce((a, b) => a + b.cents, 0),
      spend(scope),
    );
    assert.ok(d.every((x) => Number.isSafeInteger(x.cents)));
  }
});
test("CSV escapes quoted values and spreadsheet formulas", () => {
  assert.equal(csvCell('=WEBSERVICE("x")'), '"\'=WEBSERVICE(""x"")"');
  assert.equal(csvCell("-300.00"), '"-300.00"');
  assert.equal(csvCell(" @SUM(A1)"), '"\' @SUM(A1)"');
  assert.equal(csvCell("a,b"), '"a,b"');
});
test("screen routes, parents, metric keys and detailed documents are complete", () => {
  const ids = new Set(screens.map((s: any) => s.id));
  assert.equal(ids.size, screens.length);
  for (const s of screens) {
    assert.ok(s.panels.length >= 2, s.id);
    if (s.parent) assert.ok(ids.has(s.parent));
    for (const c of s.children) assert.ok(ids.has(c));
    for (const m of s.metrics) assert.ok(metrics[m], s.id + ":" + m);
    const doc = new URL(
      "../../../docs/21-ui-ux/" + s.document,
      import.meta.url,
    );
    assert.ok(existsSync(doc));
    const text = readFileSync(doc, "utf8");
    assert.ok(text.includes("## " + s.id + " —"));
    assert.ok(text.includes("Permission-denied state"));
  }
});
test("metric display oracles agree with canonical financial fixtures", () => {
  assert.equal(metrics.spend.cents, spend());
  assert.equal(metrics.accountcost.cents, spend("production"));
  assert.equal(metrics.forecast.cents, budget().forecast);
  assert.equal(metrics.verifiedsavings.cents, savings().realized);
  assert.equal(
    metrics.financealloc.cents + metrics.marketingalloc.cents,
    metrics.warehouse.cents,
  );
  assert.equal(
    metrics.recondelta.cents,
    metrics.ledgercompare.cents - metrics.invoicecompare.cents,
  );
});
