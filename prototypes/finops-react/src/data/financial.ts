// Synthetic golden fixture: canonical F-270 amounts multiplied by 100.
// Integer cents are the prototype's financial arithmetic boundary.
export const charges = [
  { service: "Warehouse", cents: 2_000_000, account: "PRODUCTION" },
  { service: "Cloud services", cents: 100_000, account: "PRODUCTION" },
  { service: "Storage", cents: 120_000, account: "PRODUCTION" },
  { service: "Serverless", cents: 180_000, account: "PRODUCTION" },
  { service: "AI / Cortex", cents: 60_000, account: "PRODUCTION" },
  { service: "SPCS", cents: 80_000, account: "PRODUCTION" },
  { service: "Data transfer", cents: 40_000, account: "PRODUCTION" },
  { service: "Application fees", cents: 100_000, account: "PRODUCTION" },
  { service: "Organization support", cents: 50_000, account: null },
  { service: "Organization rebate", cents: -30_000, account: null },
] as const;
export function spend(scope: "all" | "production" = "all") {
  return charges
    .filter((c) => scope === "all" || c.account !== null)
    .reduce((s, c) => s + c.cents, 0);
}
export const usd = (cents: number) =>
  new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(
    cents / 100,
  );
export function allocateCents(amount: number, weights: number[]) {
  if (
    !Number.isSafeInteger(amount) ||
    !weights.length ||
    weights.some((x) => !Number.isFinite(x) || x < 0) ||
    Math.abs(weights.reduce((a, b) => a + b, 0) - 1) > 1e-9
  )
    throw new Error("Invalid allocation input");
  const absolute = Math.abs(amount);
  const exact = weights.map((w) => absolute * w);
  const rounded = exact.map(Math.floor);
  const order = exact
    .map((v, i) => ({ i, remainder: v - rounded[i] }))
    .sort((a, b) => b.remainder - a.remainder || a.i - b.i);
  const remainder = absolute - rounded.reduce((a, b) => a + b, 0);
  for (let n = 0; n < remainder; n++) rounded[order[n].i]++;
  return rounded.map((n) => n * Math.sign(amount));
}
export function allocation(policy: "proportional" | "platform") {
  return policy === "proportional"
    ? [1_200_000, 800_000, 0]
    : [840_000, 560_000, 600_000];
}
export function budget() {
  const limit = 2_800_000,
    actual = 1_500_000,
    completeDays = 15,
    days = 30;
  const burn = actual / completeDays,
    forecast = actual + burn * (days - completeDays);
  return {
    limit,
    actual,
    remaining: limit - actual,
    burn,
    forecast,
    variance: forecast - limit,
  };
}
export function savings(post = 1_800_000) {
  const baseline = 2_000_000,
    baselineUnits = 100,
    postUnits = 120;
  const expected = (baseline / baselineUnits) * postUnits;
  return { baseline, expected, post, realized: expected - post };
}
export function dailySpend(scope: "all" | "production" = "all") {
  const weights = [
    80, 73, 75, 91, 100, 63, 55, 86, 84, 79, 91, 102, 65, 58, 84, 80, 83, 101,
    112, 75, 64, 93, 99, 91, 107, 109, 77, 66, 91, 88, 83,
  ];
  const sum = weights.reduce((a, b) => a + b, 0);
  return allocateCents(
    spend(scope),
    weights.map((n) => n / sum),
  ).map((cents, i) => ({
    day: String(i + 1).padStart(2, "0"),
    cents,
    usd: cents / 100,
  }));
}
export function forecastSeries() {
  return Array.from({ length: 30 }, (_, i) => ({
    day: i + 1,
    actual: i < 15 ? (i + 1) * 1000 : null,
    forecast: i >= 14 ? (i + 1) * 1000 : null,
    budget: 28000,
  }));
}
export function csvCell(value: string) {
  const safe =
    /^[\s\u0000-\u001f]*[=+@-]/.test(value) && !/^[-+]?\d[\d,.]*$/.test(value)
      ? "'" + value
      : value;
  return '"' + safe.replaceAll('"', '""') + '"';
}
