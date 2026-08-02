// Copyright (c) 2026 Microsoft Corporation. All rights reserved.
// SPDX-License-Identifier: MIT

export function countMarketplaceComponents(
  entry: Record<string, unknown>,
): number;

export function loadMarketplaceCounts(
  marketplacePath: string,
  packageNames: string[],
): Record<string, number>;
