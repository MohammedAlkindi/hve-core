// Copyright (c) 2026 Microsoft Corporation. All rights reserved.
// SPDX-License-Identifier: MIT
import { test, expect, type Page } from '@playwright/test';

// Walks the navbar search dropdown with ArrowDown/ArrowUp and reports, at each
// step, the aria-activedescendant and which option carries the upstream visual
// "cursor" highlight. Purpose: reproduce "the dropdown opens but up/down arrows
// no longer navigate the list".

async function activeState(page: Page) {
  return page.evaluate(() => {
    const input = document.querySelector('input.navbar__search-input') as HTMLInputElement | null;
    const lb = document.querySelector('[role="listbox"]');
    const opts = lb ? Array.from(lb.querySelectorAll('[role="option"]')) : [];
    const highlighted = lb ? lb.querySelector('[class*="cursor"]') : null;
    return {
      activeDescendant: input?.getAttribute('aria-activedescendant') ?? null,
      optionCount: opts.length,
      highlightedText: highlighted ? (highlighted.textContent || '').trim().slice(0, 40) : null,
      focusIsInput: document.activeElement === input,
      focusClass: document.activeElement ? (document.activeElement.className || document.activeElement.tagName) : null,
    };
  });
}

test('navbar search: ArrowDown/ArrowUp navigate the dropdown list', async ({ page }) => {
  await page.goto('/hve-core/docs/getting-started/');
  await page.waitForLoadState('domcontentloaded');

  const input = page.locator('input.navbar__search-input').first();
  await input.click();
  await input.fill('agent');
  await page.locator('[role="listbox"]').first().waitFor({ state: 'visible', timeout: 15000 });

  const steps: Array<Record<string, unknown>> = [];
  steps.push({ key: 'start', ...(await activeState(page)) });

  for (let n = 0; n < 5; n += 1) {
    await input.press('ArrowDown');
    await page.waitForTimeout(120);
    steps.push({ key: 'ArrowDown#' + (n + 1), ...(await activeState(page)) });
  }
  for (let n = 0; n < 2; n += 1) {
    await input.press('ArrowUp');
    await page.waitForTimeout(120);
    steps.push({ key: 'ArrowUp#' + (n + 1), ...(await activeState(page)) });
  }

  // eslint-disable-next-line no-console
  console.log('ARROW WALK:\n' + steps.map((s) => JSON.stringify(s)).join('\n'));

  const downs = steps.filter((s) => String(s.key).startsWith('ArrowDown'));

  // User-visible criteria for "arrows navigate the list":
  // 1. Focus must stay on the combobox input (baseline bug: it fell to <body>).
  const focusStayed = downs.every((s) => s.focusIsInput === true);
  // 2. The visible highlight must move through options (baseline bug: it stuck).
  const highlightMoved = new Set(downs.map((s) => s.highlightedText).filter(Boolean)).size >= 2;

  expect(focusStayed, 'focus must stay on the search input while arrowing (not fall to <body>)').toBe(true);
  expect(highlightMoved, 'the visible option highlight must move as ArrowDown is pressed').toBe(true);
});
