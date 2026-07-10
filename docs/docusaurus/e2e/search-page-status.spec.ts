// Copyright (c) 2026 Microsoft Corporation. All rights reserved.
// SPDX-License-Identifier: MIT
import { test, expect } from '@playwright/test';

test.describe('Search page status announcements', () => {
  test('announces matching and non-matching query counts', async ({ page }) => {
    await page.goto('/hve-core/search/?q=agent');

    const status = page.locator('#search-results-status[role="status"]');
    await expect(status).toHaveAttribute('aria-live', 'polite');
    await expect(status).toHaveText(/\d+ document(?:s)? found/, { timeout: 15000 });

    const searchInput = page.locator('input[name="q"]');
    await searchInput.fill('zzzzzzzzqqqq');
    await expect(status).toHaveText(/No documents found/, { timeout: 15000 });
  });
});
