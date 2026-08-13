#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Validates the marketplace.json manifest for Copilot CLI plugins.

.DESCRIPTION
    Reads .github/plugin/marketplace.json and validates JSON schema compliance,
    version consistency with the root package.json, the plugin source locator
    of every entry, and the tracked runtime root each entry addresses.

    A source takes one of two forms, and one uniform form serves the whole
    catalog. Development catalogs use the repository-relative package path
    plugins/<name>, which resolves inside the marketplace checkout ref so a
    package installs from the same branch, tag, or clone the marketplace was
    registered from. Release catalogs use a GitHub object locator rooted at the
    same tracked package root, pinning one uniform exact channel tag:
    prerelease-v<version> for PreRelease and v<version> for Stable. Commit SHA
    locators are rejected in both forms.

    Validation never writes tracked package content. Byte and path drift is
    reported by the generator's own non-mutating check, so generation stays the
    sole mutating owner of plugins/.

.EXAMPLE
    ./Validate-Marketplace.ps1 -OutputPath 'logs/marketplace-validation-results.json'
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = 'logs/marketplace-validation-results.json'
)

$ErrorActionPreference = 'Stop'

# ConvertFrom-Yaml is called directly below, so the parser is imported here
# rather than inherited from whichever helper module happens to load it first.
Import-Module -Name PowerShell-Yaml -RequiredVersion '0.4.7' -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '../lib/Modules/CIHelpers.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../lib/Modules/MarketplaceHelpers.psm1') -Force

# The generator owns the only comparison between catalog projection and tracked
# bytes; dot-sourcing reuses its non-mutating check instead of restating it.
. (Join-Path $PSScriptRoot 'Generate-Plugins.ps1')

#region Validation Helpers

function Write-MarketplaceValidationReport {
    <#
    .SYNOPSIS
        Writes marketplace validation results to a JSON report.

    .PARAMETER RepoRoot
        Absolute path to the repository root directory.

    .PARAMETER OutputPath
        Output report path, absolute or relative to RepoRoot.

    .PARAMETER ErrorCount
        Total number of validation errors.

    .PARAMETER Results
        Validation results grouped by plugin or manifest scope.

    .OUTPUTS
        [void]

    .EXAMPLE
        Write-MarketplaceValidationReport -RepoRoot $RepoRoot -OutputPath 'logs/marketplace-validation-results.json' -ErrorCount 0 -Results @()
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath = 'logs/marketplace-validation-results.json',

        [Parameter(Mandatory = $true)]
        [int]$ErrorCount,

        [Parameter(Mandatory = $false)]
        [array]$Results = @()
    )

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        return
    }

    $resolvedOutputPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
        $OutputPath
    }
    else {
        Join-Path -Path $RepoRoot -ChildPath $OutputPath
    }

    $outputDirectory = Split-Path -Path $resolvedOutputPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path -Path $outputDirectory -PathType Container)) {
        New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
    }

    $report = [ordered]@{
        Timestamp  = (Get-Date).ToUniversalTime().ToString('o')
        ErrorCount = $ErrorCount
        Results    = @($Results)
    }

    $report | ConvertTo-Json -Depth 10 | Set-Content -Path $resolvedOutputPath -Encoding UTF8
}

function Test-PluginSourcePath {
    <#
    .SYNOPSIS
        Validates the package path of an object-form plugin source.

    .DESCRIPTION
        Requires a forward-slash relative path that stays inside the source
        repository. Absolute paths, backslashes, relative segments, and empty
        segments are rejected.

    .PARAMETER Path
        Repository-relative package path from an object source.

    .OUTPUTS
        [string] Error message if the path is malformed, empty string if valid.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ($Path -match '\\') {
        return "object source path '$Path' must use forward slashes"
    }

    if ($Path -match '^/' -or $Path -match '^[A-Za-z]:') {
        return "object source path '$Path' must be relative to the repository root"
    }

    foreach ($segment in ($Path -split '/')) {
        if ([string]::IsNullOrEmpty($segment)) {
            return "object source path '$Path' must not contain empty path segments"
        }

        if ($segment -eq '..') {
            return "object source path '$Path' must not escape the source repository"
        }

        if ($segment -eq '.') {
            return "object source path '$Path' must not contain relative path segments"
        }
    }

    return ''
}

