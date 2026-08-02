// Copyright (c) 2026 Microsoft Corporation. All rights reserved.
// SPDX-License-Identifier: MIT

import * as fs from 'fs';

const componentFields = ['agents', 'commands', 'rules', 'skills', 'hooks'];

/**
 * @param {Record<string, unknown>} entry
 */
export function countMarketplaceComponents(entry) {
  return componentFields.reduce((count, field) => {
    const value = entry[field];
    if (typeof value === 'string') {
      return count + 1;
    }
    if (Array.isArray(value)) {
      return count + value.length;
    }
    return count;
  }, 0);
}

/**
 * @param {string} marketplacePath
 * @param {string[]} packageNames
 */
export function loadMarketplaceCounts(marketplacePath, packageNames) {
  const marketplace = JSON.parse(fs.readFileSync(marketplacePath, 'utf-8'));
  const entries = new Map(
    marketplace.plugins.map((entry) => [entry.name, entry]),
  );

  return Object.fromEntries(packageNames.map((name) => {
    const entry = entries.get(name);
    if (!entry) {
      throw new Error(
        `[marketplaceCounts] Unknown marketplace package: ${name}`,
      );
    }
    return [name, countMarketplaceComponents(entry)];
  }));
}