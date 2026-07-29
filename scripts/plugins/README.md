---
title: Plugin Generation Scripts
description: PowerShell tooling for generating Copilot CLI plugins from collection manifests
---

PowerShell tooling for generating Copilot CLI plugins from collection
manifests.

## Scripts

| Script                     | npm Command               | Description                                      |
|----------------------------|---------------------------|--------------------------------------------------|
| Generate-Plugins.ps1       | `npm run plugin:generate` | Generate plugin manifests and READMEs             |
| Modules/PluginHelpers.psm1 | (library)                 | Plugin and marketplace generation helpers        |

## Prerequisites

* PowerShell 7.0+
* PowerShell-Yaml module (`Install-Module -Name PowerShell-Yaml -RequiredVersion 0.4.7`)

## Collection to Plugin Pipeline

1. Author artifacts in `.github/` (agents, prompts, skills)
2. Define collections in `collections/*.collection.yml`
3. Run `npm run plugin:generate` to produce each plugin's manifest and README
4. Commit generated `plugins/` to the repository

## Refreshing Plugins After Artifact Changes

```bash
npm run plugin:generate
```

This regenerates each `plugins/<collection>/.github/plugin/plugin.json` from its
collection manifest and initially copies the refreshed collection markdown to
`plugins/<collection>/README.md`. Component paths in `plugin.json` reference
canonical artifacts under the repository's root `.github/` directory. README
generation can evolve independently from collection markdown in future changes.

---

<!-- markdownlint-disable MD036 -->
*🤖 Crafted with precision by ✨Copilot following brilliant human instruction,
then carefully refined by our team of discerning human reviewers.*
<!-- markdownlint-enable MD036 -->
