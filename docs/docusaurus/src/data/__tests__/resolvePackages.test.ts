// Copyright (c) 2026 Microsoft Corporation. All rights reserved.
// SPDX-License-Identifier: MIT
import {
  packageCardDefinitions,
  resolvePackageCards,
  resolveMetaPackages,
} from '../packageCards';

describe('resolvePackageCards', () => {
  it('maps a declared count onto the matching package', () => {
    const first = packageCardDefinitions[0];

    const cards = resolvePackageCards({ [first.name]: 7 });

    expect(cards.find((card) => card.name === first.name)?.artifacts).toBe(7);
  });

  it('falls back to 0 artifacts when a count is missing', () => {
    const cards = resolvePackageCards({});

    expect(cards).toHaveLength(packageCardDefinitions.length);
    expect(cards.every((card) => card.artifacts === 0)).toBe(true);
  });

  it('preserves the declaration order and the declared card fields', () => {
    const cards = resolvePackageCards({});

    expect(cards.map((card) => card.name)).toEqual(
      packageCardDefinitions.map((definition) => definition.name),
    );
    cards.forEach((card, index) => {
      const definition = packageCardDefinitions[index];
      expect(card.title).toBe(definition.title);
      expect(card.description).toBe(definition.description);
      expect(card.maturity).toBe(definition.maturity);
      expect(card.href).toBe(definition.href);
    });
  });

  it('ignores counts for packages that declare no card', () => {
    const cards = resolvePackageCards({ 'not-a-card': 99 });

    expect(cards.map((card) => card.name)).not.toContain('not-a-card');
  });
});

describe('resolveMetaPackages', () => {
  it('reads the hve-core-all count when present', () => {
    expect(resolveMetaPackages({ 'hve-core-all': 42 })).toEqual({ 'hve-core-all': 42 });
  });

  it('falls back to 0 when the hve-core-all count is missing', () => {
    expect(resolveMetaPackages({})).toEqual({ 'hve-core-all': 0 });
  });

  it('exposes only the meta package entry', () => {
    expect(Object.keys(resolveMetaPackages({ 'hve-core-all': 1, ado: 2 }))).toEqual([
      'hve-core-all',
    ]);
  });
});
