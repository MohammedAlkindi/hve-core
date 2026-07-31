# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT

# PluginHelpers.psm1
#
# Purpose: Shared functions for the Copilot CLI plugin generation pipeline.
# Author: HVE Core Team

#Requires -Version 7.4

Import-Module (Join-Path $PSScriptRoot '../../collections/Modules/CollectionHelpers.psm1') -Force

# ---------------------------------------------------------------------------
# Pure Functions (no file system side effects)
# ---------------------------------------------------------------------------

function Get-PluginItemName {
    <#
    .SYNOPSIS
    Returns an artifact filename, stripping kind suffixes for CLI display.

    .DESCRIPTION
    Validated entry point for filename handling in the plugin pipeline.
    Agent and prompt files have their kind suffix (.agent.md, .prompt.md)
    replaced with .md so the CLI title is clean. Instruction files keep
    their suffix because VS Code discovery filters on *.instructions.md.

    .PARAMETER FileName
    The original filename (e.g. rpi-agent.agent.md).

    .PARAMETER Kind
    The artifact kind: agent, prompt, instruction, or skill.

    .OUTPUTS
    [string] The processed filename.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('agent', 'prompt', 'instruction', 'skill', 'hook')]
        [string]$Kind
    )

    switch ($Kind) {
        'agent'       { return $FileName -replace '\.agent\.md$', '.md' }
        'prompt'      { return $FileName -replace '\.prompt\.md$', '.md' }
        'instruction' { return $FileName }
        'skill'       { return $FileName }
        'hook'        { return $FileName }
    }
}

function Get-PluginItemSubpath {
    <#
    .SYNOPSIS
    Extracts the subdirectory path between the kind root prefix and the leaf.

    .DESCRIPTION
    Given a repo-relative item path and its kind, strips the known prefix
    (e.g. .github/agents/) and returns the intermediate directory segments.
    Returns empty string when the item is directly under the kind root.

    .PARAMETER Path
    Repo-relative item path (e.g. .github/agents/hve-core/rpi-agent.agent.md).

    .PARAMETER Kind
    The artifact kind: agent, prompt, instruction, or skill.

    .OUTPUTS
    [string] Intermediate subdirectory path, or empty string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet('agent', 'prompt', 'instruction', 'skill', 'hook')]
        [string]$Kind
    )

    $prefixMap = @{
        'agent'       = '.github/agents/'
        'prompt'      = '.github/prompts/'
        'instruction' = '.github/instructions/'
        'skill'       = '.github/skills/'
        'hook'        = '.github/hooks/'
    }

    $prefix = $prefixMap[$Kind]
    $normalized = $Path -replace '\\', '/'

    if (-not $normalized.StartsWith($prefix)) {
        return ''
    }

    $relative = $normalized.Substring($prefix.Length)
    $parts = $relative -split '/'

    if ($parts.Count -gt 1) {
        return ($parts[0..($parts.Count - 2)] -join '/')
    }

    return ''
}

function Get-PluginSubdirectory {
    <#
    .SYNOPSIS
    Returns the plugin subdirectory name for an artifact kind.

    .DESCRIPTION
    Maps a collection item kind to the corresponding subdirectory name
    within the plugin directory structure.

    .PARAMETER Kind
    The artifact kind: agent, prompt, instruction, or skill.

    .OUTPUTS
    [string] The subdirectory name (agents, commands, instructions, or skills).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('agent', 'prompt', 'instruction', 'skill', 'hook')]
        [string]$Kind
    )

    switch ($Kind) {
        'agent' { return 'agents' }
        'prompt' { return 'commands' }
        'instruction' { return 'instructions' }
        'skill' { return 'skills' }
        'hook' { return 'hooks' }
    }
}

function New-PluginManifestContent {
    <#
    .SYNOPSIS
    Generates plugin.json content as a hashtable.

    .DESCRIPTION
    Creates a hashtable representing the plugin manifest with name,
    description, version, and component path declarations. When explicit
    path arrays are provided, uses them so the CLI discovers artifacts
    in nested subdirectories. When omitted, falls back to convention
    defaults for lightweight marketplace entries.

    .PARAMETER CollectionId
    The collection identifier used as the plugin name.

    .PARAMETER Description
    A short description of the plugin.

    .PARAMETER Version
    Semantic version string from the repository package.json.

    .PARAMETER AgentPaths
    Optional. Array of relative directory paths containing .agent.md files.

    .PARAMETER CommandPaths
    Optional. Array of relative directory paths containing .prompt.md files.

    .PARAMETER SkillPaths
    Optional. Array of relative directory paths containing skill subdirs.

    .PARAMETER HookPaths
    Optional. Array of relative file paths to hook JSON files.

    .OUTPUTS
    [hashtable] Plugin manifest with name, description, version, and
    component path keys.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CollectionId,

        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$AgentPaths,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$CommandPaths,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$SkillPaths,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$HookPaths
    )

    $manifest = [ordered]@{
        name        = $CollectionId
        description = $Description
        version     = $Version
    }

    # Emit explicit path arrays when provided; the CLI does not recurse
    # into subdirectories, so each leaf directory must be declared.
    if ($AgentPaths -and $AgentPaths.Count -gt 0) {
        $manifest['agents'] = @($AgentPaths | Sort-Object)
    }

    if ($CommandPaths -and $CommandPaths.Count -gt 0) {
        $manifest['commands'] = @($CommandPaths | Sort-Object)
    }

    if ($SkillPaths -and $SkillPaths.Count -gt 0) {
        $manifest['skills'] = @($SkillPaths | Sort-Object)
    }

    if ($HookPaths -and $HookPaths.Count -gt 0) {
        # The CLI `hooks` field is a single hooks-config file path (or inline
        # object), not an array. Emit the lone path as a string; warn when more
        # than one hook manifest is registered since only one can be referenced.
        $sortedHooks = @($HookPaths | Sort-Object)
        if ($sortedHooks.Count -gt 1) {
            Write-Warning "Plugin '$CollectionId' declares $($sortedHooks.Count) hook manifests; the CLI references only one. Using '$($sortedHooks[0])'."
        }
        $manifest['hooks'] = $sortedHooks[0]
    }

    return $manifest
}

