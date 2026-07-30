#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Validates the marketplace.json manifest for Copilot CLI plugins.

.DESCRIPTION
    Reads .github/plugin/marketplace.json and validates JSON schema compliance,
    plugin source directory existence, name-source consistency, version
    consistency with the root package.json, and absence of path separators
    in source values.

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

function Test-PluginSourceDirectory {
    <#
    .SYNOPSIS
        Validates that a plugin source directory exists under the plugins root.

    .PARAMETER Source
        Plugin source value from marketplace.json.

    .PARAMETER PluginsRoot
        Absolute path to the plugins directory.

    .OUTPUTS
        [string] Error message if directory not found, empty string if valid.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$PluginsRoot
    )

    $pluginDir = Join-Path -Path $PluginsRoot -ChildPath $Source
    $pluginItem = Get-Item -LiteralPath $pluginDir -Force -ErrorAction SilentlyContinue
    if ($null -eq $pluginItem -or -not $pluginItem.PSIsContainer) {
        return "plugin source directory not found: plugins/$Source"
    }

    if ($pluginItem.LinkType -or ($pluginItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        return "plugin source directory must be a regular directory: plugins/$Source"
    }

    return ''
}

function Test-PluginSourceFormat {
    <#
    .SYNOPSIS
        Validates that a plugin source contains no path separators.

    .PARAMETER Source
        Plugin source value from marketplace.json.

    .OUTPUTS
        [string] Error message if source contains path separators, empty string if valid.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    if ($Source -match '[/\\]') {
        return "plugin source '$Source' must not contain path separators"
    }

    if ($Source -in @('.', '..')) {
        return "plugin source '$Source' must not be a relative path segment"
    }

    return ''
}

function Test-PathContainedByRoot {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $comparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }

    return $fullPath.Equals($fullRoot, $comparison) -or
        $fullPath.StartsWith("$fullRoot$([System.IO.Path]::DirectorySeparatorChar)", $comparison)
}

function Get-RegularObjectError {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet('File', 'Directory')]
        [string]$ExpectedType,

        [Parameter(Mandatory = $true)]
        [string]$DisplayPath
    )

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return "required $($ExpectedType.ToLowerInvariant()) not found: $DisplayPath"
    }
    if ($item.LinkType -or ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        return "linked or reparse-point object is not allowed: $DisplayPath"
    }
    if ($ExpectedType -eq 'Directory' -and -not $item.PSIsContainer) {
        return "expected directory but found file: $DisplayPath"
    }
    if ($ExpectedType -eq 'File' -and $item.PSIsContainer) {
        return "expected file but found directory: $DisplayPath"
    }

    return ''
}

