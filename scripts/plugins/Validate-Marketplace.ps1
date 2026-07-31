#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Validates the marketplace.json manifest for Copilot CLI plugins.

.DESCRIPTION
    Reads .github/plugin/marketplace.json and validates JSON schema compliance,
    version consistency with the root package.json, and the plugin source
    locator of every entry.

    Every source is an immutable GitHub object locator containing a repository,
    package path, and plugins-v<version> tag. Bare package names and commit SHA
    locators are rejected.

.EXAMPLE
    ./Validate-Marketplace.ps1 -OutputPath 'logs/marketplace-validation-results.json'
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = 'logs/marketplace-validation-results.json'
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '../lib/Modules/CIHelpers.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Modules/PluginHelpers.psm1') -Force

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
        Checks the GitHub source type, repository locator, package path, and
        required immutable plugins-v<version> tag. Commit SHA locators are
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

    $ref = $Source['ref']
    if ($ref -isnot [string] -or [string]::IsNullOrWhiteSpace($ref)) {
        $sourceErrors += "object source 'ref' must be a non-empty string"
    }
    elseif ($ref -notmatch '^plugins-v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
        $sourceErrors += "object source 'ref' must use the immutable 'plugins-v<version>' tag form"
    }

    if ($Source.Contains('sha')) {
        $sourceErrors += "object source 'sha' is not supported; use an immutable 'plugins-v<version>' ref"
    }

    return [string[]]$sourceErrors
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

    # Metadata validation
    $metadataRequired = @('description', 'version', 'pluginRoot')
    foreach ($field in $metadataRequired) {
        if (-not $manifest.metadata.ContainsKey($field) -or [string]::IsNullOrWhiteSpace([string]$manifest.metadata[$field])) {
            $errors += "missing required metadata field '$field'"
        }
    }

    # Owner validation
    if (-not $manifest.owner.ContainsKey('name') -or [string]::IsNullOrWhiteSpace([string]$manifest.owner.name)) {
        $errors += "missing required owner field 'name'"
    }

    # Version consistency with package.json
    $packageJsonPath = Join-Path -Path $RepoRoot -ChildPath 'package.json'
    $expectedVersion = $null
    if (Test-Path -Path $packageJsonPath) {
        $packageJson = Get-Content -Path $packageJsonPath -Raw | ConvertFrom-Json
        $expectedVersion = $packageJson.version
        if ($manifest.metadata.version -ne $expectedVersion) {
            $errors += "metadata.version '$($manifest.metadata.version)' does not match package.json version '$expectedVersion'"
        }
    }

    # Plugins validation
    if ($manifest.plugins -isnot [array] -or $manifest.plugins.Count -eq 0) {
        $errors += 'plugins array is empty or missing'
    }
    else {
        $seenNames = @{}

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
            if ($sourceValue -is [System.Collections.IDictionary]) {
                foreach ($sourceError in @(Test-PluginObjectSource -Source $sourceValue)) {
                    $pluginErrors += $sourceError
                }
                $expectedPath = "plugins/$pluginName"
                if ([string]$sourceValue['path'] -cne $expectedPath) {
                    $pluginErrors += "object source path must match package name '$expectedPath'"
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$plugin['version'])) {
                    $expectedRef = "plugins-v$($plugin['version'])"
                    if ([string]$sourceValue['ref'] -cne $expectedRef) {
                        $pluginErrors += "object source ref must match package version '$expectedRef'"
                    }
                }
            }
            elseif ($null -eq $sourceValue -or ($sourceValue -is [string] -and [string]::IsNullOrWhiteSpace($sourceValue))) {
                $pluginErrors += "missing required field 'source'"
            }
            else {
                $pluginErrors += 'source must be an immutable github locator object; bare package names are not supported'
            }

            # Plugin version consistency
            if ($expectedVersion -and $plugin.version -ne $expectedVersion) {
                $pluginErrors += "version '$($plugin.version)' does not match package.json version '$expectedVersion'"
            }

            # Standard component membership and metadata-only x-hve overlay
            foreach ($contractError in @(Test-MarketplaceEntryContract -Entry $plugin)) {
                $pluginErrors += $contractError
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
