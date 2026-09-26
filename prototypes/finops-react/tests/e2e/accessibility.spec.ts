import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";
test("key compositions have no automated WCAG A/AA violations", async ({
  page,
}) => {
  test.setTimeout(90_000);
  const findings: unknown[] = [];
  for (const route of [
    "home",
    "explorer",
    "budget-new",
    "allocation",
    "warehouse-detail",
    "settings-security",
  ]) {
    await page.goto("/#/" + route);
    await expect(page.locator('[data-ready="true"]')).toBeVisible();
    await page.waitForTimeout(200);
    const result = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa", "wcag21aa", "wcag22aa"])
      .analyze();
    findings.push(
      ...result.violations.map((v) => ({
        route,
        id: v.id,
        impact: v.impact,
        nodes: v.nodes.map((n) => n.target),
      })),
    );
  }
  expect(findings).toEqual([]);
});