function New-PluginReadmeContent {
    <#
    .SYNOPSIS
    Generates README.md markdown for a plugin.

    .DESCRIPTION
    Builds a complete README.md string with a markdownlint-disable header,
    title, description, install command, and tables for each artifact kind
    that has items. Only sections with items are included.

    .PARAMETER Collection
    Hashtable with id, name, and description keys from the collection manifest.
    An optional 'notice' key injects a custom blockquote after the description.

    .PARAMETER Items
    Array of processed item objects. Each object must have Name, Description,
    and Kind properties.

    .PARAMETER Maturity
        Optional collection-level maturity string. When 'experimental', an
        experimental notice is injected after the description. When 'preview',
        a preview notice is injected.

    .PARAMETER CollectionContent
        Optional markdown content from the collection .md file. Injected as
        an Overview section between the description and the Install section.

    .OUTPUTS
    [string] Complete README markdown content.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Collection,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$Items,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Maturity,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$CollectionContent
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<!-- markdownlint-disable-file -->')
    [void]$sb.AppendLine("# $($Collection.name)")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine($Collection.description)

    # Inject maturity notice when collection is not stable
    $effectiveMaturity = if ([string]::IsNullOrWhiteSpace($Maturity)) { 'stable' } else { $Maturity }
    if ($effectiveMaturity -eq 'experimental') {
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("> **`u{26A0}`u{FE0F} Experimental** `u{2014} This collection is experimental. Contents and behavior may change or be removed without notice.")
    }
    elseif ($effectiveMaturity -eq 'preview') {
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("> **`u{1F50D} Preview** `u{2014} This collection is in preview. Core features are complete and functional but refinements may follow.")
    }

    # Inject collection-level notice when present
    if ($Collection.ContainsKey('notice') -and -not [string]::IsNullOrWhiteSpace($Collection.notice)) {
        [void]$sb.AppendLine()
        [void]$sb.AppendLine($Collection.notice.TrimEnd())
    }

    # Inject collection description content as an Overview section.
    # Strip the leading H1 since the title is already emitted above.
    if (-not [string]::IsNullOrWhiteSpace($CollectionContent)) {
        $overviewText = $CollectionContent -replace '(?m)\A#\s+[^\r\n]+\r?\n\r?\n', ''
        $overviewText = $overviewText.TrimEnd()

        if (-not [string]::IsNullOrWhiteSpace($overviewText)) {
            [void]$sb.AppendLine()
            [void]$sb.AppendLine('## Overview')
            [void]$sb.AppendLine()
            [void]$sb.AppendLine($overviewText)
        }
    }

    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Install')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('```bash')
    [void]$sb.AppendLine("copilot plugin install $($Collection.id)@hve-core")
    [void]$sb.AppendLine('```')

    $sectionMap = [ordered]@{
        agent       = @{ Title = 'Agents'; Header = 'Agent' }
        prompt      = @{ Title = 'Commands'; Header = 'Command' }
        instruction = @{ Title = 'Instructions'; Header = 'Instruction' }
        skill       = @{ Title = 'Skills'; Header = 'Skill' }
        hook        = @{ Title = 'Hooks'; Header = 'Hook' }
    }

    $hasCollectionArtifactContent = -not [string]::IsNullOrWhiteSpace($CollectionContent) -and (
        $CollectionContent -match '(?m)^##\s+Included Artifacts\s*$' -or
        (
            $CollectionContent -match '<!-- BEGIN AUTO-GENERATED ARTIFACTS -->' -and
            $CollectionContent -match '<!-- END AUTO-GENERATED ARTIFACTS -->'
        )
    )

    if (-not $hasCollectionArtifactContent) {
        foreach ($entry in $sectionMap.GetEnumerator()) {
            $kind = $entry.Key
            $meta = $entry.Value
            $kindItems = @($Items | Where-Object { $_.Kind -eq $kind })
            if ($kindItems.Count -eq 0) {
                continue
            }

            [void]$sb.AppendLine()
            [void]$sb.AppendLine("## $($meta.Title)")
            [void]$sb.AppendLine()

            # Calculate column widths for aligned table output
            $col1Width = $meta.Header.Length
            $col2Width = 'Description'.Length
            foreach ($item in $kindItems) {
                if ($item.Name.Length -gt $col1Width) { $col1Width = $item.Name.Length }
                if ($item.Description.Length -gt $col2Width) { $col2Width = $item.Description.Length }
            }

            [void]$sb.AppendLine("| $($meta.Header.PadRight($col1Width)) | $('Description'.PadRight($col2Width)) |")
            [void]$sb.AppendLine('|' + ('-' * ($col1Width + 2)) + '|' + ('-' * ($col2Width + 2)) + '|')
            foreach ($item in $kindItems) {
                [void]$sb.AppendLine("| $($item.Name.PadRight($col1Width)) | $($item.Description.PadRight($col2Width)) |")
            }
        }
    }

    [void]$sb.AppendLine()
    [void]$sb.AppendLine('---')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('> Source: [microsoft/hve-core](https://github.com/microsoft/hve-core)')
    [void]$sb.AppendLine()

    return $sb.ToString()
}

