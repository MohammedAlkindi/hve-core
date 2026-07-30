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
    Maps a collection item kind to the canonical plugin subdirectory.

    .PARAMETER Kind
    The artifact kind: agent, prompt, instruction, or skill.

    .OUTPUTS
    [string] The canonical plugin subdirectory.
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

    .PARAMETER RulePaths
    Optional. Array of relative directory paths containing .instructions.md files.

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
        [string[]]$RulePaths,

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

    if ($RulePaths -and $RulePaths.Count -gt 0) {
        $manifest['rules'] = @($RulePaths | Sort-Object)
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

function New-MarketplaceManifestContent {
    <#
    .SYNOPSIS
    Generates marketplace.json content as a hashtable.

    .DESCRIPTION
    Creates a hashtable representing the marketplace manifest with repository
    metadata, owner information, and plugin entries. Matches the schema used
    by github/awesome-copilot.

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
        [array]$Plugins
    )

    $pluginEntries = @()
    foreach ($plugin in $Plugins) {
        $pluginEntries += [ordered]@{
            name        = $plugin.name
            source      = $plugin.name
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
        [switch]$DryRun
    )

    $packageJsonPath = Join-Path -Path $RepoRoot -ChildPath 'package.json'
    $packageJson = Get-Content -Path $packageJsonPath -Raw | ConvertFrom-Json

    $plugins = @()
    foreach ($collection in ($Collections | Sort-Object { $_.id })) {
        $plugins += New-PluginManifestContent `
            -CollectionId $collection.id `
            -Description $collection.description `
            -Version $packageJson.version
    }

    $manifest = New-MarketplaceManifestContent `
        -RepoName $packageJson.name `
        -Description $packageJson.description `
        -Version $packageJson.version `
        -OwnerName $packageJson.author `
        -Plugins $plugins

    $outputDir = Join-Path -Path $RepoRoot -ChildPath '.github' -AdditionalChildPath 'plugin'
    $outputPath = Join-Path -Path $outputDir -ChildPath 'marketplace.json'

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would write marketplace.json at $outputPath" -ForegroundColor Yellow
        return
    }

    if (-not (Test-Path -Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $manifestJson = $manifest | ConvertTo-Json -Depth 10
    Set-ContentIfChanged -Path $outputPath -Value $manifestJson | Out-Null
    Write-Host "  Marketplace manifest: $outputPath" -ForegroundColor Green
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

function Write-PluginDirectory {
    <#
    .SYNOPSIS
    Generates a plugin manifest and README from collection sources.

    .DESCRIPTION
    Creates .github/plugin/plugin.json and README.md under the plugin root.
    Component paths resolve from the marketplace repository root to canonical
    artifacts in its .github directory. README.md initially mirrors the
    collection markdown so its generation can evolve independently later.

    .PARAMETER Collection
    Parsed collection manifest hashtable with id, description, and items.

    .PARAMETER PluginsDir
    Absolute path to the root plugins output directory.

    .PARAMETER RepoRoot
    Absolute path to the repository root.

    .PARAMETER Version
    Semantic version string from the repository package.json.

    .PARAMETER Maturity
    Accepted for compatibility with the generation orchestrator.

    .PARAMETER DryRun
    When specified, validates inputs without writing the manifest.

    .OUTPUTS
    [hashtable] Generation result and artifact counts.
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

    $pathComparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    $canonicalRepoRoot = [System.IO.Path]::TrimEndingDirectorySeparator(
        [System.IO.Path]::GetFullPath($RepoRoot)
    )
    $repoPrefix = $canonicalRepoRoot + [System.IO.Path]::DirectorySeparatorChar
    $componentRoot = Join-Path -Path $canonicalRepoRoot -ChildPath '.github'
    $componentPrefix = $componentRoot + [System.IO.Path]::DirectorySeparatorChar
    $pluginRoot = Join-Path -Path $PluginsDir -ChildPath $Collection.id

    $agentDirs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $commandDirs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $skillPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $ruleDirs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $hookFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $counts = @{
        AgentCount       = 0
        CommandCount     = 0
        InstructionCount = 0
        SkillCount       = 0
        HookCount        = 0
    }

    foreach ($item in $Collection.items) {
        $sourcePath = [System.IO.Path]::GetFullPath(
            (Join-Path -Path $canonicalRepoRoot -ChildPath ([string]$item.path))
        )
        if (-not $sourcePath.StartsWith($repoPrefix, $pathComparison)) {
            throw "Plugin source must be inside the repository root: $sourcePath"
        }
        if (-not $sourcePath.StartsWith($componentPrefix, $pathComparison)) {
            throw "Plugin source must be inside the repository .github directory: $sourcePath"
        }
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            throw "Plugin source not found: $sourcePath"
        }

        $sourceItem = Get-Item -LiteralPath $sourcePath -Force
        $componentPath = switch ([string]$item.kind) {
            'agent' {
                $counts.AgentCount++
                [System.IO.Path]::GetRelativePath($canonicalRepoRoot, $sourceItem.DirectoryName)
            }
            'prompt' {
                $counts.CommandCount++
                [System.IO.Path]::GetRelativePath($canonicalRepoRoot, $sourceItem.DirectoryName)
            }
            'instruction' {
                $counts.InstructionCount++
                [System.IO.Path]::GetRelativePath($canonicalRepoRoot, $sourceItem.DirectoryName)
            }
            'skill' {
                $counts.SkillCount++
                [System.IO.Path]::GetRelativePath($canonicalRepoRoot, $sourceItem.FullName)
            }
            'hook' {
                $counts.HookCount++
                [System.IO.Path]::GetRelativePath($canonicalRepoRoot, $sourceItem.FullName)
            }
            default { throw "Unsupported plugin item kind: $($item.kind)" }
        }
        $componentPath = $componentPath -replace '\\', '/'

        switch ([string]$item.kind) {
            'agent' { [void]$agentDirs.Add("$componentPath/") }
            'prompt' { [void]$commandDirs.Add("$componentPath/") }
            'instruction' { [void]$ruleDirs.Add("$componentPath/") }
            'skill' { [void]$skillPaths.Add($componentPath) }
            'hook' { [void]$hookFiles.Add($componentPath) }
        }
    }

    $manifestDir = Join-Path -Path $pluginRoot -ChildPath '.github/plugin'
    $manifestPath = Join-Path -Path $manifestDir -ChildPath 'plugin.json'
    $collectionReadmePath = Join-Path -Path $canonicalRepoRoot -ChildPath "collections/$($Collection.id).collection.md"
    if (-not (Test-Path -LiteralPath $collectionReadmePath -PathType Leaf)) {
        throw "Plugin collection README source not found: $collectionReadmePath"
    }
    $readmePath = Join-Path -Path $pluginRoot -ChildPath 'README.md'
    $readmeContent = Get-Content -LiteralPath $collectionReadmePath -Raw -Encoding utf8
    $manifest = New-PluginManifestContent `
        -CollectionId $Collection.id `
        -Description $Collection.description `
        -Version $Version `
        -AgentPaths @($agentDirs) `
        -CommandPaths @($commandDirs) `
        -SkillPaths @($skillPaths) `
        -RulePaths @($ruleDirs) `
        -HookPaths @($hookFiles)

    if ($DryRun) {
        Write-Verbose "DryRun: Would write plugin.json at $manifestPath"
        Write-Verbose "DryRun: Would write README.md at $readmePath"
    }
    else {
        New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
        $jsonContent = $manifest | ConvertTo-Json -Depth 10
        Set-ContentIfChanged -Path $manifestPath -Value $jsonContent | Out-Null
        Set-ContentIfChanged -Path $readmePath -Value $readmeContent | Out-Null
    }

    return @{
        Success              = $true
        AgentCount           = $counts.AgentCount
        CommandCount         = $counts.CommandCount
        InstructionCount     = $counts.InstructionCount
        SkillCount           = $counts.SkillCount
        HookCount            = $counts.HookCount
        GeneratedFiles       = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
        GeneratedDirectories = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
    }
}

Export-ModuleMember -Function @(
    'Get-PluginItemName',
    'Get-PluginItemSubpath',
    'Get-PluginSubdirectory',
    'New-GenerateResult',
    'New-MarketplaceManifestContent',
    'New-PluginManifestContent',
    'Write-MarketplaceManifest',
    'Write-PluginDirectory'
)
