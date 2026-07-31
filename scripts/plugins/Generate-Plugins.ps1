#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Generates Copilot CLI plugin directories from collection manifests.

.DESCRIPTION
    Reads collection YAML manifests from the collections/ directory and generates
    plugin directories under plugins/ containing materialized copies of the
    git-tracked source artifacts, plugin.json manifests, and auto-generated
    README files.

    Supports generating all plugins or specific collections. Use -Refresh to
    regenerate existing plugins (deletes and recreates).

.PARAMETER CollectionIds
    Optional. Array of collection IDs to generate. Generates all when omitted.

.PARAMETER Refresh
    Optional. Deletes and recreates existing plugin directories.

.PARAMETER DryRun
    Optional. Shows what would be done without making changes.

.PARAMETER Channel
    Optional. Release channel controlling eligible item maturities.
    Stable includes only stable items. PreRelease includes stable, preview,
    and experimental. Deprecated and removed are excluded from both channels.

.PARAMETER MaxTotalSizeMB
    Optional. Ceiling in megabytes for the total generated plugins/ tree.
    Generation fails and names the largest plugins when the ceiling is
    exceeded, catching accidental ingestion of large or undeclared trees.

.PARAMETER ReleaseTag
    Optional. Immutable 'plugins-v<version>' tag. Emits object-form marketplace
    sources that resolve each package from that tag instead of local bare
    sources. Requires -MarketplaceOutputPath: generation never rewrites the
    production catalog with remote locators.

.PARAMETER MarketplaceOutputPath
    Optional. Destination for the generated marketplace manifest, absolute or
    relative to the repository root. Defaults to the production catalog.

.EXAMPLE
    ./Generate-Plugins.ps1
    # Generates all plugins (default: all + refresh)

.EXAMPLE
    ./Generate-Plugins.ps1 -CollectionIds rpi,github
    # Generates only the rpi and github plugins

.EXAMPLE
    ./Generate-Plugins.ps1 -DryRun
    # Shows what would be generated without making changes

.EXAMPLE
    ./Generate-Plugins.ps1 -Channel Stable
    # Generates plugins with stable-only items

.EXAMPLE
    ./Generate-Plugins.ps1 -ReleaseTag plugins-v1.2.3 -MarketplaceOutputPath out/marketplace.json
    # Writes a tag-pinned catalog snapshot without touching the production catalog

.NOTES
    Dependencies: PowerShell-Yaml module, scripts/plugins/Modules/PluginHelpers.psm1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$CollectionIds,

    [Parameter(Mandatory = $false)]
    [switch]$Refresh,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Stable', 'PreRelease')]
    [string]$Channel = 'PreRelease',

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 10240)]
    [int]$MaxTotalSizeMB = 40,

    [Parameter(Mandatory = $false)]
    [string]$ReleaseTag,

    [Parameter(Mandatory = $false)]
    [string]$MarketplaceOutputPath
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Modules/PluginHelpers.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../collections/Modules/CollectionHelpers.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../lib/Modules/CIHelpers.psm1') -Force

#region Orchestration

function Get-AllowedCollectionMaturities {
    <#
    .SYNOPSIS
        Returns allowed collection item maturities for a channel.

    .PARAMETER Channel
        Release channel ('Stable' or 'PreRelease').

    .OUTPUTS
        [string[]] Allowed maturity values for collection items.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Stable', 'PreRelease')]
        [string]$Channel
    )

    if ($Channel -eq 'Stable') {
        return @('stable')
    }

    return @('stable', 'preview', 'experimental')
}

function Select-CollectionItemsByChannel {
    <#
    .SYNOPSIS
        Filters collection items by channel using item maturity metadata.

    .PARAMETER Collection
        Collection manifest hashtable.

    .PARAMETER Channel
        Release channel ('Stable' or 'PreRelease').

    .OUTPUTS
        [hashtable] Collection clone with filtered items.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Collection,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Stable', 'PreRelease')]
        [string]$Channel
    )

    $allowedMaturities = Get-AllowedCollectionMaturities -Channel $Channel
    $filteredItems = @()

    foreach ($item in $Collection.items) {
        $effectiveMaturity = Resolve-CollectionItemMaturity -Maturity $item.maturity
        if ($effectiveMaturity -eq 'removed') {
            Write-Verbose "Skipping removed item: $($item.path)"
            continue
        }
        if ($allowedMaturities -contains $effectiveMaturity) {
            $filteredItems += $item
        }
    }

    $filteredCollection = @{}
    foreach ($key in $Collection.Keys) {
        $filteredCollection[$key] = $Collection[$key]
    }
    $filteredCollection['items'] = $filteredItems

    return $filteredCollection
}

