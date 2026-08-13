#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Generates the tracked Copilot CLI plugin manifests from the marketplace catalog.

.DESCRIPTION
    Reads .github/plugin/marketplace.json and writes one plugin.json per catalog
    entry under plugins/<package>/. A package root delivers that manifest and
    nothing else: every component value is a manifest-relative reference to the
    canonical .github artifact, so no component bytes are copied. This script is
    the only mutating owner of plugins/; those files are never hand-edited.

    Standard component fields (agents, commands, rules, skills, hooks) are the
    sole package-definition input; the x-hve overlay contributes display name,
    package and per-component maturity, documentation, and installer profile
    metadata only, and never reaches a manifest. Every declared reference maps
    deterministically to one canonical repository source, so nothing undeclared
    is discovered by scanning.

    Supports generating all packages or specific names. Use -Refresh to retire
    package roots the catalog no longer declares.

.PARAMETER PackageNames
    Optional. Array of package names to generate. Generates all when omitted.

.PARAMETER Refresh
    Optional. Removes package roots the current catalog no longer declares.

.PARAMETER DryRun
    Optional. Shows what would be done without making changes.

.PARAMETER Check
    Optional. Non-mutating drift check. Generates the expected manifest set into
    a temporary directory, compares its exact relative path set and file bytes
    with the tracked plugins/ tree, and fails when they disagree. The tracked
    tree is never written in this mode.

.PARAMETER Channel
    Optional. Release channel controlling eligible item maturities.
    Stable includes only stable items. PreRelease includes stable, preview,
    and experimental. Deprecated and removed are excluded from both channels.

.PARAMETER CatalogPath
    Optional. Marketplace catalog to read, absolute or relative to the
    repository root. Defaults to .github/plugin/marketplace.json.

.EXAMPLE
    ./Generate-Plugins.ps1
    # Regenerates every tracked package manifest under plugins/

.EXAMPLE
    ./Generate-Plugins.ps1 -PackageNames rpi,github
    # Generates only the rpi and github plugin manifests

.EXAMPLE
    ./Generate-Plugins.ps1 -Check
    # Reports drift between the catalog projection and tracked plugins/

.EXAMPLE
    ./Generate-Plugins.ps1 -Channel Stable
    # Generates manifests with stable-only items

.NOTES
    Dependencies: PowerShell-Yaml module, scripts/plugins/Modules/PluginHelpers.psm1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$PackageNames,

    [Parameter(Mandatory = $false)]
    [switch]$Refresh,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$Check,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Stable', 'PreRelease')]
    [string]$Channel = 'PreRelease',

    [Parameter(Mandatory = $false)]
    [string]$CatalogPath
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Modules/PluginHelpers.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../lib/Modules/CIHelpers.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../lib/Modules/MarketplaceHelpers.psm1') -Force

#region Orchestration

function Remove-StalePluginRoot {
    <#
    .SYNOPSIS
        Removes generated plugin roots the catalog no longer declares.

    .DESCRIPTION
        Per-package orphan cleanup only descends into roots the current run
        regenerates, so a package deleted from the catalog leaves its whole
        tree behind. This deletes every directory under the plugins output that
        the current generation did not produce, making repeated generation from
        a pre-collapse tree converge on the declared package set.

    .PARAMETER PluginsDir
        Absolute path to the generated plugins output directory.

    .PARAMETER GeneratedNames
        Package directory names produced by the current run.

    .PARAMETER DryRun
        When specified, logs removals without deleting.

    .OUTPUTS
        [string[]] Removed directory names.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PluginsDir,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$GeneratedNames,

        [Parameter(Mandatory = $false)]
        [switch]$DryRun
    )

    if (-not (Test-Path -LiteralPath $PluginsDir -PathType Container)) {
        return [string[]]@()
    }

    $keep = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]$GeneratedNames, [System.StringComparer]::OrdinalIgnoreCase
    )

    $removed = [System.Collections.Generic.List[string]]::new()
    foreach ($dir in Get-ChildItem -LiteralPath $PluginsDir -Directory -Force | Sort-Object Name) {
        if ($keep.Contains($dir.Name)) { continue }
        $removed.Add($dir.Name)
        if ($DryRun) {
            Write-Host "  [DRY RUN] Would remove stale plugin root: $($dir.Name)" -ForegroundColor Yellow
        }
        else {
            Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop
            Write-Host "  Removed stale plugin root: $($dir.Name)" -ForegroundColor Yellow
        }
    }

    return [string[]]$removed.ToArray()
}