function New-PluginReleaseLocator {
    <#
    .SYNOPSIS
    Builds a validated immutable release locator for marketplace object sources.

    .DESCRIPTION
    Produces the repository, immutable ref, and package path prefix used to emit
    object-form marketplace sources. Accepts an explicit 'plugins-v<version>' tag
    or derives one from a package version.

    Commit-sha locators are rejected. Catalog sha pinning stays unsupported until
    a reviewed change proves an end-to-end catalog update path for it.

    .PARAMETER Tag
    Explicit immutable release tag in 'plugins-v<version>' form.

    .PARAMETER Version
    Semantic version from which the 'plugins-v<version>' tag is derived.

    .PARAMETER Repo
    Source repository in 'owner/name' form.

    .PARAMETER PathPrefix
    Repository-relative directory holding generated packages.

    .OUTPUTS
    [hashtable] Locator with Repo, Ref, and PathPrefix keys.

    .EXAMPLE
    New-PluginReleaseLocator -Version '1.2.3'
    #>
    [CmdletBinding(DefaultParameterSetName = 'Tag')]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Tag')]
        [AllowEmptyString()]
        [string]$Tag,

        [Parameter(Mandatory = $true, ParameterSetName = 'Version')]
        [AllowEmptyString()]
        [string]$Version,

        [Parameter(Mandatory = $false)]
        [string]$Repo = 'microsoft/hve-core',

        [Parameter(Mandatory = $false)]
        [string]$PathPrefix = 'plugins'
    )

    $semVerPattern = '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$'

    if ($PSCmdlet.ParameterSetName -eq 'Version') {
        if ($Version -notmatch $semVerPattern) {
            throw "Release version '$Version' is not a semantic version."
        }
        $Tag = "plugins-v$Version"
    }

    if ($Tag -match '^[0-9a-fA-F]{40}$') {
        throw "Release locator '$Tag' is a commit sha. Sha-pinned catalog sources are not supported; use the immutable 'plugins-v<version>' tag."
    }

    if ($Tag -notmatch "^plugins-v$($semVerPattern.TrimStart('^'))") {
        throw "Release locator '$Tag' must use the immutable 'plugins-v<version>' tag form."
    }

    if ($Repo -notmatch '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$') {
        throw "Release repository '$Repo' must use 'owner/name' form."
    }

    $normalizedPrefix = $PathPrefix.Trim('/')
    if ([string]::IsNullOrWhiteSpace($normalizedPrefix) -or $normalizedPrefix -match '\\' -or $normalizedPrefix -match '(^|/)\.\.?(/|$)') {
        throw "Release path prefix '$PathPrefix' must be a relative forward-slash path inside the repository."
    }

    return @{
        Repo       = $Repo
        Ref        = $Tag
        PathPrefix = $normalizedPrefix
    }
}

function New-MarketplaceManifestContent {
    <#
    .SYNOPSIS
    Generates marketplace.json content as a hashtable.

    .DESCRIPTION
    Creates a hashtable representing the marketplace manifest with repository
    metadata, owner information, and plugin entries. Matches the schema used
    by github/awesome-copilot.

    Entry sources take the bare local package-name form by default. Supplying a
    release locator emits object sources that resolve the package from an
    immutable ref in the source repository.

    .PARAMETER RepoName
    Repository name used as the marketplace name.

    .PARAMETER Description
    Short description of the repository.

    .PARAMETER Version
    Semantic version string from package.json.

    .PARAMETER OwnerName
    Organization or individual owning the repository.

    .PARAMETER Plugins
    Array of ordered hashtables with name, description, and version keys
    from New-PluginManifestContent.

    .PARAMETER ReleaseLocator
    Optional. Locator from New-PluginReleaseLocator. When supplied, entries
    carry object sources instead of bare local package names.

    .OUTPUTS
    [hashtable] Marketplace manifest with name, metadata, owner, and plugins keys.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$OwnerName,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$Plugins,

        [Parameter(Mandatory = $false)]
        [hashtable]$ReleaseLocator
    )

    $useLocator = $null -ne $ReleaseLocator -and $ReleaseLocator.Count -gt 0

    $pluginEntries = @()
    foreach ($plugin in $Plugins) {
        $source = if ($useLocator) {
            [ordered]@{
                source = 'github'
                repo   = $ReleaseLocator.Repo
                path   = "$($ReleaseLocator.PathPrefix)/$($plugin.name)"
                ref    = $ReleaseLocator.Ref
            }
        }
        else {
            $plugin.name
        }

        $pluginEntries += [ordered]@{
            name        = $plugin.name
            source      = $source
            description = $plugin.description
            version     = $plugin.version
        }
    }

    return [ordered]@{
        name     = $RepoName
        metadata = [ordered]@{
            description = $Description
            version     = $Version
            pluginRoot  = './plugins'
        }
        owner    = [ordered]@{
            name = $OwnerName
        }
        plugins  = $pluginEntries
    }
}

