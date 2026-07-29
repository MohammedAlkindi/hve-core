#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

#Requires -Version 7.4

<#
.SYNOPSIS
    Refreshes the model catalog by fetching current models from GitHub docs data.

.DESCRIPTION
    Fetches structured YAML data files from the github/docs repository that define
    Copilot model names, release status, and per-token pricing. Merges these into
    the local model-catalog.json. Reports additions, removals, and tier changes.

.PARAMETER CatalogPath
    Path to the model catalog JSON file to update.

.PARAMETER DryRun
    When specified, reports changes without modifying the catalog file.

.PARAMETER BaseUrl
    Base URL for raw YAML data files in the github/docs repository.

.EXAMPLE
    ./Update-ModelCatalog.ps1

.EXAMPLE
    ./Update-ModelCatalog.ps1 -DryRun

.NOTES
    Data files are structured YAML from github/docs and are more stable than
    rendered page scraping. If the file paths change, update BaseUrl or the
    file names in the script.

    Upstream is fetched from github/docs@main without a pinned SHA or tag.
    This means results are non-deterministic across runs — upstream additions
    or removals can appear between invocations. The CI workflow detects drift
    between the refreshed catalog and the committed version, so staleness is
    surfaced rather than silently accepted.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$CatalogPath = 'scripts/linting/model-catalog.json',

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [string]$BaseUrl = 'https://raw.githubusercontent.com/github/docs/main/data/tables/copilot'
)

$ErrorActionPreference = 'Stop'

Import-Module powershell-yaml -ErrorAction Stop

#region Functions

function Get-RemoteYaml {
    <#
    .SYNOPSIS
    Fetches and parses a remote YAML file.

    .PARAMETER Url
    URL to fetch.

    .OUTPUTS
    Parsed YAML content.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
    return ConvertFrom-Yaml -Yaml $response.Content -AllDocuments
}

function Get-ModelProvider {
    <#
    .SYNOPSIS
    Derives the provider name from a model display name using prefix matching.

    .DESCRIPTION
    Maps model names to their provider using known prefix patterns. Models not
    matching any known prefix are classified as 'Unknown'. To support additional
    providers in the future, add a new entry to the $providerPatterns array below.

    .PARAMETER ModelName
    The model display name (without the "(copilot)" suffix).

    .OUTPUTS
    [string] Provider name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModelName
    )

    # Provider prefix patterns — add new providers here as they become available.
    # Order matters: first match wins.
    $providerPatterns = @(
        @{ Pattern = '^Claude';    Provider = 'Anthropic' }
        @{ Pattern = '^GPT-|^o\d'; Provider = 'OpenAI' }
        @{ Pattern = '^Gemini';    Provider = 'Google' }
        @{ Pattern = '^Grok';      Provider = 'xAI' }
        @{ Pattern = '^Kimi';      Provider = 'Moonshot AI' }
    )

    foreach ($entry in $providerPatterns) {
        if ($ModelName -match $entry.Pattern) {
            return $entry.Provider
        }
    }

    return 'Unknown'
}

function ConvertTo-ProviderName {
    <#
    .SYNOPSIS
    Maps an upstream provider slug to its catalog display name.

    .PARAMETER Slug
    Provider slug from the pricing table, such as 'moonshot_ai'.

    .OUTPUTS
    [string] Display name, or $null when the slug is empty or unrecognized.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Slug
    )

    switch ($Slug) {
        'anthropic' { return 'Anthropic' }
        'openai' { return 'OpenAI' }
        'google' { return 'Google' }
        'microsoft' { return 'Microsoft' }
        'github' { return 'GitHub' }
        'xai' { return 'xAI' }
        'moonshot_ai' { return 'Moonshot AI' }
        default { return $null }
    }
}

function Get-InputPrice {
    <#
    .SYNOPSIS
    Parses an upstream display price such as '$1.50' into a number.

    .PARAMETER Price
    Raw price string from the pricing table.

    .OUTPUTS
    [nullable[double]] Parsed price, or $null when the cell is empty or unparsable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Price
    )

    if ([string]::IsNullOrWhiteSpace($Price)) { return $null }
    $digits = $Price -replace '[^\d.]', ''
    if ([string]::IsNullOrWhiteSpace($digits)) { return $null }

    $parsed = 0.0
    if ([double]::TryParse($digits, [ref]$parsed)) { return $parsed }
    return $null
}

function Get-CostTier {
    <#
    .SYNOPSIS
    Classifies a model into a cost tier from its per-million-token input price.

    .PARAMETER InputPrice
    Base input price in USD per million tokens.

    .OUTPUTS
    [string] One of free, fast, standard, premium, ultra.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [double]$InputPrice
    )

    if ($InputPrice -eq 0) { return 'free' }
    if ($InputPrice -le 1.0) { return 'fast' }
    if ($InputPrice -le 3.0) { return 'standard' }
    if ($InputPrice -le 5.0) { return 'premium' }
    return 'ultra'
}

