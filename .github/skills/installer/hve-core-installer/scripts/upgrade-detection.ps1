# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
    Detects whether the current installation is eligible for upgrade.
.DESCRIPTION
    Checks for .hve-tracking.json and compares installed version against
    the source HVE-Core version from package.json.
.PARAMETER HveCoreBasePath
    Root path of the local HVE-Core clone containing package.json.
.EXAMPLE
    ./scripts/upgrade-detection.ps1 -HveCoreBasePath ../hve-core
.OUTPUTS
    UPGRADE_MODE, INSTALLED_VERSION, SOURCE_VERSION, VERSION_CHANGED,
    INSTALLED_PACKAGE key-value pairs.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ })]
    [string]$HveCoreBasePath
)

$ErrorActionPreference = 'Stop'
$manifestPath = ".hve-tracking.json"

if (Test-Path $manifestPath) {
    $manifest = Get-Content $manifestPath | ConvertFrom-Json -AsHashtable
    $sourceVersion = (Get-Content "$hveCoreBasePath/package.json" | ConvertFrom-Json).version

    Write-Host "UPGRADE_MODE=true"
    Write-Host "INSTALLED_VERSION=$($manifest.version)"
    Write-Host "SOURCE_VERSION=$sourceVersion"
    # Lower-cased so the emitted value matches UPGRADE_MODE and the Bash detector.
    $versionChanged = if ($sourceVersion -ne $manifest.version) { 'true' } else { 'false' }
    Write-Host "VERSION_CHANGED=$versionChanged"
    $package = if ($manifest.package) { $manifest.package } else { 'hve-core' }
    Write-Host "INSTALLED_PACKAGE=$package"
} else {
    Write-Host "UPGRADE_MODE=false"
}
