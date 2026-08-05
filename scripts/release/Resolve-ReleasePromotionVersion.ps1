#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Resolves an exact version for a release branch promotion.
.DESCRIPTION
    Applies the repository's odd-minor PreRelease and even-minor Stable version
    rules to explicit channel versions and a caller-supplied release class.
.PARAMETER Channel
    Channel receiving the promotion.
.PARAMETER CurrentPreReleaseVersion
    Current numeric PreRelease version.
.PARAMETER CurrentStableVersion
    Current numeric Stable version.
.PARAMETER PromotedSourceVersion
    Version associated with the promoted source. Required for Stable.
.PARAMETER ReleaseClass
    Conventional release class resolved by the calling workflow.
.PARAMETER AsJson
    Emit a compressed JSON object instead of a PowerShell object.
.EXAMPLE
    ./Resolve-ReleasePromotionVersion.ps1 -Channel PreRelease `
        -CurrentPreReleaseVersion 3.3.101 -CurrentStableVersion 3.2.2
.EXAMPLE
    ./Resolve-ReleasePromotionVersion.ps1 -Channel Stable `
        -CurrentPreReleaseVersion 3.3.102 -CurrentStableVersion 3.2.2 `
        -PromotedSourceVersion 3.3.102 -ReleaseClass minor -AsJson
.NOTES
    This script performs no repository or network access. Promotion workflows
    own commit classification and supply the current branch state.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('PreRelease', 'Stable')]
    [string]$Channel,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$CurrentPreReleaseVersion,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$CurrentStableVersion,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$PromotedSourceVersion,

    [Parameter(Mandatory = $false)]
    [ValidateSet('patch', 'minor', 'major')]
    [string]$ReleaseClass = 'patch',

    [Parameter(Mandatory = $false)]
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'

#region Functions

function Resolve-ReleasePromotionVersion {
    <#
    .SYNOPSIS
        Resolves and validates the next channel version.
    .OUTPUTS
        [pscustomobject] The resolved version and its inputs.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('PreRelease', 'Stable')]
        [string]$Channel,

        [Parameter(Mandatory = $true)]
        [version]$CurrentPreReleaseVersion,

        [Parameter(Mandatory = $true)]
        [version]$CurrentStableVersion,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [version]$PromotedSourceVersion,

        [Parameter(Mandatory = $true)]
        [ValidateSet('patch', 'minor', 'major')]
        [string]$ReleaseClass
    )

    if ($CurrentPreReleaseVersion.Minor % 2 -eq 0) {
        throw "PreRelease baseline must have an odd minor: $CurrentPreReleaseVersion"
    }
    if ($CurrentStableVersion.Minor % 2 -ne 0) {
        throw "Stable baseline must have an even minor: $CurrentStableVersion"
    }

    if ($Channel -eq 'PreRelease') {
        if ($ReleaseClass -eq 'major') {
            $nextMajor = [Math]::Max(
                $CurrentPreReleaseVersion.Major,
                $CurrentStableVersion.Major
            ) + 1
            $candidate = [version]::new($nextMajor, 1, 0)
        }
        elseif (
            $CurrentPreReleaseVersion.Major -lt $CurrentStableVersion.Major -or
            (
                $CurrentPreReleaseVersion.Major -eq $CurrentStableVersion.Major -and
                $CurrentPreReleaseVersion.Minor -le $CurrentStableVersion.Minor
            )
        ) {
            $candidate = [version]::new(
                $CurrentStableVersion.Major,
                $CurrentStableVersion.Minor + 1,
                0
            )
        }
        else {
            $candidate = [version]::new(
                $CurrentPreReleaseVersion.Major,
                $CurrentPreReleaseVersion.Minor,
                $CurrentPreReleaseVersion.Build + 1
            )
        }

        if ($candidate.Minor % 2 -eq 0 -or $candidate -le $CurrentStableVersion) {
            throw "Resolved PreRelease version must be odd-minor and greater than Stable: $candidate"
        }
    }
    else {
        if ($null -eq $PromotedSourceVersion) {
            throw 'PromotedSourceVersion is required for Stable resolution'
        }
        if ($PromotedSourceVersion.Minor % 2 -eq 0) {
            throw "Stable promotion source must have an odd minor: $PromotedSourceVersion"
        }
        if ($PromotedSourceVersion -le $CurrentStableVersion) {
            throw "Stable promotion source must be greater than the Stable baseline"
        }

        switch ($ReleaseClass) {
            'patch' {
                $candidate = [version]::new(
                    $CurrentStableVersion.Major,
                    $CurrentStableVersion.Minor,
                    $CurrentStableVersion.Build + 1
                )
            }
            'minor' {
                if ($PromotedSourceVersion.Major -ne $CurrentStableVersion.Major) {
                    throw 'A cross-major Stable promotion requires ReleaseClass major'
                }
                $nextMinor = [Math]::Max(
                    $CurrentStableVersion.Minor + 2,
                    $PromotedSourceVersion.Minor + 1
                )
                if ($nextMinor % 2 -ne 0) {
                    $nextMinor++
                }
                $candidate = [version]::new($CurrentStableVersion.Major, $nextMinor, 0)
            }
            'major' {
                $nextMajor = [Math]::Max(
                    $CurrentStableVersion.Major + 1,
                    $PromotedSourceVersion.Major
                )
                $candidate = [version]::new($nextMajor, 0, 0)
            }
        }

        if ($candidate.Minor % 2 -ne 0 -or $candidate -le $CurrentStableVersion) {
            throw "Resolved Stable version must be even-minor and greater than its baseline: $candidate"
        }
    }

    return [pscustomobject]@{
        Version                   = $candidate.ToString(3)
        Channel                   = $Channel
        ReleaseClass              = $ReleaseClass
        CurrentPreReleaseVersion  = $CurrentPreReleaseVersion.ToString(3)
        CurrentStableVersion      = $CurrentStableVersion.ToString(3)
        PromotedSourceVersion     = if ($null -eq $PromotedSourceVersion) {
            $null
        }
        else {
            $PromotedSourceVersion.ToString(3)
        }
    }
}

#endregion Functions

#region Main Execution

if ($MyInvocation.InvocationName -ne '.') {
    $result = Resolve-ReleasePromotionVersion `
        -Channel $Channel `
        -CurrentPreReleaseVersion ([version]$CurrentPreReleaseVersion) `
        -CurrentStableVersion ([version]$CurrentStableVersion) `
        -PromotedSourceVersion $(
            if ($PromotedSourceVersion) { [version]$PromotedSourceVersion }
            else { $null }
        ) `
        -ReleaseClass $ReleaseClass

    if ($AsJson) {
        $result | ConvertTo-Json -Compress
    }
    else {
        $result
    }
}

#endregion Main Execution
