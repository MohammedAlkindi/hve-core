---
title: Agent Customization and Upgrade
description: Phase 7 agent customization and the Phase 7 upgrade mode for the hve-core installer.
---
<!-- markdownlint-disable-file -->

## Phase 7: Agent Customization (Optional)

> [!IMPORTANT]
> Generated scripts in this phase require PowerShell 7+ (`pwsh`). Windows PowerShell 5.1 is not supported.

After Phase 6 completes, offer users the option to copy agent files into their target repository. This phase ONLY applies to clone-based installation methods (1-6), NOT to extension installation.

### Skip Condition

If user selected **Extension Quick Install** (Option 1) in Phase 2, skip Phase 7 entirely. Extension installation bundles agents automatically.

### Checkpoint 6: Agent Copy Decision

Present the agent selection prompt:

<!-- <agent-copy-prompt> -->
```text
📂 Agent Customization (Optional)

HVE-Core includes specialized agents for common workflows.
Copying agents enables local customization and offline use.

🔬 HVE Core Starter Agents
  • rpi-agent - Research, Plan, Implement, Review, and Follow-up coordinator
  • documentation - Documentation audit, drift, authoring, and validation

📋 Planning & Documentation
  • adr-creation, brd-builder, prd-builder
  • security-planner, ux-ui-designer

⚙️ Generators
  • gen-data-spec, gen-jupyter-notebook, gen-streamlit-dashboard

✅ Review & Testing
  • code-review, test-streamlit-dashboard

🔗 Platform-Specific
  • backlog-manager (Azure DevOps, GitHub, Jira)
  • functional-planner (PRD planning)

Options:
  [1] Install HVE Core starter agents (recommended)
  [2] Install by collection
  [3] Skip agent installation

Your choice? (1/2/3)
```
<!-- </agent-copy-prompt> -->

User input handling:

* "1", "rpi", "starter", "core" → Copy the HVE Core starter bundle
* "2", "collection", "by collection" → Proceed to Collection Selection sub-flow
* "3", "skip", "none", "no" → Skip to success report
* Unclear response → Ask for clarification

### Collection Selection Sub-Flow

When the user selects option 2, read collection manifests to present available collections.

#### Step 1: Read collections and build collection agent counts

Read `collections/*.collection.yml` from the HVE-Core source (at `$hveCoreBasePath`). Derive collection options from collection `id` and `name`. For each selected collection, count agent items where `kind` equals `agent` and effective item maturity is `stable` (item `maturity` omitted defaults to `stable`; exclude `experimental` and `deprecated`).

#### Step 2: Present collection options

<!-- <collection-selection-prompt> -->
```text
🎭 Collection Selection

Choose one or more collections to install agents tailored to your role, more to come in the future.

| # | Collection | Agents | Description                     |
|---|------------|--------|---------------------------------|
| 1 | Developer  | [N]    | Software engineers writing code |

Enter collection number(s) separated by commas (e.g., "1"):
```
<!-- </collection-selection-prompt> -->

Agent counts `[N]` include agents matching the collection with `stable` maturity.

User input handling:

* Single number (e.g., "1") → Select that collection
* Multiple numbers (e.g., "1, 3") → Combine agent sets from selected collections
* Collection name (e.g., "developer") → Match by identifier
* Unclear response → Ask for clarification

#### Step 3: Build filtered agent list

For each selected collection identifier:

1. Iterate through `items` in the collection manifest
2. Include items where `kind` is `agent` AND `maturity` is `stable`
3. Deduplicate across multiple selected collections

#### Step 4: Present filtered agents for confirmation

<!-- <collection-confirmation-prompt> -->
```text
📋 Agents for [Collection Name(s)]

The following [N] agents will be copied:

  • [agent-name-1] - tags: [tag-1, tag-2]
  • [agent-name-2] - tags: [tag-1, tag-2]
  ...

Proceed with installation? (yes/no)
```
<!-- </collection-confirmation-prompt> -->

User input handling:

* "yes", "y" → Proceed with copy using filtered agent list
* "no", "n" → Return to Checkpoint 6 for re-selection
* Unclear response → Ask for clarification

> [!NOTE]
> Collection filtering applies to agents only. Copying of related prompts, instructions, and skills based on collection is planned for a future release.

### Agent Bundle Definitions

| Bundle            | Agents                            |
|-------------------|-----------------------------------|
| `hve-core`        | rpi-agent, documentation          |
| `collection:<id>` | Stable agents matching collection |

### Collision Detection

Before copying, check for existing agent files with matching names.

**PowerShell:** Run [scripts/collision-detection.ps1](scripts/collision-detection.ps1) with the `hveCoreBasePath`, `selection`, and optional `collectionAgents` variables set.

**Bash:** Run [scripts/collision-detection.sh](scripts/collision-detection.sh) with the HVE-Core base path and file list as arguments.