function Merge-ModelData {
    <#
    .SYNOPSIS
    Merges model release status and pricing data into catalog entries.

    .PARAMETER ReleaseStatus
    Array of model release status objects from model-release-status.yml.

    .PARAMETER Pricing
    Array of model pricing objects from models-and-pricing.yml.

    .OUTPUTS
    [hashtable[]] Array of merged model catalog entries.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$ReleaseStatus,

        [Parameter(Mandatory = $true)]
        [object[]]$Pricing
    )

    $priceLookup = @{}
    $providerLookup = @{}
    foreach ($p in $Pricing) {
        # Names may carry a footnote marker such as 'Claude Sonnet 5[^sonnet-5-promo]'.
        $priceName = ($p.model -replace '\[\^.*?\]', '').Trim()

        $upstreamProvider = ConvertTo-ProviderName -Slug $p.provider
        if ($upstreamProvider -and -not $providerLookup.ContainsKey($priceName)) {
            $providerLookup[$priceName] = $upstreamProvider
        }

        $priceValue = Get-InputPrice -Price $p.input
        if ($null -eq $priceValue) { continue }

        # A model has one row per context-window band; the base band is the cheapest.
        if (-not $priceLookup.ContainsKey($priceName) -or $priceValue -lt $priceLookup[$priceName]) {
            $priceLookup[$priceName] = $priceValue
        }
    }

    $models = @()
    foreach ($model in $ReleaseStatus) {
        $name = $model.name
        $status = if ($model.release_status -eq 'GA') { 'ga' } else { 'preview' }

        if ($priceLookup.ContainsKey($name)) {
            $tier = Get-CostTier -InputPrice $priceLookup[$name]
        }
        else {
            Write-Warning "No upstream price for '$name'. Defaulting tier to 'standard'."
            $tier = 'standard'
        }

        # Ordered so repeat runs emit a stable field order and a clean diff.
        $models += [ordered]@{
            name     = "$name (copilot)"
            tier     = $tier
            status   = $status
            provider = if ($providerLookup.ContainsKey($name)) { $providerLookup[$name] } else { Get-ModelProvider -ModelName $name }
        }
    }

    return $models
}

function Compare-Catalogs {
    <#
    .SYNOPSIS
    Compares current catalog models against newly discovered models.

    .PARAMETER Current
    Array of current catalog model objects.

    .PARAMETER Discovered
    Array of newly discovered model objects.

    .OUTPUTS
    [hashtable] With added, removed, and changed arrays.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Current,

        [Parameter(Mandatory = $true)]
        [object[]]$Discovered
    )

    $currentNames = @($Current | ForEach-Object { $_.name })
    $discoveredNames = @($Discovered | ForEach-Object { $_.name })

    $added = @($Discovered | Where-Object { $_.name -notin $currentNames })
    $removed = @($Current | Where-Object { $_.name -notin $discoveredNames })

    $changed = @()
    foreach ($disc in $Discovered) {
        $curr = $Current | Where-Object { $_.name -eq $disc.name }
        if ($curr -and $curr.tier -ne $disc.tier) {
            $changed += @{
                name    = $disc.name
                oldTier = $curr.tier
                newTier = $disc.tier
            }
        }
    }

    return @{
        added   = $added
        removed = $removed
        changed = $changed
    }
}

#endregion Functions

#region Orchestration

