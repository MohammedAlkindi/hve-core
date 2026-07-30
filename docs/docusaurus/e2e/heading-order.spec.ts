// Copyright (c) 2026 Microsoft Corporation. All rights reserved.
// SPDX-License-Identifier: MIT
import { test, expect } from '@playwright/test';
import { SITE_PAGES, visitInvariantPage } from './_helpers/a11yInvariants';

test.describe('Heading-order accessibility regression locks', () => {
  for (const { name, path } of SITE_PAGES) {
    test(`${name} does not skip heading levels`, async ({ page }) => {
      await visitInvariantPage(page, { name, path });

      const levels = await page.$$eval('h1, h2, h3, h4, h5, h6', (headings) =>
        headings.map((heading) => Number(heading.tagName.charAt(1))),
      );

      let previousLevel: number | null = null;
      for (const level of levels) {
        if (previousLevel !== null) {
          expect(
            level,
            `Heading level jumped from ${previousLevel} to ${level} on ${name}`,
          ).toBeLessThanOrEqual(previousLevel + 1);
        }
        previousLevel = level;
      }
    });

    test(`${name} uses real heading tags for prominent in-page and footer titles`, async ({ page }) => {
      await visitInvariantPage(page, { name, path });

      const inPageHeading = page.locator('.theme-doc-markdown h2, .theme-doc-markdown h3, .theme-doc-markdown h4').first();
      if ((await inPageHeading.count()) > 0) {
        await expect(inPageHeading).toBeVisible();
        const inPageTagName = await inPageHeading.evaluate((element) => element.tagName.toLowerCase());
        expect(inPageTagName).toMatch(/^h[1-6]$/);
      }

      const footerTitle = page.locator('.footer__title').first();
      if ((await footerTitle.count()) > 0) {
        await expect(footerTitle).toBeVisible();
        const footerTagName = await footerTitle.evaluate((element) => element.tagName.toLowerCase());
        expect(footerTagName).toMatch(/^h[1-6]$/);
      }
    });
  }
});