function Test-PluginObjectSource {
    <#
    .SYNOPSIS
        Validates an object-form plugin source locator.

    .DESCRIPTION
        Checks the GitHub source type, repository locator, canonical source
        path, and optional immutable channel tag. Commit SHA locators are
        rejected.

    .PARAMETER Source
        Object-form source value from marketplace.json.

    .OUTPUTS
        [string[]] Error messages, empty when the locator is valid.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Source
    )

    $sourceErrors = @()
    $sourceType = [string]$Source['source']

    if ([string]::IsNullOrWhiteSpace($sourceType)) {
        $sourceErrors += "object source is missing required field 'source'"
    }
    elseif ($sourceType -ne 'github') {
        $sourceErrors += "object source type '$sourceType' is not supported (expected: github)"
    }
    else {
        $repo = [string]$Source['repo']
        if ([string]::IsNullOrWhiteSpace($repo)) {
            $sourceErrors += "object source of type 'github' is missing required field 'repo'"
        }
        elseif ($repo -notmatch '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$') {
            $sourceErrors += "object source repo '$repo' must use 'owner/name' form"
        }
    }
    $path = [string]$Source['path']
    if ([string]::IsNullOrWhiteSpace($path)) {
        $sourceErrors += "object source is missing required field 'path'"
    }
    else {
        $pathError = Test-PluginSourcePath -Path $path
        if ($pathError) {
            $sourceErrors += $pathError
        }
    }

    if ($Source.Contains('ref')) {
        $ref = $Source['ref']
        if ($ref -isnot [string] -or [string]::IsNullOrWhiteSpace($ref)) {
            $sourceErrors += "object source 'ref' must be a non-empty string when provided"
        }
        elseif ($ref -cnotmatch '^(?:prerelease-)?v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
            $sourceErrors += "object source 'ref' must use the immutable 'prerelease-v<version>' or 'v<version>' tag form"
        }
    }

    if ($Source.Contains('sha')) {
        $sourceErrors += "object source 'sha' is not supported; omit ref or use an immutable 'prerelease-v<version>' or 'v<version>' ref"
    }

    return [string[]]$sourceErrors
}

