---
title: Plugin Generation Scripts
description: PowerShell tooling for generating Copilot CLI plugins from collection manifests
---

PowerShell tooling for generating Copilot CLI plugins from collection
manifests.

## Scripts

| Script                           | npm Command                | Description                                     |
|----------------------------------|----------------------------|-------------------------------------------------|
| Generate-Plugins.ps1             | `npm run plugin:generate`  | Generate plugin directories from collections    |
| Validate-Marketplace.ps1         | `npm run lint:marketplace` | Validate marketplace.json plugin manifest       |
| Assert-PluginReleaseEvidence.ps1 | `npm run plugin:evidence`  | Record or verify deterministic release evidence |
| Modules/PluginHelpers.psm1       | (library)                  | Plugin materialization, manifest, and packaging |

## Prerequisites

* PowerShell 7.0+
* PowerShell-Yaml module (`Install-Module -Name PowerShell-Yaml -RequiredVersion 0.4.7`)
* Git, because generation copies only git-tracked source paths

## Collection to Plugin Pipeline

1. Author artifacts in `.github/` (agents, prompts, skills)
2. Define collections in `collections/*.collection.yml`
3. Run `npm run plugin:generate` to produce `plugins/`
4. Commit generated `plugins/` to the repository

## Generated Output

Plugin trees contain only regular files and real directories. No symbolic links
are created, so generation needs no elevated privileges and no OS-specific
configuration.

Each declared collection source is materialized from the paths git currently
tracks beneath it. Working-tree bytes are copied, so locally modified tracked
files are included, while untracked content such as `.venv/`, `node_modules/`,
and `__pycache__/` is never ingested. Generation fails when the combined output
exceeds `-MaxTotalSizeMB` (default 40), and the failure names the largest
plugins.

A source path that git does not track produces a warning and is skipped. Stage
new artifacts before generating.

## Refreshing Plugins After Artifact Changes

```bash
npm run plugin:generate
```

This regenerates all plugins from their collection manifests.

## Marketplace Validation

`Validate-Marketplace.ps1` validates `.github/plugin/marketplace.json` against
its JSON schema and checks version alignment with the root `package.json` plus
the source locator of every entry.

```bash
npm run lint:marketplace
```

Parameters:

* `-OutputPath` (default: `logs/marketplace-validation-results.json`): path
  for the structured JSON report, absolute or relative to the repository root

The script writes structured JSON results to `logs/`, consistent with the rest
of the linting pipeline. Pass `-OutputPath ''` to suppress the report file.

### Entry Source Forms

An entry `source` takes one of two forms.

A bare string names a locally generated package directory:

```json
{ "name": "rpi", "source": "rpi" }
```

Bare sources must contain no path separator and must match the entry name. The
directory under `plugins/` is required only when generated output is present, so
validation still works once packages move to a release reference.

An object declares a remote locator:

```json
{
  "name": "rpi",
  "source": {
    "source": "github",
    "repo": "microsoft/hve-core",
    "path": "plugins/rpi",
    "ref": "plugins-v3.3.101"
  }
}
```

Supported source types are `github` (with `repo`) and `url` (with an https
`url`). `path` is required, must be repository-relative, and may not escape the
source repository. `ref` and `sha` are optional and mutually exclusive; a `sha`
must be a full 40-character lowercase commit id. Name and source equality is not
applied to object sources.

## Locator-Aware Catalog Generation

Default generation writes bare local sources to the production catalog. Passing
an explicit release tag switches the catalog to object sources:

```bash
pwsh -File scripts/plugins/Generate-Plugins.ps1 \
  -ReleaseTag plugins-v3.3.101 \
  -MarketplaceOutputPath logs/marketplace-snapshot.json
```

Locator mode requires an explicit `-MarketplaceOutputPath` and refuses to write
the production catalog. Moving the production catalog to remote locators is a
separate reviewed change, not a side effect of generation. Only the immutable
`plugins-v<version>` tag form is accepted; commit-sha locators are rejected
until their catalog update path is proven.

## Deterministic Release Evidence

`Assert-PluginReleaseEvidence.ps1` binds the immutable source commit, package
version, catalog locator, and a digest of the generated package tree into one
invariant. The digest covers repository-relative package paths and file content
only, so it reproduces from a clean checkout of the same source commit and never
compares against committed generated output.

```bash
# Record
npm run plugin:evidence

# Verify a snapshot against recorded evidence
pwsh -File scripts/plugins/Assert-PluginReleaseEvidence.ps1 \
  -ExpectedEvidencePath logs/plugin-release-evidence.json
```

Verification fails when the source commit, version, locator, package set, or any
digest disagrees, and when the recorded document is missing, corrupt, or
incomplete. `-ExpectedPackageCount` adds a package-count precondition.

## Snapshot Publication

The `Plugin Snapshot Publish` workflow generates one snapshot from an explicit
immutable source, stages it as an orphan commit, and verifies the staged tree
from a fresh clone before any reference is written.

Its targets are constrained by `Assert-PluginSnapshotTarget`:

* Branch and tag must start with the disposable prefix `plugins-snapshot/`.
* `main`, `release/plugins`, and `plugins-v<version>` references are refused.
* An existing tag is refused rather than overwritten, and no push uses a force
  flag.

The workflow defaults to `dry-run: true`, which stages and verifies without
pushing. It never writes the production catalog, and it fails if the catalog
changed during the run.

### Cutover and Rollback Contract

Moving the production catalog to remote locators and untracking generated output
is a later, separately reviewed step. It is refused unless every precondition
holds:

1. The snapshot contains the complete expected package set, asserted with
   `-ExpectedPackageCount`.
2. The source commit, version, locator, and digest agree in recorded evidence.
3. Archives and attestations match the same snapshot.
4. Both clients install from the immutable reference and pass a functional
   component check.

Failure behavior and rollback:

* Any failed precondition leaves the production catalog, release references, and
  tracked `plugins/` state exactly as they were. Every guard fails before a
  write rather than reverting one.
* Rollback restores the previous catalog locator by pointing entries at the
  prior `plugins-v<version>` tag. Immutable tags are never rewritten, moved, or
  deleted, so the prior snapshot remains resolvable.

---

<!-- markdownlint-disable MD036 -->
*🤖 Crafted with precision by ✨Copilot following brilliant human instruction,
then carefully refined by our team of discerning human reviewers.*
<!-- markdownlint-enable MD036 -->