function Write-MarketplaceManifest {
    <#
    .SYNOPSIS
    Writes the marketplace.json file to .github/plugin/.

    .DESCRIPTION
    Assembles plugin metadata from generated collections and writes the
    marketplace manifest to .github/plugin/marketplace.json. Creates the
    directory when it does not exist.

    .PARAMETER RepoRoot
    Absolute path to the repository root directory.

    .PARAMETER Collections
    Array of collection manifest hashtables with id and description.

    .PARAMETER ReleaseLocator
    Optional. Locator from New-PluginReleaseLocator. Emits object sources and
    requires an explicit OutputPath so the production catalog is never rewritten
    by generation; catalog cutover is a separate reviewed change.

    .PARAMETER OutputPath
    Optional. Destination path, absolute or relative to RepoRoot. Defaults to
    the production catalog at .github/plugin/marketplace.json.

    .PARAMETER DryRun
    When specified, logs the action without writing to disk.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$Collections,

        [Parameter(Mandatory = $false)]
        [hashtable]$ReleaseLocator,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [switch]$DryRun
    )

    $useLocator = $null -ne $ReleaseLocator -and $ReleaseLocator.Count -gt 0

    $productionPath = Join-Path -Path $RepoRoot -ChildPath '.github' -AdditionalChildPath 'plugin', 'marketplace.json'
    $resolvedOutputPath = if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $productionPath
    }
    elseif ([System.IO.Path]::IsPathRooted($OutputPath)) {
        $OutputPath
    }
    else {
        Join-Path -Path $RepoRoot -ChildPath $OutputPath
    }

    if ($useLocator) {
        if ([string]::IsNullOrWhiteSpace($OutputPath)) {
            throw 'Locator-aware marketplace generation requires an explicit -OutputPath. Generation does not update the production catalog.'
        }

        if ([System.IO.Path]::GetFullPath($resolvedOutputPath) -eq [System.IO.Path]::GetFullPath($productionPath)) {
            throw "Locator-aware marketplace generation must not write the production catalog at $productionPath."
        }
    }

    $packageJsonPath = Join-Path -Path $RepoRoot -ChildPath 'package.json'
    $packageJson = Get-Content -Path $packageJsonPath -Raw | ConvertFrom-Json

    $plugins = @()
    foreach ($collection in ($Collections | Sort-Object { $_.id })) {
        $plugins += New-PluginManifestContent `
            -CollectionId $collection.id `
            -Description $collection.description `
            -Version $packageJson.version
    }

    $manifestArgs = @{
        RepoName    = $packageJson.name
        Description = $packageJson.description
        Version     = $packageJson.version
        OwnerName   = $packageJson.author
        Plugins     = $plugins
    }
    if ($useLocator) {
        $manifestArgs['ReleaseLocator'] = $ReleaseLocator
    }

    $manifest = New-MarketplaceManifestContent @manifestArgs

    $outputDir = Split-Path -Path $resolvedOutputPath -Parent

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would write marketplace.json at $resolvedOutputPath" -ForegroundColor Yellow
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path -Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $manifestJson = $manifest | ConvertTo-Json -Depth 10
    Set-ContentIfChanged -Path $resolvedOutputPath -Value $manifestJson | Out-Null
    Write-Host "  Marketplace manifest: $resolvedOutputPath" -ForegroundColor Green
}

function Test-PluginGitRefName {
    <#
    .SYNOPSIS
    Tests whether a string is a usable git reference name.

    .PARAMETER Name
    Candidate branch or tag name.

    .OUTPUTS
    [bool] True when the name is a valid git reference.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }

    if ($Name -match '[\s~^:?*\[\\]' -or $Name -match '\.\.' -or $Name -match '@\{') {
        return $false
    }

    if ($Name.StartsWith('-') -or $Name.StartsWith('/') -or $Name.EndsWith('/') -or $Name.EndsWith('.')) {
        return $false
    }

    foreach ($segment in ($Name -split '/')) {
        if ([string]::IsNullOrEmpty($segment) -or $segment.StartsWith('.') -or $segment.EndsWith('.lock')) {
            return $false
        }
    }

    return $true
}

function Assert-PluginSnapshotTarget {
    <#
    .SYNOPSIS
    Validates the disposable branch and tag a snapshot publish may write.

    .DESCRIPTION
    Snapshot publication is only permitted against disposable references. The
    moving release branch, immutable 'plugins-v<version>' tags, and the default
    branch are protected and can never be named as targets. Tags are immutable,
    so an existing tag is refused rather than overwritten.

    .PARAMETER Branch
    Target branch for the snapshot commit.

    .PARAMETER Tag
    Target tag for the snapshot commit.

    .PARAMETER ExistingRefs
    Reference names that already exist on the remote, short or fully qualified.

    .PARAMETER DisposablePrefix
    Required prefix identifying a disposable reference.

    .OUTPUTS
    [hashtable] Validated target with Branch, Tag, and RefSpecs keys.

    .EXAMPLE
    Assert-PluginSnapshotTarget -Branch 'plugins-snapshot/run-42' -Tag 'plugins-snapshot/run-42-tag'
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Branch,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Tag,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$ExistingRefs = @(),

        [Parameter(Mandatory = $false)]
        [string]$DisposablePrefix = 'plugins-snapshot/'
    )

    $protectedBranches = @('main', 'release/plugins')
    $productionTagPattern = '^plugins-v\d+\.\d+\.\d+'

    foreach ($target in @(@{ Kind = 'branch'; Value = $Branch }, @{ Kind = 'tag'; Value = $Tag })) {
        if (-not (Test-PluginGitRefName -Name $target.Value)) {
            throw "Snapshot $($target.Kind) '$($target.Value)' is not a valid git reference name."
        }

        if ($protectedBranches -contains $target.Value -or $target.Value -match $productionTagPattern) {
            throw "Snapshot $($target.Kind) '$($target.Value)' targets a protected production reference and is refused."
        }

        if (-not $target.Value.StartsWith($DisposablePrefix)) {
            throw "Snapshot $($target.Kind) '$($target.Value)' must start with the disposable prefix '$DisposablePrefix'."
        }
    }

    if ($Branch -eq $Tag) {
        throw "Snapshot branch and tag must differ; both are '$Branch'."
    }

    $normalizedExisting = @($ExistingRefs | ForEach-Object { ($_ -replace '^refs/(heads|tags)/', '').Trim() })
    if ($normalizedExisting -contains $Tag) {
        throw "Snapshot tag '$Tag' already exists. Tags are immutable and are never overwritten."
    }

    return @{
        Branch   = $Branch
        Tag      = $Tag
        RefSpecs = @("HEAD:refs/heads/$Branch", "refs/tags/$Tag")
    }
}

function New-GenerateResult {
    <#
    .SYNOPSIS
    Creates a standardized result object.

    .DESCRIPTION
    Returns a hashtable representing the outcome of a plugin generation run
    with success status, plugin count, and optional error message.

    .PARAMETER Success
    Whether the operation succeeded.

    .PARAMETER PluginCount
    Number of plugins generated.

    .PARAMETER ErrorMessage
    Optional error message when Success is $false.

    .OUTPUTS
    [hashtable] Result with Success, PluginCount, and ErrorMessage keys.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Success,

        [Parameter(Mandatory = $true)]
        [int]$PluginCount,

        [Parameter(Mandatory = $false)]
        [string]$ErrorMessage = ''
    )

    return @{
        Success      = $Success
        PluginCount  = $PluginCount
        ErrorMessage = $ErrorMessage
    }
}

# ---------------------------------------------------------------------------
# I/O Functions (file system operations)
# ---------------------------------------------------------------------------

function Get-PluginTrackedPathIndex {
    <#
    .SYNOPSIS
    Builds the git-tracked path allowlist for a repository working tree.

    .DESCRIPTION
    Reads the repository-relative paths recorded in the git index. Plugin
    materialization copies only these paths, so untracked working-tree content
    such as virtual environments, dependency directories, and bytecode caches
    can never be ingested into a generated plugin. Throws when the directory is
    not a git working tree, because materializing without the allowlist would
    silently copy that residue.

    .PARAMETER RepoRoot
    Absolute path to the repository working tree.

    .OUTPUTS
    [hashtable] Index with RepoRoot, Paths (ordered list), and Lookup (set) keys.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($RepoRoot)

    # core.quotePath=false keeps non-ASCII paths raw instead of octal-escaped.
    $gitArgs = @('-C', $resolvedRoot, '-c', 'core.quotePath=false', 'ls-files', '--cached', '--full-name')
    $output = & git @gitArgs 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to enumerate git-tracked paths in '$resolvedRoot' (git ls-files exit code $LASTEXITCODE)."
    }

    $paths = [System.Collections.Generic.List[string]]::new()
    $lookup = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    foreach ($line in @($output)) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        $normalized = ([string]$line) -replace '\\', '/'
        if ($lookup.Add($normalized)) {
            $paths.Add($normalized)
        }
    }

    return @{
        RepoRoot = $resolvedRoot
        Paths    = $paths
        Lookup   = $lookup
    }
}

function Clear-PluginLinkEntry {
    <#
    .SYNOPSIS
    Removes a symbolic link at a destination path without touching its target.

    .DESCRIPTION
    Plugin trees generated before materialization contain symbolic links. Left
    in place, a copy or directory creation would resolve through the link and
    write into the repository source. This deletes the link entry itself and
    leaves real files and directories alone.

    .PARAMETER Path
    Absolute destination path to inspect.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item -or -not $item.LinkType) {
        return
    }

    if ($item.PSIsContainer) {
        [System.IO.Directory]::Delete($item.FullName)
    }
    else {
        [System.IO.File]::Delete($item.FullName)
    }
}

function Copy-PluginFileIfChanged {
    <#
    .SYNOPSIS
    Copies a file only when the destination content differs.

    .DESCRIPTION
    Compares length then SHA256 before writing, preserving the git stat cache
    for unchanged files so repeat generations stay idempotent.

    .PARAMETER SourcePath
    Absolute path to the source file.

    .PARAMETER DestinationPath
    Absolute path to the destination file.

    .OUTPUTS
    [bool] True when the file was written, false when skipped.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    Clear-PluginLinkEntry -Path $DestinationPath

    if (Test-Path -LiteralPath $DestinationPath -PathType Leaf) {
        $sourceLength = (Get-Item -LiteralPath $SourcePath -Force).Length
        $destinationLength = (Get-Item -LiteralPath $DestinationPath -Force).Length
        if ($sourceLength -eq $destinationLength) {
            $sourceHash = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash
            $destinationHash = (Get-FileHash -LiteralPath $DestinationPath -Algorithm SHA256).Hash
            if ($sourceHash -eq $destinationHash) {
                return $false
            }
        }
    }

    Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
    return $true
}

function Copy-PluginSource {
    <#
    .SYNOPSIS
    Materializes git-tracked source content into a plugin destination.

    .DESCRIPTION
    Copies current working-tree bytes for every git-tracked path at or beneath
    SourcePath, so locally modified tracked files are included and untracked
    files are excluded. A file source produces exactly one destination file; a
    directory source reconstructs its tracked subtree beneath DestinationPath.
    Returns every destination written so callers can record complete generated
    path bookkeeping for orphan cleanup.

    .PARAMETER SourcePath
    Absolute path to the repository file or directory being materialized.

    .PARAMETER DestinationPath
    Absolute destination path: the file itself for a file source, or the
    subtree root for a directory source.

    .PARAMETER RepoRoot
    Absolute path to the repository working tree.

    .PARAMETER TrackedIndex
    Optional index from Get-PluginTrackedPathIndex. Resolved on demand when
    omitted; callers in per-item loops should supply a shared index.

    .OUTPUTS
    [string[]] Absolute destination paths written.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [hashtable]$TrackedIndex
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($RepoRoot)
    $resolvedSource = [System.IO.Path]::GetFullPath($SourcePath)
    $relativeSource = [System.IO.Path]::GetRelativePath($resolvedRoot, $resolvedSource) -replace '\\', '/'

    if ($relativeSource -eq '..' -or $relativeSource.StartsWith('../') -or [System.IO.Path]::IsPathRooted($relativeSource)) {
        throw "Source path '$SourcePath' resolves outside the repository root '$resolvedRoot'."
    }

    if (-not $TrackedIndex) {
        $TrackedIndex = Get-PluginTrackedPathIndex -RepoRoot $resolvedRoot
    }

    $isFileSource = $TrackedIndex.Lookup.Contains($relativeSource)
    $matched = [System.Collections.Generic.List[string]]::new()

    if ($isFileSource) {
        $matched.Add($relativeSource)
    }
    else {
        $prefix = "$relativeSource/"
        foreach ($tracked in $TrackedIndex.Paths) {
            if ($tracked.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                $matched.Add($tracked)
            }
        }
    }

    if ($matched.Count -eq 0) {
        Write-Warning "No git-tracked content found for source: $relativeSource"
        return @()
    }

    # Replace links left by an earlier generation before writing through them.
    $destinationParent = Split-Path -Parent $DestinationPath
    if ($destinationParent) {
        Clear-PluginLinkEntry -Path $destinationParent
    }
    Clear-PluginLinkEntry -Path $DestinationPath

    $written = [System.Collections.Generic.List[string]]::new()

    foreach ($tracked in $matched) {
        $trackedSource = Join-Path -Path $resolvedRoot -ChildPath $tracked

        if ($isFileSource) {
            $destination = $DestinationPath
        }
        else {
            $suffix = $tracked.Substring($relativeSource.Length + 1)
            $destination = [System.IO.Path]::GetFullPath(
                [System.IO.Path]::Combine($DestinationPath, $suffix)
            )
        }

        # A path can be staged while absent from the working tree; skip it
        # rather than failing the whole generation run.
        if (-not (Test-Path -LiteralPath $trackedSource -PathType Leaf)) {
            Write-Warning "Tracked source missing from the working tree: $tracked"
            continue
        }

        $destinationDir = Split-Path -Parent $destination
        if ($destinationDir -and -not (Test-Path -LiteralPath $destinationDir -PathType Container)) {
            New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        }

        Copy-PluginFileIfChanged -SourcePath $trackedSource -DestinationPath $destination | Out-Null
        $written.Add($destination)
    }

    return $written.ToArray()
}

function Write-PluginHookArtifact {
    <#
    .SYNOPSIS
    Materializes a hook manifest and its sibling script directory into a plugin.

    .DESCRIPTION
    Hook command paths in the source manifest are repository-root relative
    (for example .github/hooks/shared/telemetry/telemetry-collector.sh) so they resolve
    when the hook is auto-loaded from a checked-out repository. Inside an
    installed plugin the same scripts live under the plugin root, so this
    function writes a transformed copy of the manifest with those paths
    rewritten to the ${PLUGIN_ROOT} placeholder, then materializes the sibling
    script directory (the manifest path without its .json extension).

    .PARAMETER SourceManifest
    Absolute path to the source hook .json manifest in the repository.

    .PARAMETER DestinationManifest
    Absolute path where the transformed manifest is written in the plugin.

    .PARAMETER GeneratedFiles
    Set tracking generated paths for orphan cleanup; every materialized script
    file is added to it.

    .PARAMETER RepoRoot
    Absolute path to the repository working tree.

    .PARAMETER TrackedIndex
    Optional git-tracked path index shared across a generation run.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceManifest,

        [Parameter(Mandatory = $true)]
        [string]$DestinationManifest,

        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.HashSet[string]]$GeneratedFiles,

        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [hashtable]$TrackedIndex
    )

    # Degrade gracefully when the manifest is missing, matching how other kinds
    # warn rather than throw and fail the entire generation run.
    if (-not (Test-Path -LiteralPath $SourceManifest)) {
        Write-Warning "Hook manifest not found: $SourceManifest"
        return
    }

    # Rewrite repo-root-relative hook script paths to plugin-relative paths so
    # commands resolve from the installed plugin directory. Literal string
    # replacement avoids regex interpretation of the path and the $ placeholder.
    $manifestText = Get-Content -LiteralPath $SourceManifest -Raw -Encoding utf8
    $manifestText = $manifestText.Replace('.github/hooks/', '${PLUGIN_ROOT}/hooks/')
    Set-ContentIfChanged -Path $DestinationManifest -Value $manifestText | Out-Null

    # Materialize the sibling script directory (manifest path without .json).
    $scriptSrc = $SourceManifest -replace '\.json$', ''
    if (Test-Path -LiteralPath $scriptSrc) {
        $scriptDest = $DestinationManifest -replace '\.json$', ''
        $materialized = @(Copy-PluginSource -SourcePath $scriptSrc -DestinationPath $scriptDest `
                -RepoRoot $RepoRoot -TrackedIndex $TrackedIndex)
        foreach ($file in $materialized) {
            [void]$GeneratedFiles.Add($file)
        }
    }
}