function Test-MarketplacePackageRoot {
    <#
    .SYNOPSIS
    Validates the tracked runtime root that one marketplace entry addresses.

    .DESCRIPTION
    Each entry addresses exactly one generator-owned root under plugins/ whose
    sole delivered entry is plugin.json. The manifest must carry the catalog
    name and version, omit the catalog-only x-hve overlay and the catalog-only
    source locator, declare exactly the component references the resolved
    recipe produces, and address a canonical .github source that exists in this
    repository. Expected references are derived from the catalog rather than
    read back from generated output, so a manifest that disagrees with catalog
    membership is reported even when its bytes are self-consistent.

    .PARAMETER Entry
    Marketplace entry.

    .PARAMETER RepoRoot
    Repository root containing the tracked plugins/ roots.

    .PARAMETER AgentIndex
    Catalog agent index used to resolve the package recipe.

    .OUTPUTS
    [string[]] Tracked package root errors.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Entry,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [hashtable]$AgentIndex
    )

    $name = [string]$Entry['name']
    $rootRelative = "plugins/$name"
    $rootPath = Join-Path -Path $RepoRoot -ChildPath 'plugins' -AdditionalChildPath $name
    if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) {
        return [string[]]@("tracked package root '$rootRelative' is missing")
    }

    # The manifest is the only entry a package root delivers, so anything else
    # present is undeclared payload rather than distributable content.
    $rootErrors = @()
    foreach ($entryItem in @(Get-ChildItem -LiteralPath $rootPath -Force | Sort-Object Name)) {
        if ($entryItem.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) {
            $rootErrors += "tracked package root '$rootRelative' contains a link or reparse point: $($entryItem.Name)"
            continue
        }
        if ($entryItem.PSIsContainer -or -not [string]::Equals($entryItem.Name, 'plugin.json', [System.StringComparison]::Ordinal)) {
            $rootErrors += "tracked package root '$rootRelative' delivers '$($entryItem.Name)'; only plugin.json is permitted"
        }
    }

    $manifestRelative = "$rootRelative/plugin.json"
    $manifestPath = Join-Path -Path $rootPath -ChildPath 'plugin.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return [string[]]($rootErrors + "runtime manifest '$manifestRelative' is missing")
    }

    try {
        $runtimeManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
    }
    catch {
        return [string[]]($rootErrors + "runtime manifest '$manifestRelative' is not valid JSON: $($_.Exception.Message)")
    }
    if ($runtimeManifest -isnot [System.Collections.IDictionary]) {
        return [string[]]($rootErrors + "runtime manifest '$manifestRelative' must contain a JSON object")
    }

    if ([string]$runtimeManifest['name'] -cne $name) {
        $rootErrors += "runtime manifest '$manifestRelative' declares name '$($runtimeManifest['name'])' instead of package name '$name'"
    }
    if ([string]$runtimeManifest['version'] -cne [string]$Entry['version']) {
        $rootErrors += "runtime manifest '$manifestRelative' declares version '$($runtimeManifest['version'])' instead of package version '$($Entry['version'])'"
    }
    foreach ($catalogOnly in @('x-hve', 'source')) {
        if ($runtimeManifest.Contains($catalogOnly)) {
            $rootErrors += "runtime manifest '$manifestRelative' must not carry the catalog-only '$catalogOnly' key"
        }
    }

    try {
        $items = @(Get-MarketplaceResolvedPackageRecipe -Entry $Entry -Channel PreRelease -AgentIndex $AgentIndex)
    }
    catch {
        return [string[]]($rootErrors + "package '$name' recipe does not resolve: $($_.Exception.Message)")
    }

    # Components stay in place under .github, so a manifest reference is the
    # catalog reference itself rather than a path inside the package root.
    $expected = @{}
    $sourceByReference = @{}
    foreach ($field in (Get-MarketplaceComponentFieldMap).Keys) {
        $expected[$field] = [System.Collections.Generic.List[string]]::new()
    }
    foreach ($item in $items) {
        $expected[[string]$item.Field].Add([string]$item.PackagePath)
        $sourceByReference[[string]$item.PackagePath] = [string]$item.SourcePath
    }

    foreach ($field in @($expected.Keys | Sort-Object)) {
        $expectedPaths = @($expected[$field] | Sort-Object -Unique)
        $declaredPaths = @(
            if ($runtimeManifest.Contains($field)) {
                @($runtimeManifest[$field]) | ForEach-Object { [string]$_ } | Sort-Object -Unique
            }
        )

        foreach ($omitted in @($expectedPaths | Where-Object { $declaredPaths -notcontains $_ })) {
            $rootErrors += "runtime manifest '$manifestRelative' omits '$field' reference '$omitted' required by catalog membership"
        }
        foreach ($undeclared in @($declaredPaths | Where-Object { $expectedPaths -notcontains $_ })) {
            $rootErrors += "runtime manifest '$manifestRelative' declares '$field' reference '$undeclared', which catalog membership does not produce"
        }

        foreach ($declaredPath in @($declaredPaths | Where-Object { $sourceByReference.ContainsKey($_) })) {
            $sourcePath = Join-Path -Path $RepoRoot -ChildPath $sourceByReference[$declaredPath]
            if (-not (Test-Path -LiteralPath $sourcePath)) {
                $rootErrors += "runtime manifest '$manifestRelative' declares '$field' reference '$declaredPath', whose canonical source '$($sourceByReference[$declaredPath])' does not exist"
            }
        }
    }

    return [string[]]$rootErrors
}

