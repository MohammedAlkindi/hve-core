// Copyright (c) 2026 Microsoft Corporation. All rights reserved.
// SPDX-License-Identifier: MIT
import { test, expect } from '@playwright/test';
import { SITE_PAGES, visitInvariantPage, collectPageSnapshot } from './_helpers/a11yInvariants';

// Structural regression guards.
//
// These loop the shared page inventory so any newly added route inherits the
// guards automatically, failing on landmark/heading structural regressions.
// Site-wide axe scanning (the zero-tolerance a11y gate) lives in
// site-crawl.spec.ts over the same page inventory; it is intentionally NOT
// duplicated here.

test.describe('Structural baseline', () => {
  for (const spec of SITE_PAGES) {
    test(`${spec.name} keeps a coherent landmark and heading structure`, async ({ page }) => {
      await visitInvariantPage(page, spec);
      const snapshot = await collectPageSnapshot(page);

      // Exactly one main and one contentinfo landmark per document.
      expect(snapshot.landmarks.main, `${spec.name}: one main landmark`).toBe(1);
      expect(snapshot.landmarks.footer, `${spec.name}: one contentinfo landmark`).toBe(1);

      // Heading outline never skips a level.
      const levels = snapshot.headingLevels;
      expect(levels.length, `${spec.name}: has headings`).toBeGreaterThan(0);
      for (let i = 1; i < levels.length; i += 1) {
        expect(
          levels[i] - levels[i - 1],
          `${spec.name}: no skipped heading level at index ${i} (${levels.join(',')})`,
        ).toBeLessThanOrEqual(1);
      }
    });

    test(`${spec.name} labels footer column lists with their titles and exposes banner text`, async ({ page }) => {
      await visitInvariantPage(page, spec);

      const banner = page.locator('header').first();
      if ((await banner.count()) > 0) {
        await expect(banner).toBeVisible();
        const accessibleName = await banner.evaluate((element) => element.getAttribute('aria-label') ?? element.textContent?.trim() ?? '');
        expect(accessibleName, `${spec.name}: the banner landmark should expose accessible text`).toMatch(/\S/);
      }

      const footerColumns = page.locator('.footer__col');
      if ((await footerColumns.count()) === 0) {
        test.skip(true, `${spec.name}: no footer columns are rendered.`);
        return;
      }

      for (let index = 0; index < await footerColumns.count(); index += 1) {
        const column = footerColumns.nth(index);
        const title = column.locator('.footer__title').first();
        await expect(title).toBeVisible();

        const list = column.locator('ul.footer__items').first();
        await expect(list).toBeVisible();
        const labelledBy = await list.getAttribute('aria-labelledby');
        expect(labelledBy, `${spec.name}: footer list ${index} should be labelled by its heading`).toBeTruthy();

        if (labelledBy) {
          const associatedHeading = page.locator(`#${labelledBy}`).first();
          await expect(associatedHeading).toBeVisible();
        }
      }
    });
  }
});
