import { test, expect } from "@playwright/test";
import screens from "../../src/catalog/screens.json" with { type: "json" };
test("every catalog route renders without page errors", async ({ page }) => {
  test.setTimeout(120_000);
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  for (const s of screens) {
    await page.goto("/#/" + s.id);
    await expect(page.locator('[data-ready="true"]')).toBeVisible();
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(s.title);
    await expect(page.locator(".metric")).toHaveCount(s.metrics.length);
  }
  expect(errors).toEqual([]);
});
test("scope, financial explanation and grouping remain coherent", async ({
  page,
}) => {
  await page.goto("/#/explorer");
  await expect(page.locator('[data-ready="true"]')).toBeVisible();
  await expect(page.locator(".metric-value").first()).toHaveText("$27,000.00");
  await page.getByLabel("Account scope").selectOption("production");
  await expect(page.locator(".metric-value").first()).toHaveText("$26,800.00");
  await page
    .getByRole("button", { name: "Explain Net Snowflake spend", exact: true })
    .click();
  await expect(page.getByRole("dialog")).toContainText("PRODUCTION only");
  await page.keyboard.press("Escape");
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await page.getByRole("button", { name: "Account", exact: true }).click();
  await expect(page.locator("tbody")).toContainText("26,800.00");
  await expect(page.locator("tbody")).not.toContainText("Organization");
});
test("table filters, columns, sort, density and CSV work", async ({ page }) => {
  await page.goto("/#/explorer");
  await page.getByLabel("Search table").fill("storage");
  await expect(page.locator("tbody tr")).toHaveCount(1);
  const download = page.waitForEvent("download");
  await page.getByRole("button", { name: "CSV", exact: true }).click();
  expect((await download).suggestedFilename()).toMatch(/\.csv$/);
  await page.getByLabel("Search table").fill("not-a-real-resource");
  await expect(page.getByText("No matching rows.")).toBeVisible();
  await page.getByRole("button", { name: "Clear search" }).click();
  await page.getByRole("button", { name: "Columns", exact: true }).click();
  await page.getByRole("checkbox", { name: "Basis", exact: true }).uncheck();
  await page.keyboard.press("Escape");
  await expect(page.getByRole("columnheader", { name: "Basis" })).toHaveCount(
    0,
  );
  await page.getByRole("button", { name: "Compact", exact: true }).click();
  await expect(page.locator("table")).toHaveClass("dense");
  await page.getByRole("button", { name: "Net cost USD" }).click();
  await expect(
    page.getByRole("columnheader", { name: "Net cost USD" }),
  ).toHaveAttribute("aria-sort", "ascending");
});
test("all review states preserve their semantics and recover", async ({
  page,
}) => {
  await page.goto("/#/home");
  for (const state of [
    "loading",
    "empty",
    "partial",
    "stale",
    "error",
    "denied",
    "provisional",
    "final",
  ]) {
    await page.getByLabel("Review state").selectOption(state);
    if (state === "denied") {
      await expect(page.getByRole("heading", { level: 1 })).toHaveText(
        "Access required",
      );
      await expect(page.locator(".metric")).toHaveCount(0);
      await expect(page.locator("main")).not.toContainText("$27,000");
    } else if (state === "loading")
      await expect(page.getByLabel("Loading view")).toBeVisible();
    else if (state === "partial")
      await expect(page.locator(".metric-value").first()).toHaveText("—");
    else if (state === "provisional" || state === "final")
      await expect(page.locator(".metric").first()).toContainText(
        state.toUpperCase(),
      );
  }
  await page.getByLabel("Review state").selectOption("error");
  await page.getByRole("button", { name: "Retry", exact: true }).click();
  await expect(page.locator(".metric-value").first()).toHaveText("$27,000.00");
});
test("forms validate, persist locally and never send network mutations", async ({
  page,
}) => {
  const mutations: string[] = [];
  page.on("request", (r) => {
    if (["POST", "PUT", "PATCH", "DELETE"].includes(r.method()))
      mutations.push(r.url());
  });
  await page.goto("/#/budget-new");
  await page
    .getByRole("button", { name: "Save budget draft", exact: true })
    .click();
  await expect(page.getByText("Draft saved locally.")).toHaveCount(0);
  for (const label of [
    "Budget name",
    "Amount USD",
    "Owner",
    "Threshold percent",
  ])
    await page
      .getByLabel(label, { exact: false })
      .fill(
        label === "Amount USD"
          ? "28000"
          : label === "Threshold percent"
            ? "80"
            : "Demo",
      );
  await page
    .getByRole("button", { name: "Save budget draft", exact: true })
    .click();
  await expect(page.getByRole("status")).toContainText("Draft saved locally");
  await page.reload();
  await expect(page.getByLabel("Budget name", { exact: false })).toHaveValue(
    "Demo",
  );
  expect(mutations).toEqual([]);
});
test("allocation alternative conserves amount; incident acknowledgement is local", async ({
  page,
}) => {
  await page.goto("/#/allocation");
  await page.getByRole("button", { name: "Platform owns idle" }).click();
  await expect(page.locator(".allocation-targets")).toContainText("$8,400.00");
  await expect(page.locator(".allocation-targets")).toContainText("$6,000.00");
  await page.goto("/#/incident");
  await page.getByRole("button", { name: "Acknowledge demo incident" }).click();
  await expect(page.locator(".incident-top")).toContainText("ACKNOWLEDGED");
});
test("page search and browser Back retain scoped URL", async ({ page }) => {
  await page.goto("/#/explorer?account=production");
  await page.getByRole("button", { name: "Search pages" }).click();
  await page.getByLabel("Search all pages").fill("dbt project");
  await page.getByRole("button", { name: /finance_daily/ }).click();
  await expect(page).toHaveURL(/dbt-project\?account=production/);
  await page.goBack();
  await expect(page).toHaveURL(/explorer\?account=production/);
  await expect(page.locator(".metric-value").first()).toHaveText("$26,800.00");
});
test("mobile navigation, dialog focus and bounded page width", async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 844 });
  for (const id of [
    "home",
    "explorer",
    "allocation",
    "budget-detail",
    "query-executions",
    "settings-security",
  ]) {
    await page.goto("/#/" + id);
    await expect(page.locator('[data-ready="true"]')).toBeVisible();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth + 1,
      ),
      id,
    ).toBeTruthy();
  }
  await page.getByRole("button", { name: "Open navigation" }).click();
  await expect(page.getByRole("dialog")).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(
    page.getByRole("button", { name: "Open navigation" }),
  ).toBeFocused();
  await page.screenshot({
    path: "test-results/mobile-settings.png",
    fullPage: true,
  });
  await page.setViewportSize({ width: 720, height: 550 });
  await page.goto("/#/warehouse-detail");
  await expect(page.locator('[data-ready="true"]')).toBeVisible();
  const lines = await page.locator(".metric-value").first().evaluate((el) => {
    const range = document.createRange();
    range.selectNodeContents(el);
    return range.getClientRects().length;
  });
  expect(lines, "Financial values must not split across lines at tablet/reflow width").toBe(1);
});