### Collision Resolution Prompt

If collisions are detected, present:

<!-- <collision-prompt> -->
```text
⚠️ Existing Agents Detected

The following agents already exist in your project:
  • [list collision files]

Options:
  [O] Overwrite with HVE-Core version
  [K] Keep existing (skip these files)
  [C] Compare (show diff for first file)

Or for all conflicts:
  [OA] Overwrite all
  [KA] Keep all existing

Your choice?
```
<!-- </collision-prompt> -->

User input handling:

* "o", "overwrite" → Overwrite current file, ask about next
* "k", "keep" → Keep current file, ask about next
* "c", "compare" → Show diff, then re-prompt
* "oa", "overwrite all" → Overwrite all collisions
* "ka", "keep all" → Keep all existing files

### Agent Copy Execution

After selection and collision resolution, execute the copy operation.

**PowerShell:** Run [scripts/agent-copy.ps1](scripts/agent-copy.ps1) with the required variables set.

**Bash:** Run [scripts/agent-copy.sh](scripts/agent-copy.sh) with the HVE-Core base path, collection ID, and file list as arguments.

### Agent Copy Success Report

Upon successful copy, display:

<!-- <agent-copy-success> -->
```text
✅ Agent Installation Complete!

Copied [N] agents to .github/agents/
Created .hve-tracking.json for upgrade tracking

📄 Installed Agents:
  • [list of copied agent names]

🔄 Upgrade Workflow:
  Run this installer again to check for agent updates.
  Modified files will prompt before overwriting.
  Use 'eject' to take ownership of any file.

Proceeding to final success report...
```
<!-- </agent-copy-success> -->

## Phase 7 Upgrade Mode

When `.hve-tracking.json` already exists, Phase 7 operates in upgrade mode.

### Upgrade Detection

At Phase 7 start, check for existing manifest.

**PowerShell:** Run [scripts/upgrade-detection.ps1](scripts/upgrade-detection.ps1) with the `hveCoreBasePath` variable set.

**Bash:** Run [scripts/upgrade-detection.sh](scripts/upgrade-detection.sh) with the HVE-Core base path as an argument.

### Upgrade Prompt

If upgrade mode with version change:

<!-- <upgrade-prompt> -->
```text
🔄 HVE-Core Agent Upgrade

Source: microsoft/hve-core v[SOURCE_VERSION]
Installed: v[INSTALLED_VERSION]

Checking file status...
```
<!-- </upgrade-prompt> -->

### File Status Check

Compare current files against manifest.

**PowerShell:** Run [scripts/file-status-check.ps1](scripts/file-status-check.ps1).

**Bash:** Run [scripts/file-status-check.sh](scripts/file-status-check.sh) to compare files against the manifest.

### Upgrade Summary Display

Present upgrade summary:

<!-- <upgrade-summary> -->
```text
📋 Upgrade Summary

Files to update (managed):
  ✅ .github/agents/rpi-agent.agent.md
  ✅ .github/agents/documentation.agent.md

Files requiring decision (modified):
  ⚠️ .github/agents/rpi-agent.agent.md

Files skipped (ejected):
  🔒 .github/agents/custom-agent.agent.md

For modified files, choose:
  [A] Accept upstream (overwrite your changes)
  [K] Keep local (skip this update)
  [E] Eject (never update this file again)
  [D] Show diff

Process file: rpi-agent.agent.md?
```
<!-- </upgrade-summary> -->

### Diff Display

When user requests diff:

<!-- <diff-display> -->
```text
─────────────────────────────────────
File: .github/agents/rpi-agent.agent.md
Status: modified
─────────────────────────────────────

--- Local version
+++ HVE-Core version

@@ -10,3 +10,5 @@
 ## Role Definition

-Your local modifications here
+Updated behavior with new capabilities
+
+New section added in latest version
─────────────────────────────────────

[A] Accept upstream / [K] Keep local / [E] Eject
```
<!-- </diff-display> -->

### Status Transitions

After user decision, update manifest:

| Decision | Status Change           | Manifest Update           |
|----------|-------------------------|---------------------------|
| Accept   | `modified` → `managed`  | Update hash, version      |
| Keep     | `modified` → `modified` | No change (skip file)     |
| Eject    | `*` → `ejected`         | Add `ejectedAt` timestamp |

### Eject Implementation

When user ejects a file:

**PowerShell:** Run [scripts/eject.ps1](scripts/eject.ps1) with the `FilePath` parameter.

**Bash:** Run [scripts/eject.sh](scripts/eject.sh) with the file path as an argument.

### Upgrade Completion

After processing all files:

<!-- <upgrade-success> -->
```text
✅ Upgrade Complete!

Updated: [N] files
Skipped: [M] files (kept local or ejected)
Version: v[OLD] → v[NEW]

Proceeding to final success report...
```
<!-- </upgrade-success> -->

