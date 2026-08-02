# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
    Detects file collisions before copying HVE-Core agents.
.DESCRIPTION
    Checks the target directory for existing agent files that would conflict
    with the selected agent bundle or marketplace package.
.PARAMETER Selection
    Agent bundle to check. Use 'hve-core' for the default set or a package identifier.
.PARAMETER PackageAgents
    Projected agent file paths relative to the agents directory for non-default packages.
.EXAMPLE
    ./scripts/collision-detection.ps1 -Selection hve-core
.EXAMPLE
    ./scripts/collision-detection.ps1 -Selection my-package -PackageAgents @('my-package/custom.agent.md')
.OUTPUTS
    COLLISIONS_DETECTED=true/false and COLLISION_FILES list.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Selection,

    [Parameter()]
    [string[]]$PackageAgents = @()
)

$ErrorActionPreference = 'Stop'

$targetDir = ".github/agents"

# Get files to copy based on selection (paths relative to agents/)
$filesToCopy = switch ($selection) {
    "hve-core" { @("hve-core/rpi-agent.agent.md", "hve-core/documentation.agent.md") }
    default {
        $PackageAgents
    }
}

# Check for collisions. The target is flat, so only the file name matters and
# two package agents sharing a name resolve to one target. Paths stay
# forward-slashed and de-duplicated so this script and its Bash counterpart
# emit byte-identical COLLISION_FILES values on every platform.
$collisions = [System.Collections.Generic.List[string]]::new()
$seenTargets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($file in $filesToCopy) {
    $fileName = Split-Path $file -Leaf
    $targetPath = "$targetDir/$fileName"
    if (-not $seenTargets.Add($targetPath)) { continue }
    if (Test-Path -LiteralPath $targetPath) { $collisions.Add($targetPath) }
}

if ($collisions.Count -gt 0) {
    Write-Host "COLLISIONS_DETECTED=true"
    Write-Host "COLLISION_FILES=$($collisions -join ',')"
} else {
    Write-Host "COLLISIONS_DETECTED=false"
}