function Assert-PluginOutputSize {
    <#
    .SYNOPSIS
        Fails generation when the materialized plugins tree exceeds a ceiling.

    .DESCRIPTION
        Measures the total byte size of the generated plugins directory and
        throws when it exceeds MaxTotalSizeMB. The failure names the largest
        plugins so an accidental ingestion of a large or undeclared tree is
        immediately attributable.

    .PARAMETER PluginsDir
        Absolute path to the generated plugins output directory.

    .PARAMETER MaxTotalSizeMB
        Ceiling in megabytes for the combined generated output.

    .OUTPUTS
        [hashtable] Report with TotalMB and Plugins (name/size pairs) keys.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PluginsDir,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 10240)]
        [int]$MaxTotalSizeMB
    )

    $perPlugin = [System.Collections.Generic.List[hashtable]]::new()
    $totalBytes = [long]0

    if (Test-Path -LiteralPath $PluginsDir -PathType Container) {
        foreach ($pluginDir in Get-ChildItem -LiteralPath $PluginsDir -Directory) {
            $bytes = [long]0
            foreach ($file in Get-ChildItem -LiteralPath $pluginDir.FullName -File -Recurse -Force) {
                $bytes += $file.Length
            }
            $totalBytes += $bytes
            $perPlugin.Add(@{ Name = $pluginDir.Name; Bytes = $bytes })
        }
    }

    $totalMB = $totalBytes / 1MB
    $report = @{
        TotalMB = $totalMB
        Plugins = @($perPlugin | Sort-Object { -$_.Bytes })
    }

    if ($totalMB -gt $MaxTotalSizeMB) {
        $offenders = @($report.Plugins | Select-Object -First 3 | ForEach-Object {
                "{0} ({1:N1} MB)" -f $_.Name, ($_.Bytes / 1MB)
            })
        throw ("Generated plugins output is {0:N1} MB, exceeding the {1} MB ceiling. Largest plugins: {2}." -f `
                $totalMB, $MaxTotalSizeMB, ($offenders -join ', '))
    }

    return $report
}

function Invoke-PluginGeneration {
    <#
    .SYNOPSIS
        Orchestrates plugin directory generation from collection manifests.

    .DESCRIPTION
        Loads collection manifests from the collections/ directory, optionally
        filters to specified IDs, and generates plugin directory structures
        under plugins/. Each plugin receives materialized copies of the
        git-tracked source artifacts, a plugin.json manifest, and an
        auto-generated README.

    .PARAMETER RepoRoot
        Absolute path to the repository root directory.

    .PARAMETER CollectionIds
        Optional. Array of collection IDs to generate. Generates all when omitted.

    .PARAMETER Refresh
        When specified, removes existing plugin directories before regenerating.

    .PARAMETER DryRun
        When specified, logs actions without creating files or directories.

    .PARAMETER Channel
        Release channel controlling item maturity eligibility.

    .PARAMETER MaxTotalSizeMB
        Ceiling in megabytes for the total generated plugins/ tree.

    .PARAMETER ReleaseTag
        Optional immutable 'plugins-v<version>' tag producing object-form
        marketplace sources.

    .PARAMETER MarketplaceOutputPath
        Optional destination for the generated marketplace manifest.

    .OUTPUTS
        Hashtable with Success, PluginCount, and ErrorMessage keys
        via New-GenerateResult.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot,

        [Parameter(Mandatory = $false)]
        [string[]]$CollectionIds,

        [Parameter(Mandatory = $false)]
        [switch]$Refresh,

        [Parameter(Mandatory = $false)]
        [switch]$DryRun,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Stable', 'PreRelease')]
        [string]$Channel = 'PreRelease',

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 10240)]
        [int]$MaxTotalSizeMB = 40,

        [Parameter(Mandatory = $false)]
        [string]$ReleaseTag,

        [Parameter(Mandatory = $false)]
        [string]$MarketplaceOutputPath
    )

    $releaseLocator = $null
    if (-not [string]::IsNullOrWhiteSpace($ReleaseTag)) {
        $releaseLocator = New-PluginReleaseLocator -Tag $ReleaseTag
    }

    $collectionsDir = Join-Path -Path $RepoRoot -ChildPath 'collections'
    $pluginsDir = Join-Path -Path $RepoRoot -ChildPath 'plugins'

    # Read repo version from package.json for plugin manifests
    $packageJsonPath = Join-Path -Path $RepoRoot -ChildPath 'package.json'
    $repoVersion = (Get-Content -Path $packageJsonPath -Raw | ConvertFrom-Json).version

    # Auto-update hve-core-all collection with discovered artifacts
    $updateResult = Update-HveCoreAllCollection -RepoRoot $RepoRoot -DryRun:$DryRun
    Write-Verbose "hve-core-all updated: $($updateResult.ItemCount) items ($($updateResult.AddedCount) added, $($updateResult.RemovedCount) removed)"

    # Load all collection manifests
    $allCollections = Get-AllCollections -CollectionsDir $collectionsDir

    if ($allCollections.Count -eq 0) {
        Write-Warning 'No collection manifests found in collections/'
        return New-GenerateResult -Success $true -PluginCount 0
    }

    # Filter to requested IDs when provided
    if ($CollectionIds -and $CollectionIds.Count -gt 0) {
        $filtered = @($allCollections | Where-Object { $CollectionIds -contains $_.id })
        $missing = @($CollectionIds | Where-Object { $_ -notin ($allCollections | ForEach-Object { $_.id }) })
        if ($missing.Count -gt 0) {
            Write-Warning "Collections not found: $($missing -join ', ')"
        }
        $allCollections = $filtered
    }

    Write-Host "`n=== Plugin Generation ===" -ForegroundColor Cyan
    Write-Host "Collections: $($allCollections.Count)"
    Write-Host "Channel: $Channel"
    Write-Host "Plugins dir: $pluginsDir"
    if ($DryRun) {
        Write-Host '[DRY RUN] No changes will be made' -ForegroundColor Yellow
    }

    $generated = 0
    $totalAgents = 0
    $totalCommands = 0
    $totalInstructions = 0
    $totalSkills = 0
    $totalHooks = 0

    foreach ($collection in $allCollections) {
        $id = $collection.id
        $pluginDir = Join-Path -Path $pluginsDir -ChildPath $id

        # Skip deprecated collections
        $collectionMaturity = if ($collection.ContainsKey('maturity') -and $collection.maturity) {
            [string]$collection.maturity
        } else { 'stable' }

        if ($collectionMaturity -eq 'deprecated') {
            Write-Verbose "Skipping deprecated collection: $id"
            continue
        }

        if ($collectionMaturity -eq 'removed') {
            Write-Verbose "Skipping removed collection: $id"
            continue
        }

        # Generate plugin directory structure (overwrites in place)
        $filteredCollection = Select-CollectionItemsByChannel -Collection $collection -Channel $Channel

        # Refresh collection.md before generating the plugin README so the
        # embedded Overview block uses current artifact descriptions.
        if (-not $DryRun) {
            $collectionMdPath = Join-Path $collectionsDir "$id.collection.md"
            if (Test-Path $collectionMdPath) {
                $bodyContent = Get-Content -Path $collectionMdPath -Raw
                $parsed = Split-CollectionMdByMarkers -Content $bodyContent

                if ($parsed.HasMarkers) {
                    $agents = @()
                    $prompts = @()
                    $instructions = @()
                    $skills = @()
                    $hooks = @()

                    foreach ($item in $filteredCollection.items) {
                        if (-not $item.ContainsKey('kind') -or -not $item.ContainsKey('path')) {
                            continue
                        }
                        $kind = [string]$item.kind
                        $path = [string]$item.path
                        $artifactName = Get-CollectionArtifactKey -Kind $kind -Path $path

                        $resolvedPath = Join-Path $RepoRoot ($path -replace '^\./', '')
                        if ($kind -eq 'skill') {
                            $resolvedPath = Join-Path $resolvedPath 'SKILL.md'
                        }
                        $artifactDesc = Get-ArtifactDescription -FilePath $resolvedPath

                        $entry = @{ Name = $artifactName; Description = $artifactDesc }
                        switch ($kind) {
                            'agent' { $agents += $entry }
                            'prompt' { $prompts += $entry }
                            'instruction' { $instructions += $entry }
                            'skill' { $skills += $entry }
                            'hook' { $hooks += $entry }
                        }
                    }

                    $artifactSections = [System.Text.StringBuilder]::new()

                    foreach ($section in @(
                        @{ Title = 'Chat Agents'; Items = $agents },
                        @{ Title = 'Prompts'; Items = $prompts },
                        @{ Title = 'Instructions'; Items = $instructions },
                        @{ Title = 'Skills'; Items = $skills },
                        @{ Title = 'Hooks'; Items = $hooks }
                    )) {
                        if ($section.Items.Count -eq 0) { continue }

                        $null = $artifactSections.AppendLine("### $($section.Title)")
                        $null = $artifactSections.AppendLine()
                        $null = $artifactSections.AppendLine('| Name | Description |')
                        $null = $artifactSections.AppendLine('|------|-------------|')
                        foreach ($entry in ($section.Items | Sort-Object { $_.Name })) {
                            $null = $artifactSections.AppendLine("| **$($entry.Name)** | $($entry.Description) |")
                        }
                        $null = $artifactSections.AppendLine()
                    }

                    $generatedBlock = $artifactSections.ToString().TrimEnd()
                    $intro = $parsed.Intro.TrimEnd()
                    if ($intro -notmatch '(?m)^## Included Artifacts\s*$') {
                        $intro = "$intro`n`n## Included Artifacts"
                    }
                    $updatedCollectionMd = "$intro`n`n$($CollectionMdBeginMarker)`n`n$generatedBlock`n`n$($CollectionMdEndMarker)"
                    if (-not [string]::IsNullOrWhiteSpace($parsed.Footer)) {
                        $updatedCollectionMd += "`n`n$($parsed.Footer.TrimEnd())"
                    }
                    $updatedCollectionMd += "`n"
                    Set-ContentIfChanged -Path $collectionMdPath -Value $updatedCollectionMd
                }
            }
        }

        $result = Write-PluginDirectory -Collection $filteredCollection `
            -PluginsDir $pluginsDir `
            -RepoRoot $RepoRoot `
            -Version $repoVersion `
            -Maturity $collectionMaturity `
            -DryRun:$DryRun

        # Orphan cleanup in Refresh mode. Generated directories are real trees,
        # so the walker descends into every one and compares each contained file
        # against the complete generated-path set recorded during materialization.
        if ($Refresh -and (Test-Path -LiteralPath $pluginDir)) {
            $generatedFiles = $result.GeneratedFiles
            $existingFiles = [System.Collections.Generic.List[string]]::new()
            $scanQueue = [System.Collections.Generic.Queue[string]]::new()
            $scanQueue.Enqueue($pluginDir)
            while ($scanQueue.Count -gt 0) {
                $currentDir = $scanQueue.Dequeue()
                foreach ($entry in Get-ChildItem -LiteralPath $currentDir -Force) {
                    if ($entry.PSIsContainer) {
                        $scanQueue.Enqueue($entry.FullName)
                    }
                    else {
                        $existingFiles.Add($entry.FullName)
                    }
                }
            }
            foreach ($existingFile in $existingFiles) {
                if (-not $generatedFiles.Contains($existingFile)) {
                    if ($DryRun) {
                        Write-Host "  [DRY RUN] Would remove orphan: $existingFile" -ForegroundColor Yellow
                    }
                    else {
                        Remove-Item -LiteralPath $existingFile -Force -ErrorAction Stop
                        Write-Verbose "Removed orphan file: $existingFile"
                    }
                }
            }
            # Remove empty directories bottom-up
            if (-not $DryRun) {
                Get-ChildItem -LiteralPath $pluginDir -Recurse -Directory |
                    Sort-Object { $_.FullName.Length } -Descending |
                    Where-Object { @(Get-ChildItem -LiteralPath $_.FullName -Force).Count -eq 0 } |
                    ForEach-Object {
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                        Write-Verbose "Removed empty directory: $($_.FullName)"
                    }
            }
        }

        $itemCount = $filteredCollection.items.Count
        $totalAgents += $result.AgentCount
        $totalCommands += $result.CommandCount
        $totalInstructions += $result.InstructionCount
        $totalSkills += $result.SkillCount
        $totalHooks += $result.HookCount
        $generated++

        Write-Host "  $id ($itemCount items)" -ForegroundColor Green
    }

    # Generate marketplace.json from all collections
    $marketplaceArgs = @{
        RepoRoot    = $RepoRoot
        Collections = $allCollections
        DryRun      = $DryRun
    }
    if ($releaseLocator) {
        $marketplaceArgs['ReleaseLocator'] = $releaseLocator
    }
    if (-not [string]::IsNullOrWhiteSpace($MarketplaceOutputPath)) {
        $marketplaceArgs['OutputPath'] = $MarketplaceOutputPath
    }
    Write-MarketplaceManifest @marketplaceArgs

    if (-not $DryRun) {
        $sizeReport = Assert-PluginOutputSize -PluginsDir $pluginsDir -MaxTotalSizeMB $MaxTotalSizeMB
        Write-Host ("  Generated size: {0:N1} MB (ceiling {1} MB)" -f $sizeReport.TotalMB, $MaxTotalSizeMB)
    }

    Write-Host "`n--- Summary ---" -ForegroundColor Cyan
    Write-Host "  Plugins generated: $generated"
    Write-Host "  Agents: $totalAgents"
    Write-Host "  Commands: $totalCommands"
    Write-Host "  Instructions: $totalInstructions"
    Write-Host "  Skills: $totalSkills"
    Write-Host "  Hooks: $totalHooks"

    return New-GenerateResult -Success $true -PluginCount $generated
}

#endregion Orchestration

#region Main Execution

function Start-PluginGeneration {
    <#
    .SYNOPSIS
        Entry point for CLI invocation. Returns 0 on success, 1 on failure.

    .PARAMETER ScriptPath
        Absolute path to this script file, used to resolve the repo root.

    .PARAMETER CollectionIds
        Optional collection IDs forwarded to Invoke-PluginGeneration.

    .PARAMETER Refresh
        Forwarded refresh switch.

    .PARAMETER DryRun
        Forwarded dry-run switch.

    .PARAMETER Channel
        Forwarded channel parameter.

    .PARAMETER MaxTotalSizeMB
        Forwarded generated-output size ceiling in megabytes.

    .PARAMETER ReleaseTag
        Forwarded immutable release tag.

    .PARAMETER MarketplaceOutputPath
        Forwarded marketplace manifest destination.

    .OUTPUTS
        [int] Exit code: 0 for success, 1 for failure.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $false)]
        [string[]]$CollectionIds,

        [Parameter(Mandatory = $false)]
        [switch]$Refresh,

        [Parameter(Mandatory = $false)]
        [switch]$DryRun,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Stable', 'PreRelease')]
        [string]$Channel = 'PreRelease',

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 10240)]
        [int]$MaxTotalSizeMB = 40,

        [Parameter(Mandatory = $false)]
        [string]$ReleaseTag,

        [Parameter(Mandatory = $false)]
        [string]$MarketplaceOutputPath
    )

    try {
        # Verify PowerShell-Yaml module
        if (-not (Get-Module -ListAvailable -Name PowerShell-Yaml)) {
            throw "Required module 'PowerShell-Yaml' is not installed."
        }
        Import-Module PowerShell-Yaml -ErrorAction Stop

        # Resolve paths
        $ScriptDir = Split-Path -Parent $ScriptPath
        $RepoRoot = (Get-Item "$ScriptDir/../..").FullName

        Write-Host 'HVE Core Plugin Generator' -ForegroundColor Cyan
        Write-Host '==========================' -ForegroundColor Cyan

        # Default to all + refresh when no args
        $effectiveRefresh = $Refresh
        if (-not $CollectionIds -and -not $Refresh.IsPresent -and -not $DryRun.IsPresent) {
            $effectiveRefresh = [switch]::new($true)
        }

        $result = Invoke-PluginGeneration `
            -RepoRoot $RepoRoot `
            -CollectionIds $CollectionIds `
            -Refresh:$effectiveRefresh `
            -DryRun:$DryRun `
            -Channel $Channel `
            -MaxTotalSizeMB $MaxTotalSizeMB `
            -ReleaseTag $ReleaseTag `
            -MarketplaceOutputPath $MarketplaceOutputPath

        if (-not $result.Success) {
            throw $result.ErrorMessage
        }

        Write-Host ''
        Write-Host 'Done!' -ForegroundColor Green
        Write-Host "   $($result.PluginCount) plugin(s) generated."

        return 0
    }
    catch {
        $message = $_.Exception.Message
        Write-Error "Plugin generation failed: $message"

        if (Get-Command -Name Write-CIAnnotation -ErrorAction SilentlyContinue) {
            Write-CIAnnotation -Message $message -Level Error
        }

        return 1
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    exit (Start-PluginGeneration `
        -ScriptPath $MyInvocation.MyCommand.Path `
        -CollectionIds $CollectionIds `
        -Refresh:$Refresh `
        -DryRun:$DryRun `
        -Channel $Channel `
        -MaxTotalSizeMB $MaxTotalSizeMB `
        -ReleaseTag $ReleaseTag `
        -MarketplaceOutputPath $MarketplaceOutputPath)
}
#endregion