function Test-PluginPackageContent {
    <#
    .SYNOPSIS
        Validates a generated plugin and its repository source references.

    .PARAMETER PluginRoot
        Absolute path to the generated plugin root.

    .PARAMETER PluginName
        Marketplace plugin name for error messages.

    .PARAMETER ExpectedVersion
        Expected plugin manifest version.

    .PARAMETER RepoRoot
        Absolute repository root that must contain every component target.

    .OUTPUTS
        [string[]] Validation errors for invalid manifests or source references.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PluginRoot,

        [Parameter(Mandatory = $true)]
        [string]$PluginName,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$ExpectedVersion,

        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $pluginErrors = @()
    $canonicalPluginRoot = [System.IO.Path]::TrimEndingDirectorySeparator(
        [System.IO.Path]::GetFullPath($PluginRoot)
    )
    $canonicalRepoRoot = [System.IO.Path]::TrimEndingDirectorySeparator(
        [System.IO.Path]::GetFullPath($RepoRoot)
    )
    $manifestPath = Join-Path $canonicalPluginRoot '.github/plugin/plugin.json'
    $readmePath = Join-Path $canonicalPluginRoot 'README.md'
    $manifestError = Get-RegularObjectError -Path $manifestPath -ExpectedType File -DisplayPath '.github/plugin/plugin.json'
    if ($manifestError) {
        return @($manifestError)
    }
    $readmeError = Get-RegularObjectError -Path $readmePath -ExpectedType File -DisplayPath 'README.md'
    if ($readmeError) {
        $pluginErrors += $readmeError
    }

    $generatedFiles = @(Get-ChildItem -LiteralPath $canonicalPluginRoot -File -Recurse -Force)
    $expectedFiles = @(
        [System.IO.Path]::GetFullPath($manifestPath)
        [System.IO.Path]::GetFullPath($readmePath)
    )
    $unexpectedFiles = @($generatedFiles | Where-Object {
        [System.IO.Path]::GetFullPath($_.FullName) -notin $expectedFiles
    })
    if ($unexpectedFiles.Count -gt 0) {
        $pluginErrors += "plugin '$PluginName' must contain only README.md and .github/plugin/plugin.json"
    }

    foreach ($item in Get-ChildItem -LiteralPath $canonicalPluginRoot -Force -Recurse) {
        if ($item.LinkType -or ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            $pluginErrors += "plugin '$PluginName' contains a link or reparse point: $($item.FullName)"
        }
    }

    try {
        $manifest = [System.IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json -AsHashtable
    }
    catch {
        return @($pluginErrors + "plugin '$PluginName' has invalid plugin.json content")
    }

    if ($manifest.name -ne $PluginName) {
        $pluginErrors += "plugin manifest name '$($manifest.name)' does not match marketplace plugin '$PluginName'"
    }
    if ($ExpectedVersion -and $manifest.version -ne $ExpectedVersion) {
        $pluginErrors += "plugin manifest version '$($manifest.version)' does not match package.json version '$ExpectedVersion'"
    }

    $componentTypes = [ordered]@{
        agents   = 'Directory'
        commands = 'Directory'
        skills   = 'Directory'
        rules    = 'Directory'
        hooks    = 'File'
    }
    $componentRoot = Join-Path $canonicalRepoRoot '.github'
    foreach ($field in $componentTypes.Keys) {
        if (-not $manifest.ContainsKey($field) -or $null -eq $manifest[$field]) {
            continue
        }

        $declaredPaths = if ($manifest[$field] -is [string]) {
            @($manifest[$field])
        }
        elseif ($manifest[$field] -is [System.Collections.IEnumerable]) {
            @($manifest[$field])
        }
        else {
            $pluginErrors += "plugin '$PluginName' manifest field '$field' must contain path strings"
            continue
        }

        foreach ($declaredPath in $declaredPaths) {
            if ($declaredPath -isnot [string] -or [string]::IsNullOrWhiteSpace($declaredPath) -or
                [System.IO.Path]::IsPathRooted($declaredPath)) {
                $pluginErrors += "plugin '$PluginName' manifest field '$field' contains an invalid path"
                continue
            }

            $resolvedPath = [System.IO.Path]::GetFullPath(
                (Join-Path -Path $canonicalRepoRoot -ChildPath $declaredPath)
            )
            if (-not (Test-PathContainedByRoot -Path $resolvedPath -Root $componentRoot)) {
                $pluginErrors += "plugin '$PluginName' manifest field '$field' path is not a canonical repository source: $declaredPath"
                continue
            }

            $targetError = Get-RegularObjectError -Path $resolvedPath `
                -ExpectedType $componentTypes[$field] -DisplayPath $declaredPath
            if ($targetError) {
                $pluginErrors += $targetError
            }
        }
    }

    return @($pluginErrors)
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

    $manifestItem = Get-Item -LiteralPath $manifestPath -Force -ErrorAction SilentlyContinue
    if ($null -eq $manifestItem) {
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

    $manifestObjectError = Get-RegularObjectError -Path $manifestPath -ExpectedType File -DisplayPath '.github/plugin/marketplace.json'
    if ($manifestObjectError) {
        $results = @(
            @{ PluginName = 'marketplace'; IsValid = $false; Errors = @($manifestObjectError); Warnings = @() }
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
        $pluginRootValue = [string]$manifest.metadata.pluginRoot
        $pluginsRoot = if ([string]::IsNullOrWhiteSpace($pluginRootValue) -or
            [System.IO.Path]::IsPathRooted($pluginRootValue)) {
            $null
        }
        else {
            [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $pluginRootValue))
        }
        $pluginRootIsContained = $pluginsRoot -and (Test-PathContainedByRoot -Path $pluginsRoot -Root $RepoRoot)
        if (-not $pluginRootIsContained) {
            $errors += "metadata.pluginRoot escapes repository root: '$pluginRootValue'"
        }
        else {
            $pluginRootError = Get-RegularObjectError -Path $pluginsRoot -ExpectedType Directory -DisplayPath $pluginRootValue
            if ($pluginRootError) {
                $errors += $pluginRootError
            }
        }
        $seenNames = @{}

        foreach ($plugin in $manifest.plugins) {
            $pluginName = $plugin.name
            $pluginErrors = @()
            $pluginWarnings = @()

            # Required plugin fields
            $pluginRequired = @('name', 'source', 'description', 'version')
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

            # Source format (no path separators)
            $sourceFormatValid = $true
            if (-not [string]::IsNullOrWhiteSpace($plugin.source)) {
                $formatError = Test-PluginSourceFormat -Source $plugin.source
                if ($formatError) {
                    $pluginErrors += $formatError
                    $sourceFormatValid = $false
                }
            }

            # Source directory existence
            if ($pluginRootIsContained -and $sourceFormatValid -and -not [string]::IsNullOrWhiteSpace($plugin.source)) {
                $dirError = Test-PluginSourceDirectory -Source $plugin.source -PluginsRoot $pluginsRoot
                if ($dirError) {
                    $pluginErrors += $dirError
                }
                else {
                    $pluginPackageRoot = Join-Path -Path $pluginsRoot -ChildPath $plugin.source
                    $pluginErrors += Test-PluginPackageContent -PluginRoot $pluginPackageRoot `
                        -PluginName $pluginName -ExpectedVersion $expectedVersion -RepoRoot $RepoRoot
                }
            }

            # Name-source consistency
            if ($pluginName -ne $plugin.source) {
                $pluginErrors += "name does not match source '$($plugin.source)'"
            }

            # Plugin version consistency
            if ($expectedVersion -and $plugin.version -ne $expectedVersion) {
                $pluginErrors += "version '$($plugin.version)' does not match package.json version '$expectedVersion'"
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