function Test-MarketplaceRepositoryContract {
    <#
    .SYNOPSIS
    Validates the repository-specific marketplace completeness contract.
    .PARAMETER Manifest
    Parsed marketplace catalog.
    .PARAMETER RepoRoot
    Repository root containing canonical artifacts and package docs.
    .PARAMETER AgentIndex
    Catalog agent index used to resolve package recipes.
    .OUTPUTS
    [string[]] Repository contract errors.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Manifest,

        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [hashtable]$AgentIndex
    )

    # A missing canonical root is reported rather than skipped: silently
    # returning no errors would make every rule below vacuously satisfied.
    $contractErrors = @()
    $artifactRoot = Join-Path $RepoRoot '.github/agents'
    $documentationRoot = Join-Path $RepoRoot 'docs/plugins'
    if (-not (Test-Path -LiteralPath $artifactRoot -PathType Container)) {
        $contractErrors += "canonical artifact root '.github/agents' is missing under $RepoRoot"
    }
    if (-not (Test-Path -LiteralPath $documentationRoot -PathType Container)) {
        $contractErrors += "package documentation root 'docs/plugins' is missing under $RepoRoot"
    }

    # Every entry installs from its own tracked root, so the delivered package
    # set is the directory set under plugins/. Missing roots are reported per
    # entry; only roots the catalog never declares are reported here.
    $entries = @($Manifest['plugins'])
    $declaredPackageNames = @($entries | ForEach-Object { [string]$_['name'] })
    $packageRootDirectory = Join-Path $RepoRoot 'plugins'
    if (-not (Test-Path -LiteralPath $packageRootDirectory -PathType Container)) {
        $contractErrors += "tracked package root directory 'plugins' is missing under $RepoRoot"
    }
    else {
        foreach ($trackedRoot in @(Get-ChildItem -LiteralPath $packageRootDirectory -Directory -Force |
                    ForEach-Object { $_.Name } | Sort-Object)) {
            if ($declaredPackageNames -notcontains $trackedRoot) {
                $contractErrors += "tracked package root 'plugins/$trackedRoot' does not match any marketplace package"
            }
        }
        foreach ($strayFile in @(Get-ChildItem -LiteralPath $packageRootDirectory -File -Force |
                    ForEach-Object { $_.Name } | Sort-Object)) {
            $contractErrors += "'plugins/$strayFile' is not a tracked package root"
        }
    }

    # The active package set is derived from the package documents on disk, so
    # adding or retiring a package never requires editing a hard-coded count.
    if (Test-Path -LiteralPath $documentationRoot -PathType Container) {
        $documentedNames = @(Get-ChildItem -LiteralPath $documentationRoot -File -Filter '*.md' |
                ForEach-Object { $_.BaseName } | Sort-Object)
        foreach ($undocumented in @($declaredPackageNames | Where-Object { $documentedNames -notcontains $_ } | Sort-Object)) {
            $contractErrors += "package '$undocumented' has no package document under docs/plugins"
        }
        foreach ($orphan in @($documentedNames | Where-Object { $declaredPackageNames -notcontains $_ })) {
            $contractErrors += "package document 'docs/plugins/$orphan.md' does not match any marketplace package"
        }
    }

    $tombstoneCount = 0
    foreach ($entry in $entries) {
        $name = [string]$entry['name']
        $displayName = Get-MarketplaceEntryOverlayValue -Entry $entry -Key 'displayName'
        if ([string]::IsNullOrWhiteSpace([string]$displayName)) {
            $contractErrors += "package '$name' must declare non-empty x-hve.displayName"
        }

        $documentation = Get-MarketplaceEntryOverlayValue -Entry $entry -Key 'documentation'
        if ([string]::IsNullOrWhiteSpace([string]$documentation)) {
            $contractErrors += "package '$name' must declare x-hve.documentation"
        }
        else {
            $documentPath = Join-Path $RepoRoot ([string]$documentation)
            if (-not (Test-Path -LiteralPath $documentPath -PathType Leaf)) {
                $contractErrors += "package '$name' documentation is missing: $documentation"
            }
            else {
                $content = Get-Content -LiteralPath $documentPath -Raw -Encoding utf8
                if ($content -match '(?s)^---\s*\r?\n(.*?)\r?\n---') {
                    $frontmatter = ConvertFrom-Yaml -Yaml $Matches[1]
                    if ([string]$frontmatter.description -ne [string]$entry['description']) {
                        $contractErrors += "package '$name' description does not match $documentation"
                    }
                }
                else {
                    $contractErrors += "package '$name' documentation has no frontmatter: $documentation"
                }
            }
        }

        $componentMaturity = Get-MarketplaceEntryOverlayValue -Entry $entry -Key 'componentMaturity'
        if ($componentMaturity -is [System.Collections.IDictionary]) {
            $tombstoneCount += @($componentMaturity.Values | Where-Object { $_ -eq 'removed' }).Count
        }

        foreach ($item in Get-MarketplaceResolvedPackageRecipe -Entry $entry -Channel PreRelease -AgentIndex $AgentIndex) {
            $sourcePath = Join-Path $RepoRoot $item.SourcePath
            if (-not (Test-Path -LiteralPath $sourcePath)) {
                $contractErrors += "package '$name' source is missing: $($item.SourcePath)"
            }
        }

        # Both release lanes ship the same components with the same labels, so a
        # channel-dependent projection is a policy regression rather than a variant.
        $channelProjections = @{}
        foreach ($channel in @('Stable', 'PreRelease')) {
            $channelProjections[$channel] = @(Get-MarketplaceResolvedPackageRecipe -Entry $entry -Channel $channel -AgentIndex $AgentIndex |
                    ForEach-Object { "$($_.PackagePath)=$($_.Maturity)" }) -join '|'
        }
        if ($channelProjections['Stable'] -ne $channelProjections['PreRelease']) {
            $contractErrors += "package '$name' must resolve identical components and maturity on Stable and PreRelease"
        }
    }
    if ($tombstoneCount -eq 0) {
        $contractErrors += 'repository marketplace must declare at least one removed component tombstone'
    }

    $sourcePolicyIndex = Get-MarketplaceSourcePolicyIndex -Catalog $Manifest
    foreach ($sourcePath in @($sourcePolicyIndex.Keys | Sort-Object)) {
        $records = @($sourcePolicyIndex[$sourcePath])
        $maturityValues = @($records | ForEach-Object { [string]$_.Maturity } | Sort-Object -Unique)
        if ($maturityValues.Count -gt 1) {
            $declarations = @($records | Sort-Object PackageName |
                    ForEach-Object { "$($_.PackageName)=$($_.Maturity)" }) -join ', '
            $contractErrors += "source '$sourcePath' must declare identical maturity across packages: $declarations"
        }
    }

    return [string[]]$contractErrors
}

