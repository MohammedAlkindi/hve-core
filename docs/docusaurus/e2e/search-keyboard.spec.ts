// Copyright (c) 2026 Microsoft Corporation. All rights reserved.
// SPDX-License-Identifier: MIT
import { test, expect, type Page } from '@playwright/test';
import { openSearchWidget, waitForHydration } from './_helpers/a11yInvariants';

async function openNavbarSearch(page: Page) {
  await page.goto('/hve-core/docs/getting-started/');
  await page.waitForLoadState('domcontentloaded');
  await waitForHydration(page);

  // Gate on upstream attachment rather than role="combobox", which this
  // repository's swizzle supplies at rest.
  const input = await openSearchWidget(page);
  await input.fill('agent');
  await page.locator('[role="listbox"]').first().waitFor({ state: 'visible', timeout: 30000 });

  return input;
}

async function getFooterId(page: Page) {
  const footer = page.locator('[role="listbox"] [class*="hitFooter"] a').first();
  await footer.waitFor({ state: 'attached' });
  return footer.getAttribute('id');
}

async function getResultOptionIds(page: Page) {
  return page.$$eval('[role="listbox"] [role="option"]', (els) =>
    els
      .filter((el) => !el.closest('[class*="hitFooter"]'))
      .map((el) => el.id),
  );
}

// Arrow down until the active descendant is the given id, or the cap is hit.
async function arrowDownUntilActive(page: Page, input: ReturnType<Page['locator']>, targetId: string, cap: number) {
  for (let index = 0; index < cap; index += 1) {
    if ((await input.getAttribute('aria-activedescendant')) === targetId) {
      return true;
    }
    await input.press('ArrowDown');
    await page.waitForTimeout(60);
  }
  return (await input.getAttribute('aria-activedescendant')) === targetId;
}

