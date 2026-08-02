# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
    Copies selected HVE-Core agents to the target repository.
.DESCRIPTION
    Creates .github/agents/ directory, copies agent files, computes SHA256 hashes,
    and writes .hve-tracking.json manifest for upgrade tracking.
.PARAMETER HveCoreBasePath
    Root path of the local HVE-Core clone used as the copy source.
.PARAMETER PackageId
    Marketplace package identifier recorded in the tracking manifest.
.PARAMETER FilesToCopy
    Array of agent file paths relative to the source agents directory.
.PARAMETER KeepExisting
    When set, existing files listed in Collisions are preserved instead of overwritten.
.PARAMETER Collisions
    Array of target file paths that already exist and may conflict.
.EXAMPLE
    ./scripts/agent-copy.ps1 -HveCoreBasePath ../hve-core -PackageId hve-core -FilesToCopy @('hve-core/rpi-agent.agent.md')
.OUTPUTS
    Per-file copy status and manifest creation confirmation.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ })]
    [string]$HveCoreBasePath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PackageId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$FilesToCopy,

    [Parameter()]
    [switch]$KeepExisting,

    [Parameter()]
    [string[]]$Collisions = @()
)

$ErrorActionPreference = 'Stop'

$sourceBase = "$hveCoreBasePath/.github/agents"
$targetDir = ".github/agents"
$manifestPath = ".hve-tracking.json"

# Create target directory
if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    Write-Host "✅ Created $targetDir"
}

# Initialize manifest
$manifest = @{
    source = "microsoft/hve-core"
    version = (Get-Content "$hveCoreBasePath/package.json" | ConvertFrom-Json).version
    installed = (Get-Date -Format "o")
    package = $PackageId
    files = @{}
}

# Copy files (source paths are relative to agents/, target is flat). Target
# paths stay forward-slashed so they match the COLLISION_FILES values produced
# by collision-detection on every platform.
foreach ($file in $filesToCopy) {
    $fileName = Split-Path $file -Leaf
    $sourcePath = Join-Path $sourceBase $file
    $targetPath = "$targetDir/$fileName"
    $relPath = ".github/agents/$fileName"

    if ($keepExisting -and $collisions -contains $targetPath) {
        Write-Host "⏭️ Kept existing: $fileName"; continue
    }

    Set-Content -Path $targetPath -Value (Get-Content $sourcePath -Raw) -NoNewline
    $hash = (Get-FileHash -Path $targetPath -Algorithm SHA256).Hash.ToLower()
    $manifest.files[$relPath] = @{ version = $manifest.version; sha256 = $hash; status = "managed" }
    Write-Host "✅ Copied $fileName"
}

$manifest | ConvertTo-Json -Depth 10 | Set-Content $manifestPath
Write-Host "✅ Created $manifestPath"