#endregion Validation Helpers

#region Orchestration

function Invoke-MarketplaceValidation {
    <#
    .SYNOPSIS
        Validates the marketplace.json manifest.

    .DESCRIPTION
        Validates the marketplace manifest against its JSON schema and performs
        cross-validation checks including source directory existence,
        name-source consistency, version consistency, and source format.

    .PARAMETER RepoRoot
        Absolute path to the repository root directory.

    .OUTPUTS
        Hashtable with Success bool and ErrorCount int.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath = 'logs/marketplace-validation-results.json'
    )

    $manifestPath = Join-Path -Path $RepoRoot -ChildPath '.github' -AdditionalChildPath 'plugin', 'marketplace.json'

    if (-not (Test-Path -Path $manifestPath)) {
        Write-Host '  FAIL marketplace.json not found' -ForegroundColor Red
        $results = @(
            @{
                PluginName = 'marketplace'
                IsValid    = $false
                Errors     = @('marketplace.json not found')
                Warnings   = @()
            }
        )
        Write-MarketplaceValidationReport -RepoRoot $RepoRoot -OutputPath $OutputPath -ErrorCount 1 -Results $results
        return @{ Success = $false; ErrorCount = 1 }
    }

    Write-Host 'Validating marketplace.json...'

    $errors = @()
    $results = @()

    # Parse JSON
    try {
        $manifestContent = Get-Content -Path $manifestPath -Raw
        $manifest = $manifestContent | ConvertFrom-Json -AsHashtable
    }
    catch {
        $errors += "invalid JSON: $($_.Exception.Message)"
        foreach ($err in $errors) {
            Write-Host "    x $err" -ForegroundColor Red
        }
        $results += @{
            PluginName = 'marketplace'
            IsValid    = $false
            Errors     = @($errors)
            Warnings   = @()
        }
        Write-MarketplaceValidationReport -RepoRoot $RepoRoot -OutputPath $OutputPath -ErrorCount 1 -Results $results
        return @{ Success = $false; ErrorCount = 1 }
    }

    # Required top-level fields
    $requiredFields = @('name', 'metadata', 'owner', 'plugins')
    foreach ($field in $requiredFields) {
        if (-not $manifest.ContainsKey($field) -or $null -eq $manifest[$field]) {
            $errors += "missing required field '$field'"
        }
    }

    if ($errors.Count -gt 0) {
        foreach ($err in $errors) {
            Write-Host "    x $err" -ForegroundColor Red
        }
        $results += @{
            PluginName = 'marketplace'
            IsValid    = $false
            Errors     = @($errors)
            Warnings   = @()
        }
        Write-MarketplaceValidationReport -RepoRoot $RepoRoot -OutputPath $OutputPath -ErrorCount $errors.Count -Results $results
        return @{ Success = $false; ErrorCount = $errors.Count }
    }

    # Catalog-scope findings are collected separately so the report names them
    # under a marketplace scope instead of only raising the error count.
    $catalogErrors = @()

    # Metadata validation
    $metadataRequired = @('description', 'version')
    foreach ($field in $metadataRequired) {
        if (-not $manifest.metadata.ContainsKey($field) -or [string]::IsNullOrWhiteSpace([string]$manifest.metadata[$field])) {
            $catalogErrors += "missing required metadata field '$field'"
        }
    }

    # Owner validation
    if (-not $manifest.owner.ContainsKey('name') -or [string]::IsNullOrWhiteSpace([string]$manifest.owner.name)) {
        $catalogErrors += "missing required owner field 'name'"
    }

    # Version consistency with package.json
    $packageJsonPath = Join-Path -Path $RepoRoot -ChildPath 'package.json'
    $expectedVersion = $null
    if (Test-Path -Path $packageJsonPath) {
        $packageJson = Get-Content -Path $packageJsonPath -Raw | ConvertFrom-Json
        $expectedVersion = $packageJson.version
        if ($manifest.metadata.version -ne $expectedVersion) {
            $catalogErrors += "metadata.version '$($manifest.metadata.version)' does not match package.json version '$expectedVersion'"
        }
    }

    # One index serves entry-level root checks and the repository contract, so
    # handoff closure is resolved from the same catalog projection in both.
    $agentIndex = Get-MarketplaceAgentIndex -Catalog $manifest -RepoRoot $RepoRoot

    # Plugins validation
    if ($manifest.plugins -isnot [array] -or $manifest.plugins.Count -eq 0) {
        $catalogErrors += 'plugins array is empty or missing'
    }
    else {
        $seenNames = @{}
        $sourceForms = @()
        $sourceRefPresence = @()
        $sourceRefChannels = @()

        foreach ($plugin in $manifest.plugins) {
            $pluginName = $plugin.name
            $pluginErrors = @()
            $pluginWarnings = @()

            # Required plugin fields
            $pluginRequired = @('name', 'description', 'version')
            foreach ($field in $pluginRequired) {
                if (-not $plugin.ContainsKey($field) -or [string]::IsNullOrWhiteSpace([string]$plugin[$field])) {
                    $pluginErrors += "missing required field '$field'"
                }
            }

            # Duplicate name check
            if ($seenNames.ContainsKey($pluginName)) {
                $pluginErrors += "duplicate plugin name '$pluginName'"
            }
            else {
                $seenNames[$pluginName] = $true
            }

            # Source validation, dispatched on the source form
            $sourceValue = $plugin['source']
            $expectedSourcePath = "plugins/$pluginName"
            if ($sourceValue -is [System.Collections.IDictionary]) {
                $sourceForms += 'object'
                $sourceRefPresence += $sourceValue.Contains('ref')
                foreach ($sourceError in @(Test-PluginObjectSource -Source $sourceValue)) {
                    $pluginErrors += $sourceError
                }
                if ([string]$sourceValue['path'] -cne $expectedSourcePath) {
                    $pluginErrors += "object source path must be '$expectedSourcePath'"
                }
                if ($sourceValue.Contains('ref') -and -not [string]::IsNullOrWhiteSpace([string]$plugin['version'])) {
                    $channelRefs = [ordered]@{
                        PreRelease = "prerelease-v$($plugin['version'])"
                        Stable     = "v$($plugin['version'])"
                    }
                    $refChannel = @($channelRefs.Keys | Where-Object { $channelRefs[$_] -ceq [string]$sourceValue['ref'] })
                    if ($refChannel.Count -eq 0) {
                        $pluginErrors += "object source ref must match package version '$($channelRefs['PreRelease'])' or '$($channelRefs['Stable'])'"
                    }
                    else {
                        $sourceRefChannels += $refChannel[0]
                    }
                }
            }
            elseif ($sourceValue -is [string] -and -not [string]::IsNullOrWhiteSpace($sourceValue)) {
                # A relative source names no ref because it resolves inside the
                # marketplace checkout ref, so the package comes from the same
                # branch, tag, or clone the catalog was read from.
                $sourceForms += 'relative'
                if ($sourceValue -cne $expectedSourcePath) {
                    $pluginErrors += "relative source must be '$expectedSourcePath'"
                }
            }
            elseif ($null -eq $sourceValue -or $sourceValue -is [string]) {
                $pluginErrors += "missing required field 'source'"
            }
            else {
                $pluginErrors += "source must be the relative package path '$expectedSourcePath' or an immutable github locator object"
            }

            # Plugin version consistency
            if ($expectedVersion -and $plugin.version -ne $expectedVersion) {
                $pluginErrors += "version '$($plugin.version)' does not match package.json version '$expectedVersion'"
            }

            # Standard component membership and metadata-only x-hve overlay
            foreach ($contractError in @(Test-MarketplaceEntryContract -Entry $plugin)) {
                $pluginErrors += $contractError
            }

            # Delivered runtime root addressed by this entry
            foreach ($rootError in @(Test-MarketplacePackageRoot -Entry $plugin -RepoRoot $RepoRoot -AgentIndex $agentIndex)) {
                $pluginErrors += $rootError
            }

            $results += @{
                PluginName = $pluginName
                IsValid    = ($pluginErrors.Count -eq 0)
                Errors     = @($pluginErrors)
                Warnings   = @($pluginWarnings)
            }

            foreach ($pluginError in $pluginErrors) {
                $errors += "plugin '$pluginName': $pluginError"
            }
        }

        if (@($sourceForms | Sort-Object -Unique).Count -gt 1) {
            $catalogErrors += 'source must use one uniform form across every entry: the relative package path or the immutable github locator object'
        }

        if (@($sourceRefPresence | Sort-Object -Unique).Count -gt 1) {
            $catalogErrors += 'object source ref must be either omitted from every entry or present on every entry'
        }

        if (@($sourceRefChannels | Sort-Object -Unique).Count -gt 1) {
            $catalogErrors += 'object source ref must use one uniform release channel namespace across every entry'
        }
    }

    if ($catalogErrors.Count -gt 0) {
        $results += @{
            PluginName = 'marketplace'
            IsValid    = $false
            Errors     = @($catalogErrors)
            Warnings   = @()
        }
        $errors += $catalogErrors
    }

    # Repository-contract findings get their own report scope; without it the
    # report would raise ErrorCount without naming a single failing rule.
    $repositoryErrors = @(
        Test-MarketplaceRepositoryContract -Manifest $manifest -RepoRoot $RepoRoot -AgentIndex $agentIndex |
            ForEach-Object { "repository contract: $_" }
    )
    if ($repositoryErrors.Count -gt 0) {
        $results += @{
            PluginName = 'repository'
            IsValid    = $false
            Errors     = @($repositoryErrors)
            Warnings   = @()
        }
        $errors += $repositoryErrors
    }

    # Byte and path drift belongs to the generator, which regenerates into a
    # temporary tree and compares. Validation only reports its verdict so the
    # tracked roots are never rewritten by a validation run.
    $driftErrors = @()
    try {
        $driftResult = Invoke-PluginGenerationCheck -RepoRoot $RepoRoot
        if (-not $driftResult.Success) {
            $driftErrors += [string]$driftResult.ErrorMessage
        }
    }
    catch {
        $driftErrors += "generated package drift check failed: $($_.Exception.Message)"
    }
    if ($driftErrors.Count -gt 0) {
        $results += @{
            PluginName = 'plugins'
            IsValid    = $false
            Errors     = @($driftErrors)
            Warnings   = @()
        }
        $errors += $driftErrors
    }

    if ($errors.Count -gt 0 -and $results.Count -eq 0) {
        $results += @{
            PluginName = 'marketplace'
            IsValid    = $false
            Errors     = @($errors)
            Warnings   = @()
        }
    }

    if ($errors.Count -gt 0) {
        Write-Host "  FAIL marketplace.json - $($errors.Count) error(s)" -ForegroundColor Red
        foreach ($err in $errors) {
            Write-Host "      $err" -ForegroundColor Red
        }
    }
    else {
        Write-Host "  OK marketplace.json ($($manifest.plugins.Count) plugins)"
    }

    Write-MarketplaceValidationReport -RepoRoot $RepoRoot -OutputPath $OutputPath -ErrorCount $errors.Count -Results $results

    return @{
        Success    = ($errors.Count -eq 0)
        ErrorCount = $errors.Count
    }
}

#endregion Orchestration

#region Main Execution
if ($MyInvocation.InvocationName -ne '.') {
    try {
        $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
        $RepoRoot = (Get-Item "$ScriptDir/../..").FullName

        $result = Invoke-MarketplaceValidation -RepoRoot $RepoRoot -OutputPath $OutputPath

        if (-not $result.Success) {
            throw "Marketplace validation failed with $($result.ErrorCount) error(s)."
        }

        exit 0
    }
    catch {
        Write-Error "Marketplace validation failed: $($_.Exception.Message)"
        Write-CIAnnotation -Message $_.Exception.Message -Level Error
        exit 1
    }
}
#endregion