function Invoke-PluginGeneration {
    <#
    .SYNOPSIS
        Orchestrates plugin manifest generation from the marketplace catalog.

    .DESCRIPTION
        Loads the marketplace catalog, optionally filters to specified package
        names, and writes one plugin.json per eligible package under the output
        root. Component values are manifest-relative references to canonical
        .github artifacts, so no component bytes are produced.

    .PARAMETER RepoRoot
        Absolute path to the repository root directory.

    .PARAMETER PackageNames
        Optional. Array of package names to generate. Generates all when omitted.

    .PARAMETER OutputRoot
        Optional absolute output root. Defaults to the tracked plugins/ directory
        under RepoRoot; drift checking redirects it to a temporary directory.

    .PARAMETER Refresh
        When specified, removes package roots the current catalog no longer declares.

    .PARAMETER DryRun
        When specified, logs actions without creating files or directories.

    .PARAMETER Channel
        Release channel controlling item maturity eligibility.

    .PARAMETER CatalogPath
        Optional marketplace catalog path, absolute or relative to RepoRoot.

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
        [string[]]$PackageNames,

        [Parameter(Mandatory = $false)]
        [string]$OutputRoot,

        [Parameter(Mandatory = $false)]
        [switch]$Refresh,

        [Parameter(Mandatory = $false)]
        [switch]$DryRun,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Stable', 'PreRelease')]
        [string]$Channel = 'PreRelease',

        [Parameter(Mandatory = $false)]
        [string]$CatalogPath
    )

    $pluginsDir = if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        Join-Path -Path $RepoRoot -ChildPath 'plugins'
    }
    else {
        [System.IO.Path]::GetFullPath($OutputRoot)
    }

    $resolvedCatalogPath = if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
        Join-Path -Path $RepoRoot -ChildPath '.github' -AdditionalChildPath 'plugin', 'marketplace.json'
    }
    elseif ([System.IO.Path]::IsPathRooted($CatalogPath)) {
        $CatalogPath
    }
    else {
        Join-Path -Path $RepoRoot -ChildPath $CatalogPath
    }

    $packageJsonPath = Join-Path -Path $RepoRoot -ChildPath 'package.json'
    $effectiveVersion = (Get-Content -Path $packageJsonPath -Raw | ConvertFrom-Json).version

    $catalog = Get-MarketplaceCatalog -Path $resolvedCatalogPath
    $allEntries = @($catalog['plugins'])

    if ($allEntries.Count -eq 0) {
        Write-Warning "No packages declared in $resolvedCatalogPath"
        return New-GenerateResult -Success $true -PluginCount 0
    }

    $agentIndex = Get-MarketplaceAgentIndex -Catalog $catalog -RepoRoot $RepoRoot

    # Filter to requested names when provided
    if ($PackageNames -and $PackageNames.Count -gt 0) {
        $filtered = @($allEntries | Where-Object { $PackageNames -contains $_['name'] })
        $missing = @($PackageNames | Where-Object { $_ -notin ($allEntries | ForEach-Object { $_['name'] }) })
        if ($missing.Count -gt 0) {
            Write-Warning "Packages not found: $($missing -join ', ')"
        }
        $allEntries = $filtered
    }

    Write-Host "`n=== Plugin Generation ===" -ForegroundColor Cyan
    Write-Host "Packages: $($allEntries.Count)"
    Write-Host "Channel: $Channel"
    Write-Host "Version: $effectiveVersion"
    Write-Host "Catalog: $resolvedCatalogPath"
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
    $generatedNames = [System.Collections.Generic.List[string]]::new()

    foreach ($entry in ($allEntries | Sort-Object { $_['name'] })) {
        $id = [string]$entry['name']

        $packageMaturity = Get-MarketplaceEntryMaturity -Entry $entry

        if ($packageMaturity -eq 'deprecated') {
            Write-Verbose "Skipping deprecated package: $id"
            continue
        }

        if ($packageMaturity -eq 'removed') {
            Write-Verbose "Skipping removed package: $id"
            continue
        }

        $items = @(Get-MarketplaceResolvedPackageRecipe -Entry $entry -Channel $Channel -AgentIndex $agentIndex)

        $result = Write-PluginManifest -Entry $entry `
            -Items $items `
            -PluginsDir $pluginsDir `
            -Version $effectiveVersion `
            -DryRun:$DryRun

        $itemCount = $items.Count
        $totalAgents += $result.AgentCount
        $totalCommands += $result.CommandCount
        $totalInstructions += $result.InstructionCount
        $totalSkills += $result.SkillCount
        $totalHooks += $result.HookCount
        $generated++
        $generatedNames.Add($id)

        Write-Host "  $id ($itemCount items)" -ForegroundColor Green
    }

    # A package the catalog no longer declares is never visited above, so only
    # a sweep across the output root retires its manifest.
    $isFullRun = -not ($PackageNames -and $PackageNames.Count -gt 0)
    if ($Refresh -and $isFullRun) {
        $staleRoots = @(Remove-StalePluginRoot -PluginsDir $pluginsDir -GeneratedNames ([string[]]$generatedNames) -DryRun:$DryRun)
        if ($staleRoots.Count -gt 0) {
            Write-Host "  Stale plugin roots removed: $($staleRoots -join ', ')"
        }
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

function Invoke-PluginGenerationCheck {
    <#
    .SYNOPSIS
        Reports drift between the catalog projection and tracked plugins/.

    .DESCRIPTION
        Regenerates the complete manifest set into a temporary directory and
        compares its relative path set and file bytes with the tracked
        plugins/ tree, so the check can never repair the drift it reports. The
        temporary workspace is always removed.

    .PARAMETER RepoRoot
        Absolute path to the repository root directory.

    .PARAMETER Channel
        Release channel controlling item maturity eligibility.

    .PARAMETER CatalogPath
        Optional marketplace catalog path, absolute or relative to RepoRoot.

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
        [ValidateSet('Stable', 'PreRelease')]
        [string]$Channel = 'PreRelease',

        [Parameter(Mandatory = $false)]
        [string]$CatalogPath
    )

    $workspace = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "hve-plugin-check-$([System.Guid]::NewGuid().ToString('n'))"
    $expectedRoot = Join-Path -Path $workspace -ChildPath 'packages'
    try {
        New-Item -ItemType Directory -Path $expectedRoot -Force | Out-Null

        $generation = Invoke-PluginGeneration `
            -RepoRoot $RepoRoot `
            -OutputRoot $expectedRoot `
            -Refresh `
            -Channel $Channel `
            -CatalogPath $CatalogPath
        if (-not $generation.Success) {
            return $generation
        }

        $trackedRoot = Join-Path -Path $RepoRoot -ChildPath 'plugins'
        $comparison = Compare-PluginOutputTree -ExpectedRoot $expectedRoot -ActualRoot $trackedRoot

        Write-Host "`n--- Drift Check ---" -ForegroundColor Cyan
        if (-not $comparison.HasDrift) {
            Write-Host '  plugins/ matches the catalog projection' -ForegroundColor Green
            return New-GenerateResult -Success $true -PluginCount $generation.PluginCount
        }

        foreach ($group in @(
                @{ Label = 'missing from plugins/'; Paths = $comparison.Missing },
                @{ Label = 'not produced by generation'; Paths = $comparison.Extra },
                @{ Label = 'differing content'; Paths = $comparison.Changed }
            )) {
            if ($group.Paths.Count -eq 0) { continue }
            Write-Host "  $($group.Paths.Count) $($group.Label):" -ForegroundColor Red
            foreach ($path in ($group.Paths | Select-Object -First 20)) {
                Write-Host "    $path"
            }
            if ($group.Paths.Count -gt 20) {
                Write-Host "    ... and $($group.Paths.Count - 20) more"
            }
        }

        $message = 'Tracked plugins/ differs from the catalog projection: ' +
        "$($comparison.Missing.Count) missing, $($comparison.Extra.Count) extra, $($comparison.Changed.Count) changed. " +
        'Run npm run plugin:generate and commit the result.'
        return New-GenerateResult -Success $false -PluginCount $generation.PluginCount -ErrorMessage $message
    }
    finally {
        if (Test-Path -LiteralPath $workspace) {
            Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

#endregion Orchestration

#region Main Execution

function Start-PluginGeneration {
    <#
    .SYNOPSIS
        Entry point for CLI invocation. Returns 0 on success, 1 on failure.

    .PARAMETER ScriptPath
        Absolute path to this script file, used to resolve the repo root.

    .PARAMETER PackageNames
        Optional package names forwarded to Invoke-PluginGeneration.

    .PARAMETER Refresh
        Forwarded refresh switch.

    .PARAMETER DryRun
        Forwarded dry-run switch.

    .PARAMETER Check
        Runs the non-mutating drift check instead of generating tracked output.

    .PARAMETER Channel
        Forwarded channel parameter.

    .PARAMETER CatalogPath
        Forwarded marketplace catalog path.

    .OUTPUTS
        [int] Exit code: 0 for success, 1 for failure.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $false)]
        [string[]]$PackageNames,

        [Parameter(Mandatory = $false)]
        [switch]$Refresh,

        [Parameter(Mandatory = $false)]
        [switch]$DryRun,

        [Parameter(Mandatory = $false)]
        [switch]$Check,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Stable', 'PreRelease')]
        [string]$Channel = 'PreRelease',

        [Parameter(Mandatory = $false)]
        [string]$CatalogPath
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

        if ($Check) {
            $result = Invoke-PluginGenerationCheck `
                -RepoRoot $RepoRoot `
                -Channel $Channel `
                -CatalogPath $CatalogPath

            if (-not $result.Success) {
                throw $result.ErrorMessage
            }

            Write-Host ''
            Write-Host 'Done!' -ForegroundColor Green
            Write-Host "   $($result.PluginCount) plugin(s) checked."

            return 0
        }

        # Default to all + refresh when no args
        $effectiveRefresh = $Refresh
        if (-not $PackageNames -and -not $Refresh.IsPresent -and -not $DryRun.IsPresent) {
            $effectiveRefresh = [switch]::new($true)
        }

        $result = Invoke-PluginGeneration `
            -RepoRoot $RepoRoot `
            -PackageNames $PackageNames `
            -Refresh:$effectiveRefresh `
            -DryRun:$DryRun `
            -Channel $Channel `
            -CatalogPath $CatalogPath

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
        Write-Error -ErrorAction Continue "Plugin generation failed: $message"

        if (Get-Command -Name Write-CIAnnotation -ErrorAction SilentlyContinue) {
            Write-CIAnnotation -Message $message -Level Error
        }

        return 1
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    exit (Start-PluginGeneration `
        -ScriptPath $MyInvocation.MyCommand.Path `
        -PackageNames $PackageNames `
        -Refresh:$Refresh `
        -DryRun:$DryRun `
        -Check:$Check `
        -Channel $Channel `
        -CatalogPath $CatalogPath)
}
#endregion
