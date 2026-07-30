// Copyright (c) 2026 Microsoft Corporation. All rights reserved.
// SPDX-License-Identifier: MIT
import { test, expect, type Page } from '@playwright/test';

// WCAG 1.4.4 Resize Text: content must stay usable when text is scaled to 200%.
//
// Browser page zoom scales the CSS pixel against the device pixel, so a 1280
// device-pixel window at 200% zoom lays out as a 640 CSS pixel viewport at a
// device scale factor of 2. That equivalence makes real browser zoom
// reproducible from Playwright context options alone, without the CDP
// text-scale emulation that never reproduced the reported symptom.
//
// The reported defect was the navbar search placeholder being clipped to
// "Sear" at 200%: the field narrows while the Ctrl+K badges inside it do not
// yield, leaving less room for the placeholder than the placeholder needs.
const ZOOM_LEVELS = [
  { label: '100%', width: 1280, height: 768, deviceScaleFactor: 1 },
  { label: '150%', width: 853, height: 512, deviceScaleFactor: 1.5 },
  { label: '200%', width: 640, height: 384, deviceScaleFactor: 2 },
  { label: '250%', width: 512, height: 307, deviceScaleFactor: 2.5 },
];

interface PlaceholderFit {
  present: boolean;
  collapsed: boolean;
  requiredWidth: number;
  usableWidth: number;
}

// Measures the space actually available for placeholder text against the width
// that text needs. A badge rendered inside the field reduces the available
// space, so the badge edge is the right boundary whenever one is present.
async function measurePlaceholderFit(page: Page): Promise<PlaceholderFit> {
  return page.evaluate(() => {
    const input = document.querySelector<HTMLInputElement>('input.navbar__search-input');
    if (!input) {
      return { present: false, collapsed: false, requiredWidth: 0, usableWidth: 0 };
    }

    // Below the theme's small breakpoint the field deliberately collapses to an
    // icon until it receives focus, which is a legitimate responsive pattern
    // rather than clipping. Focusing first measures the state a user types into.
    input.focus();

    const rect = input.getBoundingClientRect();
    const computed = window.getComputedStyle(input);

    const probe = document.createElement('span');
    probe.style.cssText = `position:absolute;visibility:hidden;white-space:pre;font:${computed.font}`;
    probe.textContent = input.getAttribute('placeholder') ?? '';
    document.body.appendChild(probe);
    const requiredWidth = probe.getBoundingClientRect().width;
    probe.remove();

    const badgeEdges = Array.from(document.querySelectorAll('.navbar__search kbd'))
      .map((badge) => badge.getBoundingClientRect())
      .filter((badge) => badge.width > 0)
      .map((badge) => badge.left);

    const paddingLeft = Number.parseFloat(computed.paddingLeft) || 0;
    const paddingRight = Number.parseFloat(computed.paddingRight) || 0;
    const rightBoundary = badgeEdges.length > 0
      ? Math.min(Math.min(...badgeEdges), rect.right - paddingRight)
      : rect.right - paddingRight;

    return {
      present: true,
      collapsed: rect.width < 48,
      requiredWidth,
      usableWidth: rightBoundary - (rect.left + paddingLeft),
    };
  });
}

test.describe('Resize text to 200% browser zoom (WCAG 1.4.4)', () => {
  for (const level of ZOOM_LEVELS) {
    test(`navbar search placeholder is not clipped at ${level.label} browser zoom`, async ({ browser }) => {
      const context = await browser.newContext({
        viewport: { width: level.width, height: level.height },
        deviceScaleFactor: level.deviceScaleFactor,
      });
      const page = await context.newPage();

      try {
        await page.goto('/hve-core/', { waitUntil: 'domcontentloaded' });
        await page.waitForFunction(
          () => document.documentElement.dataset.hasHydrated === 'true',
          undefined,
          { timeout: 30000 },
        );

        const fit = await measurePlaceholderFit(page);
        expect(fit.present, 'the navbar search input should render').toBe(true);
        expect(fit.collapsed, `the search field should expand on focus at ${level.label}`).toBe(false);
        expect(
          Math.round(fit.usableWidth),
          `at ${level.label} the placeholder needs ${Math.round(fit.requiredWidth)} CSS px but only ${Math.round(fit.usableWidth)} CSS px is available`,
        ).toBeGreaterThanOrEqual(Math.round(fit.requiredWidth));

        // SC 1.4.4 also forbids losing content to a second scroll axis.
        const horizontalScroll = await page.evaluate(
          () => document.documentElement.scrollWidth > document.documentElement.clientWidth + 1,
        );
        expect(horizontalScroll, `${level.label} should not introduce horizontal scrolling`).toBe(false);
      } finally {
        await context.close();
      }
    });
  }
});