function Write-PluginDirectory {
    <#
    .SYNOPSIS
    Creates a complete plugin directory structure from a collection.

    .DESCRIPTION
    Builds the full plugin layout under the specified plugins directory,
    including subdirectories for agents, commands, instructions, and skills.
    Each item is materialized from git-tracked repository sources into real
    files and directories. Generates plugin.json and README.md.

    .PARAMETER Collection
    Parsed collection manifest hashtable with id, name, description, and items.

    .PARAMETER PluginsDir
    Absolute path to the root plugins output directory.

    .PARAMETER RepoRoot
    Absolute path to the repository root.

    .PARAMETER Version
    Semantic version string from the repository package.json.

    .PARAMETER Maturity
        Optional collection-level maturity string. Forwarded to
        New-PluginReadmeContent for maturity notice injection.

    .PARAMETER DryRun
    When specified, logs actions without creating files or directories.

    .OUTPUTS
    [hashtable] Result with Success, AgentCount, CommandCount, InstructionCount,
    and SkillCount keys.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Collection,

        [Parameter(Mandatory = $true)]
        [string]$PluginsDir,

        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Maturity,

        [Parameter(Mandatory = $false)]
        [switch]$DryRun
    )

    $collectionId = $Collection.id
    $pluginRoot = Join-Path -Path $PluginsDir -ChildPath $collectionId

    # One index per plugin bounds git invocations while staying current for
    # callers that stage content between generations.
    $trackedIndex = if ($DryRun) { $null } else { Get-PluginTrackedPathIndex -RepoRoot $RepoRoot }

    $counts = @{
        AgentCount       = 0
        CommandCount      = 0
        InstructionCount = 0
        SkillCount       = 0
        HookCount        = 0
    }

    # Track unique directories per kind for plugin.json path arrays
    $agentDirs = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $commandDirs = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $skillDirs = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $hookFiles = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    $readmeItems = @()
    $generatedFiles = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    foreach ($item in $Collection.items) {
        $kind = $item.kind
        $sourcePath = Join-Path -Path $RepoRoot -ChildPath $item.path
        $subdir = Get-PluginSubdirectory -Kind $kind

        if ($kind -eq 'skill') {
            # Skills use the source directory name as FileName.
            $fileName = Split-Path -Leaf $item.path
            $itemName = Get-PluginItemName -FileName $fileName -Kind $kind
            $itemSubpath = Get-PluginItemSubpath -Path $item.path -Kind $kind
            if ($itemSubpath) {
                $destPath = Join-Path -Path $pluginRoot -ChildPath $subdir -AdditionalChildPath $itemSubpath, $itemName
            } else {
                $destPath = Join-Path -Path $pluginRoot -ChildPath $subdir -AdditionalChildPath $itemName
            }

            # Read frontmatter from SKILL.md for description; fall back to directory name
            $skillMdPath = Join-Path -Path $sourcePath -ChildPath 'SKILL.md'
            if (Test-Path -Path $skillMdPath) {
                $frontmatter = Get-ArtifactFrontmatter -FilePath $skillMdPath -FallbackDescription $fileName
                $description = $frontmatter.description
            }
            else {
                $description = $fileName
            }
        }
        else {
            $fileName = Split-Path -Leaf $item.path
            $itemName = Get-PluginItemName -FileName $fileName -Kind $kind
            $itemSubpath = Get-PluginItemSubpath -Path $item.path -Kind $kind
            if ($itemSubpath) {
                $destPath = Join-Path -Path $pluginRoot -ChildPath $subdir -AdditionalChildPath $itemSubpath, $itemName
            } else {
                $destPath = Join-Path -Path $pluginRoot -ChildPath $subdir -AdditionalChildPath $itemName
            }

            # Read description from the source file. Hook manifests are JSON
            # with no frontmatter, so read their top-level description field.
            $fallback = $itemName -replace '\.(md|json)$', ''
            if (-not (Test-Path -Path $sourcePath)) {
                $description = $fallback
                Write-Warning "Source file not found: $sourcePath"
            }
            elseif ($kind -eq 'hook') {
                $hookDesc = Get-ArtifactDescription -FilePath $sourcePath
                $description = if ($hookDesc) { $hookDesc } else { $fallback }
            }
            else {
                $frontmatter = Get-ArtifactFrontmatter -FilePath $sourcePath -FallbackDescription $fallback
                $description = $frontmatter.description
            }
        }

        $readmeItems += @{
            Name        = ($itemName -replace '\.md$', '') -replace '\.json$', ''
            Description = $description
            Kind        = $kind
        }

        # Update counts and collect parent directories for manifest paths
        switch ($kind) {
            'agent' {
                $counts.AgentCount++
                $parentDir = Split-Path -Parent $destPath
                $relDir = [System.IO.Path]::GetRelativePath($pluginRoot, $parentDir) -replace '\\', '/'
                [void]$agentDirs.Add("$relDir/")
            }
            'prompt' {
                $counts.CommandCount++
                $parentDir = Split-Path -Parent $destPath
                $relDir = [System.IO.Path]::GetRelativePath($pluginRoot, $parentDir) -replace '\\', '/'
                [void]$commandDirs.Add("$relDir/")
            }
            'instruction' { $counts.InstructionCount++ }
            'skill' {
                $counts.SkillCount++
                # Skills: the CLI scans for <name>/SKILL.md; point at the grandparent
                $parentDir = Split-Path -Parent $destPath
                $relDir = [System.IO.Path]::GetRelativePath($pluginRoot, $parentDir) -replace '\\', '/'
                [void]$skillDirs.Add("$relDir/")
            }
            'hook' {
                $counts.HookCount++
                $relPath = [System.IO.Path]::GetRelativePath($pluginRoot, $destPath) -replace '\\', '/'
                [void]$hookFiles.Add($relPath)
            }
        }

        [void]$generatedFiles.Add($destPath)

        if ($DryRun) {
            Write-Verbose "DryRun: Would materialize $destPath from $sourcePath"
            continue
        }

        # Hooks bundle a sibling script directory and need plugin-relative
        # command paths; other kinds materialize their source directly.
        if ($kind -eq 'hook') {
            Write-PluginHookArtifact -SourceManifest $sourcePath -DestinationManifest $destPath `
                -GeneratedFiles $generatedFiles -RepoRoot $RepoRoot -TrackedIndex $trackedIndex
        }
        else {
            $materialized = @(Copy-PluginSource -SourcePath $sourcePath -DestinationPath $destPath `
                    -RepoRoot $RepoRoot -TrackedIndex $trackedIndex)
            foreach ($file in $materialized) {
                [void]$generatedFiles.Add($file)
            }
        }
    }

    # Materialize shared resource directories (unconditional, all plugins)
    $sharedDirs = @(
        @{ Source = 'docs/templates';    Destination = 'docs/templates' }
        @{ Source = 'scripts/lib';       Destination = 'scripts/lib' }
    )

    foreach ($dir in $sharedDirs) {
        $sourcePath = Join-Path -Path $RepoRoot -ChildPath $dir.Source
        $destPath = Join-Path -Path $pluginRoot -ChildPath $dir.Destination

        if (-not (Test-Path -Path $sourcePath)) {
            Write-Warning "Shared directory not found: $sourcePath"
            continue
        }

        [void]$generatedFiles.Add($destPath)

        if ($DryRun) {
            Write-Verbose "DryRun: Would materialize shared directory $destPath from $sourcePath"
            continue
        }

        $materialized = @(Copy-PluginSource -SourcePath $sourcePath -DestinationPath $destPath `
                -RepoRoot $RepoRoot -TrackedIndex $trackedIndex)
        foreach ($file in $materialized) {
            [void]$generatedFiles.Add($file)
        }
    }

    # Generate plugin.json with explicit path arrays for CLI discovery
    $manifestDir = Join-Path -Path $pluginRoot -ChildPath '.github' -AdditionalChildPath 'plugin'
    $manifestPath = Join-Path -Path $manifestDir -ChildPath 'plugin.json'
    $manifest = New-PluginManifestContent `
        -CollectionId $collectionId `
        -Description $Collection.description `
        -Version $Version `
        -AgentPaths @($agentDirs) `
        -CommandPaths @($commandDirs) `
        -SkillPaths @($skillDirs) `
        -HookPaths @($hookFiles)
    [void]$generatedFiles.Add($manifestPath)

    if ($DryRun) {
        Write-Verbose "DryRun: Would write plugin.json at $manifestPath"
    }
    else {
        if (-not (Test-Path -Path $manifestDir)) {
            New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
        }
        $jsonContent = $manifest | ConvertTo-Json -Depth 10
        Set-ContentIfChanged -Path $manifestPath -Value $jsonContent | Out-Null
    }

    # Generate README.md
    $readmePath = Join-Path -Path $pluginRoot -ChildPath 'README.md'
    $collectionMdPath = Join-Path -Path $RepoRoot -ChildPath "collections/$collectionId.collection.md"
    $collectionContent = if (Test-Path -Path $collectionMdPath) {
        Get-Content -Path $collectionMdPath -Raw
    } else { $null }
    $readmeContent = New-PluginReadmeContent -Collection $Collection -Items $readmeItems -Maturity $Maturity -CollectionContent $collectionContent
    [void]$generatedFiles.Add($readmePath)

    if ($DryRun) {
        Write-Verbose "DryRun: Would write README.md at $readmePath"
    }
    else {
        Set-ContentIfChanged -Path $readmePath -Value $readmeContent | Out-Null
    }

    return @{
        Success          = $true
        AgentCount       = $counts.AgentCount
        CommandCount     = $counts.CommandCount
        InstructionCount = $counts.InstructionCount
        SkillCount       = $counts.SkillCount
        HookCount        = $counts.HookCount
        GeneratedFiles   = $generatedFiles
    }
}

Export-ModuleMember -Function @(
    'Assert-PluginSnapshotTarget',
    'Copy-PluginSource',
    'Get-PluginItemName',
    'Get-PluginItemSubpath',
    'Get-PluginSubdirectory',
    'Get-PluginTrackedPathIndex',
    'New-GenerateResult',
    'New-MarketplaceManifestContent',
    'New-PluginManifestContent',
    'New-PluginReadmeContent',
    'New-PluginReleaseLocator',
    'Write-MarketplaceManifest',
    'Write-PluginDirectory'
)
