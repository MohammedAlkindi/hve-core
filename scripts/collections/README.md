---
title: Collection Scripts
description: PowerShell tooling for validating collection manifests and shared collection helpers
---

PowerShell tooling for validating collection manifests and shared collection
helper functions used by both collection validation and plugin generation.

## Scripts

| Script                         | npm Command                         | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
|--------------------------------|-------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Validate-Collections.ps1       | `npm run lint:collections-metadata` | Validate collection manifests and enforce structural/semantic rules. Detects **MaturityConflict** (canonical-vs-themed) only when the canonical item has an explicit item-level maturity value (skips shared sub-domains). Detects **CrossCollectionMaturityConflict** across themed collections (excludes the `hve-core-all` canonical collection and shared sub-domains). Enforces **InvalidArtifactPathStructure**, ensuring artifacts inside `.github/` reside in collection-specific subfolders (root-level artifacts are excluded from distribution). |
| Modules/CollectionHelpers.psm1 | (library)                           | YAML parsing, frontmatter, and collection helpers, including strict-safe maturity propagation via `Get-CollectionMaturityVocabulary`, `Get-CollectionMaturityRank`, and `Resolve-StrictSafeMaturity` (unrecognized maturity values default to `experimental`)                                                                                                                                                                                                                                                                                               |

## Prerequisites

* PowerShell 7.4+
* PowerShell-Yaml module (`Install-Module -Name PowerShell-Yaml -RequiredVersion 0.4.7`)

## Frozen Collection Inputs

Collection YAML and Markdown files are frozen while remaining consumers move to
the marketplace catalog. Do not add or edit collection manifests.

To change a Copilot package, update the standard component fields in
`.github/plugin/marketplace.json`, run `npm run lint:marketplace`, and generate
the package locally with `npm run plugin:generate`. The root `plugins/`
directory is ignored validation and distribution output; never commit it.

<!-- markdownlint-disable MD036 -->
*🤖 Crafted with precision by ✨Copilot following brilliant human instruction,
then carefully refined by our team of discerning human reviewers.*
<!-- markdownlint-enable MD036 -->