test.describe('Search keyboard navigation', () => {
  test('exposes an accessible name on the search clear button', async ({ page }) => {
    await openNavbarSearch(page);

    // The clear control carries a camelCase CSS-module class and no type
    // attribute, so the substring match needs the case-insensitive flag.
    const clearButton = page.locator('button[type="reset"], button[class*="clear" i]').first();
    await expect(clearButton).toBeVisible();

    const accessibleName = await clearButton.evaluate((element) => {
      const ariaLabel = element.getAttribute('aria-label');
      if (ariaLabel) {
        return ariaLabel;
      }

      return element.textContent?.trim() ?? '';
    });

    expect(accessibleName, 'The search clear button should expose an accessible name').toMatch(/clear|reset/i);
  });

  test('associates the search input with an existing label or description', async ({ page }) => {
    const input = await openNavbarSearch(page);

    const labelledBy = await input.getAttribute('aria-labelledby');
    const describedBy = await input.getAttribute('aria-describedby');
    const ids = [...new Set([...(labelledBy?.split(/\s+/) ?? []), ...(describedBy?.split(/\s+/) ?? [])])];

    expect(ids.length, 'The search input should carry an aria-labelledby or aria-describedby association').toBeGreaterThan(0);

    for (const id of ids) {
      const associatedElement = page.locator(`#${id}`).first();
      const count = await associatedElement.count();
      expect(count, `Expected the associated element #${id} to exist`).toBeGreaterThan(0);
      const text = await associatedElement.textContent();
      expect(text?.trim().length ?? 0, `Expected the associated element #${id} to contain text`).toBeGreaterThan(0);
    }
  });

  test('reaches the footer option via arrow keys without moving focus from the input', async ({ page }) => {
    const input = await openNavbarSearch(page);

    const footerId = await getFooterId(page);
    const optionCount = (await getResultOptionIds(page)).length;

    let reachedFooter = false;
    // Accumulate every iteration's result. Assigning on each pass would let a
    // final conformant iteration erase an earlier violation, so the assertion
    // would report only the last step rather than the whole walk.
    const focusEscapes: string[] = [];

    for (let index = 0; index < optionCount + 4; index += 1) {
      await input.press('ArrowDown');
      await page.waitForTimeout(80);

      const activeDescendant = await input.getAttribute('aria-activedescendant');
      const activeElement = await page.evaluate(() => {
        const active = document.activeElement;
        if (!active || active === document.body) {
          // Focus dropping to <body> is a real failure, not a neutral state:
          // the user loses their place in the widget entirely.
          return 'body';
        }
        return String(active.className || active.tagName);
      });
      if (!activeElement.includes('navbar__search-input')) {
        focusEscapes.push(`step ${index + 1}: focus moved to "${activeElement}"`);
      }
      if (activeDescendant && footerId && activeDescendant === footerId) {
        reachedFooter = true;
        break;
      }
    }

    expect(reachedFooter, 'ArrowDown should reach the footer option').toBe(true);
    expect(
      focusEscapes,
      `Focus should stay on the combobox input while arrowing: ${focusEscapes.join('; ')}`,
    ).toEqual([]);
  });

  test('ArrowDown from the last result reaches the footer instead of wrapping to the top', async ({ page }) => {
    const input = await openNavbarSearch(page);

    const footerId = await getFooterId(page);
    const optionIds = await getResultOptionIds(page);
    expect(optionIds.length, 'expected at least one result option').toBeGreaterThan(0);
    const firstId = optionIds[0];
    const lastId = optionIds[optionIds.length - 1];

    const onLast = await arrowDownUntilActive(page, input, lastId, optionIds.length + 2);
    expect(onLast, 'should be able to reach the last result option').toBe(true);

    await input.press('ArrowDown');
    await page.waitForTimeout(80);
    const active = await input.getAttribute('aria-activedescendant');

    expect(active, 'ArrowDown from the last option should activate the footer').toBe(footerId);
    expect(active, 'ArrowDown from the last option must not wrap to the first option').not.toBe(firstId);

    const footerActive = await page
      .locator('[role="listbox"] [class*="hitFooter"] a.search-footer-active')
      .count();
    expect(footerActive, 'the footer should carry the active highlight class').toBe(1);
  });

  test('ArrowUp from the footer returns to the last result option', async ({ page }) => {
    const input = await openNavbarSearch(page);

    const footerId = await getFooterId(page);
    const optionIds = await getResultOptionIds(page);
    const lastId = optionIds[optionIds.length - 1];

    const reachedFooter = await arrowDownUntilActive(page, input, footerId as string, optionIds.length + 4);
    expect(reachedFooter, 'should reach the footer before testing ArrowUp').toBe(true);

    await input.press('ArrowUp');
    await page.waitForTimeout(80);

    expect(await input.getAttribute('aria-activedescendant')).toBe(lastId);
  });

  test('Enter on the footer navigates to the full search results page', async ({ page }) => {
    const input = await openNavbarSearch(page);

    const footerId = await getFooterId(page);
    const optionIds = await getResultOptionIds(page);

    const reachedFooter = await arrowDownUntilActive(page, input, footerId as string, optionIds.length + 4);
    expect(reachedFooter, 'should reach the footer before pressing Enter').toBe(true);

    await Promise.all([
      page.waitForURL(/\/search\/?/, { timeout: 10000 }),
      input.press('Enter'),
    ]);

    expect(page.url()).toContain('/search');
  });

  test('Tab from the open popup moves focus out of the search without navigating', async ({ page }) => {
    const input = await openNavbarSearch(page);

    await getFooterId(page);

    const urlBefore = page.url();
    await input.press('Tab');
    await page.waitForTimeout(250);

    // Focus landing on <body> is not a valid Tab escape. The browser parks focus
    // there when a handler cancels the default move, which is the keyboard trap
    // this test exists to detect, so it must be rejected rather than counted as
    // "left the input".
    const destination = await page.evaluate(() => {
      const active = document.activeElement;
      if (!active || active === document.body) {
        return 'body';
      }
      if (active.classList.contains('navbar__search-input')) {
        return 'search-input';
      }
      return String(active.tagName.toLowerCase() + (active.className ? `.${String(active.className).split(' ')[0]}` : ''));
    });
    expect(
      destination,
      'Tab must move focus to the next focusable control, not to the input or to <body> (no keyboard trap, WCAG 2.1.2)',
    ).not.toBe('search-input');
    expect(
      destination,
      'Tab dropped focus to <body>, which means the native focus move was cancelled (keyboard trap, WCAG 2.1.2)',
    ).not.toBe('body');
    expect(page.url()).toBe(urlBefore);
  });
});

