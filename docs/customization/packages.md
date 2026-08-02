---
title: Managing Marketplace Packages
description: Define self-contained Copilot plugin and VSIX packages through the marketplace catalog and shared projection
author: Microsoft
ms.date: 2026-08-01
ms.topic: how-to
keywords:
  - marketplace
  - packages
  - plugins
  - vsix
estimated_reading_time: 6
---

## Package Authority

`.github/plugin/marketplace.json` is the only operational package definition. Each entry uses standard fields for component membership:

* `agents` for custom agents
* `commands` for prompts
* `rules` for instructions
* `skills` for skill directories
* `hooks` for the plugin-only hook manifest

The `x-hve` object contains repository metadata only: `displayName`, package and component maturity, documentation path, and aggregate status. It never appears in generated `plugin.json` files.

## Add Or Change A Package

1. Add canonical artifacts under their `.github/<kind>/<package>/` source directories.
2. Add package-relative component paths to the appropriate marketplace entry.
3. Set component maturity in `x-hve.componentMaturity` only when it differs from `stable` or records a removed tombstone.
4. Update the durable package page under `docs/plugins/`.
5. Run marketplace validation, plugin generation, extension preparation, and focused tests.

A package path maps deterministically to a canonical source path. Do not add a fallback reader, duplicate package manifest, or manually copy generated package output.

## Dependency Closure

`MarketplaceHelpers.psm1` resolves transitive agent handoffs from catalog-declared agents. Unresolved or ambiguous handoffs fail. The same resolved canonical source set feeds plugin and VSIX packaging before each channel maps sources to its destination layout.

Every package remains self-contained. Do not introduce plugin dependencies, `extensionPack`, or `extensionDependencies` as a substitute for package contents.

## Maturity And Channels

Supported maturity values, from least to most restrictive, are:

1. `stable`
2. `preview`
3. `experimental`
4. `deprecated`
5. `removed`

Stable packages include stable components. PreRelease packages include stable, preview, and experimental components. Deprecated and removed entries are never distributed. Removed component tombstones may remain in `x-hve.componentMaturity` after active membership is deleted so policy checks retain the retirement record.

## Generated Outputs

Plugin generation writes ignored materialized packages under `plugins/`. Extension preparation writes `extension/package*.json` and `extension/README*.md`. Generated outputs are never package-definition authority and are not edited by hand.

Use these checks for package changes:

```bash
npm run lint:marketplace
npm run plugin:generate
npm run plugin:evidence
npm run extension:prepare
npm run extension:prepare:prerelease
npm run test:ps -- -TestPath scripts/tests/plugins/
npm run test:ps -- -TestPath scripts/tests/extension/
```

## Aggregate Package

The marketplace declares exactly one aggregate package, `hve-core-all`. Validation requires it to cover every component from eligible PreRelease packages. Aggregate-only extras are allowed when they are explicitly declared and pass the same source, maturity, and closure checks.

---

<!-- markdownlint-disable MD036 -->
*🤖 Crafted with precision by ✨Copilot following brilliant human instruction,
then carefully refined by our team of discerning human reviewers.*
<!-- markdownlint-enable MD036 -->
