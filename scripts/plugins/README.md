---
title: Plugin Generation Scripts
description: PowerShell tooling for refreshing manifest-only Copilot CLI plugin roots from marketplace recipes
---

PowerShell tooling for refreshing manifest-only Copilot CLI plugin roots from
the marketplace catalog and resolved canonical source membership.

## Scripts

| Script                           | npm Command                | Description                                     |
|----------------------------------|----------------------------|-------------------------------------------------|
| Generate-Plugins.ps1             | `npm run plugin:generate`  | Refresh the ten tracked plugin manifests         |
| Validate-Marketplace.ps1         | `npm run lint:marketplace` | Validate marketplace.json plugin manifest       |
| Assert-PluginReleaseEvidence.ps1 | `npm run plugin:evidence`  | Record or verify canonical release evidence     |
| Modules/PluginHelpers.psm1       | (library)                  | Plugin manifest and catalog helpers              |

## Prerequisites

* PowerShell 7.0+
* PowerShell-Yaml module (`Install-Module -Name PowerShell-Yaml -RequiredVersion 0.4.7`)
* Git, because manifests and release evidence resolve canonical Git-tracked source paths

## Marketplace to Plugin Pipeline

1. Author artifacts in `.github/` (agents, prompts, instructions, skills, hooks)
2. Declare package membership and metadata in `.github/plugin/marketplace.json`
3. Run `npm run lint:marketplace` for ordinary non-mutating validation
4. Run `npm run plugin:generate` to refresh only the ten tracked
  `plugins/<package>/plugin.json` manifests
5. Validate deterministic evidence directly from canonical tracked sources

## Generated Output

the largest plugins.
Generation refreshes exactly ten tracked `plugins/<package>/plugin.json`
files. Each package directory contains only that manifest. Canonical agents,
prompts, instructions, skills, hooks, templates, and scripts remain under
`.github`; generation does not copy payloads, create package READMEs, or write
documentation.

## Refreshing Plugins After Artifact Changes

```bash
npm run plugin:generate
```

This command refreshes the tracked manifests from marketplace package recipes.
Ordinary validation uses `npm run plugin:validate` and does not create payloads.

## Marketplace Validation

`Validate-Marketplace.ps1` validates `.github/plugin/marketplace.json` against
its JSON schema and checks version alignment with the root `package.json`, the
ten manifest-only roots, and the canonical source locator of every entry.

```bash
npm run lint:marketplace
```

Parameters:

* `-OutputPath` (default: `logs/marketplace-validation-results.json`): path
  for the structured JSON report, absolute or relative to the repository root

The script writes structured JSON results to `logs/`, consistent with the rest
of the linting pipeline. Pass `-OutputPath ''` to suppress the report file.

### Entry Source Contract

Every entry uses its manifest-only package root:

```json
{
  "name": "rpi",
  "source": "plugins/rpi"
}
```

A development source is a relative string, so it resolves within the same
marketplace checkout selected by registration. Each
`plugins/<package>/plugin.json` manifest declares package membership through
paths to canonical `.github` artifacts. Git-source installation clones the
repository, so those references resolve within the clone without copied
payloads. `Validate-Marketplace.ps1` checks the manifest-only root, canonical
source existence, and catalog membership contract.

Development entries have no `source.ref`, `repo`, or object `path`. This
applies to `microsoft/hve-core` and a feature branch registration such as
`microsoft/hve-core#<branch>`; each uses the catalog and manifests from its
selected checkout. PreRelease and Stable release transforms convert relative
sources to immutable GitHub object sources with repo `microsoft/hve-core`, path
`plugins/<name>`, and exact `prerelease-v<version>` or `v<version>` refs.
Moving `#release/prerelease` and `#release/stable` registrations read branch
catalogs whose entries already pin those exact immutable tags.

Moving registrations and immutable catalog locators serve different purposes.
Use `microsoft/hve-core#release/prerelease` or
`microsoft/hve-core#release/stable` when following a moving release branch.
Use `prerelease-v<version>` or `v<version>` when selecting the immutable source
tree and source SHA used for reproducible evidence.

Component membership resolves to canonical `.github` sources:

* `agents/*.agent.md`
* `prompts/*.prompt.md` under the `commands` field
* `instructions/*.instructions.md` under the `rules` field
* `skills/*` directories
* `hooks/*.json`

The manifest paths traverse from each `plugins/<package>/plugin.json` file to
these canonical sources. The CLI resolves them from the repository clone; no
generated plugin ZIP or copied package tree participates in installation.

## Deterministic Release Evidence

`Assert-PluginReleaseEvidence.ps1` produces only canonical evidence v2 by
binding the immutable source commit, package version, exact channel ref
(`prerelease-v<version>` or `v<version>`), package count, per-package
non-vacuity and digests, and total digest into one invariant. It derives the
file sets from declared canonical git-tracked sources, so it needs no generated
package tree or staging root and reproduces from a clean checkout of the tagged
commit.

```bash
# Record PreRelease evidence
npm run plugin:evidence

# Record Stable evidence explicitly
pwsh -File scripts/plugins/Assert-PluginReleaseEvidence.ps1 \
  -Channel Stable \
  -SourceCommit <source SHA> \
  -Version <version> \
  -ReleaseTag v<version> \
  -OutputPath logs/plugin-release-evidence.json

# Verify Stable evidence against recorded evidence
pwsh -File scripts/plugins/Assert-PluginReleaseEvidence.ps1 \
  -Channel Stable \
  -SourceCommit <source SHA> \
  -Version <version> \
  -ReleaseTag v<version> \
  -ExpectedEvidencePath logs/plugin-release-evidence.json
```

Verification fails when the source commit, version, locator, package set, or any
digest disagrees, and when the recorded document is missing, corrupt, or
incomplete. `-ExpectedPackageCount` adds a package-count precondition.

## Release Publication and Historical Snapshots

Release workflows attach `plugin-release-evidence.json` to the release for the
exact `prerelease-v<version>` or `v<version>` channel ref. The evidence attests
catalog-resolved canonical Git-tracked sources, while the VSIX, dependency
SBOM, VEX where applicable, Sigstore, and in-toto assets retain their own
release responsibilities. The release and prerelease branch registrations are
reviewed and moving; the exact tags and their source SHAs are immutable release
identities.

Future legacy snapshot publication and evidence v1 are retired. Existing
historical identities, including earlier `hve-core-v` or `plugins-v` tags,
catalogs, and assets, remain immutable records only. They are not current
installation, registration, generation, or migration instructions, and they
are not deleted, moved, rewritten, or migrated by the current release process.

Remote release-asset and installed-client verification are authorized manual
actions. Local script and documentation checks do not execute or verify them.

---

<!-- markdownlint-disable MD036 -->
*🤖 Crafted with precision by ✨Copilot following brilliant human instruction,
then carefully refined by our team of discerning human reviewers.*
<!-- markdownlint-enable MD036 -->