function Invoke-ModelCatalogUpdate {
    <#
    .SYNOPSIS
    Orchestrates catalog update from fetched model data.

    .PARAMETER ReleaseStatus
    Array of model release status objects.

    .PARAMETER Pricing
    Array of model pricing objects.

    .PARAMETER CatalogPath
    Path to the catalog JSON file.

    .PARAMETER DryRun
    When true, reports changes without writing to disk.

    .OUTPUTS
    [hashtable] With status ('unchanged', 'updated', 'created', 'dryrun'), diff, and finalModels.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$ReleaseStatus,

        [Parameter(Mandatory = $true)]
        [object[]]$Pricing,

        [Parameter(Mandatory = $true)]
        [string]$CatalogPath,

        [Parameter(Mandatory = $false)]
        [switch]$DryRun
    )

    $discoveredModels = Merge-ModelData -ReleaseStatus $ReleaseStatus -Pricing $Pricing
    Write-Host "  Discovered $($discoveredModels.Count) models from docs" -ForegroundColor Green

    $diff = $null
    $finalModels = $null

    # Load current catalog if it exists
    if (Test-Path -Path $CatalogPath) {
        $currentCatalog = Get-Content -Path $CatalogPath -Raw | ConvertFrom-Json
        $currentModels = @($currentCatalog.models)

        $diff = Compare-Catalogs -Current $currentModels -Discovered $discoveredModels

        if ($diff.added.Count -gt 0) {
            Write-Host "`n  Added models:" -ForegroundColor Green
            foreach ($m in $diff.added) { Write-Host "    + $($m['name']) (tier: $($m['tier']))" -ForegroundColor Green }
        }
        if ($diff.removed.Count -gt 0) {
            Write-Host "`n  Removed models (marking as retiring):" -ForegroundColor Yellow
            foreach ($m in $diff.removed) { Write-Host "    - $($m.name)" -ForegroundColor Yellow }
        }
        if ($diff.changed.Count -gt 0) {
            Write-Host "`n  Tier changes:" -ForegroundColor Cyan
            foreach ($c in $diff.changed) { Write-Host "    ~ $($c.name): $($c.oldTier) -> $($c.newTier)" -ForegroundColor Cyan }
        }

        if ($diff.added.Count -eq 0 -and $diff.removed.Count -eq 0 -and $diff.changed.Count -eq 0) {
            Write-Host "`n  No changes detected. Catalog is current." -ForegroundColor Green
            if (-not $DryRun) {
                $currentCatalog.lastUpdated = (Get-Date -Format 'yyyy-MM-dd')
                $currentCatalog | ConvertTo-Json -Depth 5 | Set-Content -Path $CatalogPath -Encoding utf8
            }
            return @{ status = 'unchanged'; diff = $diff; finalModels = $currentModels }
        }

        # Mark removed models as retiring instead of deleting
        $finalModels = @()
        $removedNames = @($diff.removed | ForEach-Object { $_.name })
        foreach ($curr in $currentModels) {
            if ($curr.name -in $removedNames) {
                # Keep the original retirement date so repeat runs do not extend it.
                $retiredDate = if ($curr.PSObject.Properties['retiredDate'] -and $curr.retiredDate) {
                    $curr.retiredDate
                }
                else {
                    (Get-Date).AddDays(60).ToString('yyyy-MM-dd')
                }

                $finalModels += [PSCustomObject]@{
                    name        = $curr.name
                    tier        = $curr.tier
                    status      = 'retiring'
                    provider    = $curr.provider
                    retiredDate = $retiredDate
                }
            }
            else {
                # Rebuild from discovered data so removed fields do not survive a refresh.
                $finalModels += @($discoveredModels | Where-Object { $_.name -eq $curr.name })
            }
        }
        # Add new models
        $finalModels += $diff.added
    }
    else {
        Write-Host "  No existing catalog found. Creating new catalog." -ForegroundColor Yellow
        $finalModels = $discoveredModels
    }

    if ($DryRun) {
        Write-Host "`n  [DRY RUN] No changes written to disk." -ForegroundColor Yellow
        return @{ status = 'dryrun'; diff = $diff; finalModels = $finalModels }
    }

    # Write updated catalog
    # providerAllowlist controls which providers are permitted in agent/prompt model
    # references. To allow additional providers, add them to this array.
    $allowlist = @('Anthropic', 'OpenAI')
    if (Test-Path -Path $CatalogPath) {
        $existingCatalog = Get-Content -Path $CatalogPath -Raw | ConvertFrom-Json
        if ($existingCatalog.providerAllowlist) {
            $allowlist = @($existingCatalog.providerAllowlist)
        }
    }

    $newCatalog = [ordered]@{
        '$schema'         = './schemas/model-catalog.schema.json'
        lastUpdated       = (Get-Date -Format 'yyyy-MM-dd')
        source            = 'https://docs.github.com/en/copilot/reference/ai-models/supported-models'
        providerAllowlist = $allowlist
        models            = $finalModels
    }

    $outputDir = Split-Path -Path $CatalogPath -Parent
    if ($outputDir -and -not (Test-Path -Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $newCatalog | ConvertTo-Json -Depth 5 | Set-Content -Path $CatalogPath -Encoding utf8
    Write-Host "`n  Catalog updated: $CatalogPath" -ForegroundColor Green
    Write-Host "  Total models: $($finalModels.Count)" -ForegroundColor Green

    $resultStatus = if ($null -eq $diff) { 'created' } else { 'updated' }
    return @{ status = $resultStatus; diff = $diff; finalModels = $finalModels }
}

#endregion Orchestration

#region Main

# Only run main logic when executed directly
if ($MyInvocation.InvocationName -ne '.') {
    Write-Host "Fetching model data from github/docs YAML sources..." -ForegroundColor Cyan

    try {
        $releaseStatusUrl = "$BaseUrl/model-release-status.yml"
        $pricingUrl = "$BaseUrl/models-and-pricing.yml"

        Write-Host "  Fetching: $releaseStatusUrl"
        $releaseStatus = Get-RemoteYaml -Url $releaseStatusUrl

        Write-Host "  Fetching: $pricingUrl"
        $pricing = Get-RemoteYaml -Url $pricingUrl
    }
    catch {
        Write-Warning "Failed to fetch source data: $_"
        Write-Warning "Model catalog not updated. Check network or source URLs."
        exit 1
    }

    if (-not $releaseStatus -or $releaseStatus.Count -eq 0) {
        Write-Warning "No models found in release status data. Source format may have changed."
        exit 1
    }

    $updateParams = @{
        ReleaseStatus = $releaseStatus
        Pricing       = $pricing
        CatalogPath   = $CatalogPath
    }
    if ($DryRun) { $updateParams['DryRun'] = $true }

    $result = Invoke-ModelCatalogUpdate @updateParams
    if ($result.status -eq 'unchanged' -or $result.status -eq 'dryrun') {
        exit 0
    }
    exit 0
}

#endregion Main
