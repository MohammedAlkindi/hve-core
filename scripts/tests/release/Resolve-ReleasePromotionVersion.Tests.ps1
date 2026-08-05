#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../release/Resolve-ReleasePromotionVersion.ps1'
    . $script:ScriptPath `
        -Channel PreRelease `
        -CurrentPreReleaseVersion '3.3.101' `
        -CurrentStableVersion '3.2.2'
}

Describe 'Resolve-ReleasePromotionVersion' -Tag 'Unit' {
    It 'Advances the current PreRelease line by patch for <ReleaseClass>' -ForEach @(
        @{ ReleaseClass = 'patch' }
        @{ ReleaseClass = 'minor' }
    ) {
        $result = Resolve-ReleasePromotionVersion `
            -Channel PreRelease `
            -CurrentPreReleaseVersion ([version]'3.3.101') `
            -CurrentStableVersion ([version]'3.2.2') `
            -ReleaseClass $ReleaseClass

        $result.Version | Should -BeExactly '3.3.102'
    }

    It 'Re-anchors PreRelease one odd minor above an advanced Stable line' {
        $result = Resolve-ReleasePromotionVersion `
            -Channel PreRelease `
            -CurrentPreReleaseVersion ([version]'3.3.102') `
            -CurrentStableVersion ([version]'3.4.0') `
            -ReleaseClass patch

        $result.Version | Should -BeExactly '3.5.0'
    }

    It 'Starts a breaking PreRelease line on the next major and odd minor' {
        $result = Resolve-ReleasePromotionVersion `
            -Channel PreRelease `
            -CurrentPreReleaseVersion ([version]'3.3.102') `
            -CurrentStableVersion ([version]'3.2.2') `
            -ReleaseClass major

        $result.Version | Should -BeExactly '4.1.0'
    }

    It 'Advances a Stable patch without changing its even minor' {
        $result = Resolve-ReleasePromotionVersion `
            -Channel Stable `
            -CurrentPreReleaseVersion ([version]'3.3.102') `
            -CurrentStableVersion ([version]'3.2.2') `
            -PromotedSourceVersion ([version]'3.3.102') `
            -ReleaseClass patch

        $result.Version | Should -BeExactly '3.2.3'
    }

    It 'Advances Stable to the next even minor' {
        $result = Resolve-ReleasePromotionVersion `
            -Channel Stable `
            -CurrentPreReleaseVersion ([version]'3.3.102') `
            -CurrentStableVersion ([version]'3.2.2') `
            -PromotedSourceVersion ([version]'3.3.102') `
            -ReleaseClass minor

        $result.Version | Should -BeExactly '3.4.0'
    }

    It 'Advances Stable to a promoted breaking major' {
        $result = Resolve-ReleasePromotionVersion `
            -Channel Stable `
            -CurrentPreReleaseVersion ([version]'4.1.0') `
            -CurrentStableVersion ([version]'3.2.2') `
            -PromotedSourceVersion ([version]'4.1.0') `
            -ReleaseClass major

        $result.Version | Should -BeExactly '4.0.0'
    }

    It 'Rejects an even-minor PreRelease baseline' {
        {
            Resolve-ReleasePromotionVersion `
                -Channel PreRelease `
                -CurrentPreReleaseVersion ([version]'3.4.0') `
                -CurrentStableVersion ([version]'3.2.2') `
                -ReleaseClass patch
        } | Should -Throw '*odd minor*'
    }

    It 'Rejects an odd-minor Stable baseline' {
        {
            Resolve-ReleasePromotionVersion `
                -Channel Stable `
                -CurrentPreReleaseVersion ([version]'3.3.102') `
                -CurrentStableVersion ([version]'3.3.0') `
                -PromotedSourceVersion ([version]'3.3.102') `
                -ReleaseClass patch
        } | Should -Throw '*even minor*'
    }

    It 'Requires a promoted source version for Stable' {
        {
            Resolve-ReleasePromotionVersion `
                -Channel Stable `
                -CurrentPreReleaseVersion ([version]'3.3.102') `
                -CurrentStableVersion ([version]'3.2.2') `
                -ReleaseClass patch
        } | Should -Throw '*required for Stable*'
    }

    It 'Rejects a Stable source that does not advance beyond its baseline' {
        {
            Resolve-ReleasePromotionVersion `
                -Channel Stable `
                -CurrentPreReleaseVersion ([version]'3.3.102') `
                -CurrentStableVersion ([version]'3.2.2') `
                -PromotedSourceVersion ([version]'3.1.9') `
                -ReleaseClass patch
        } | Should -Throw '*greater than the Stable baseline*'
    }

    It 'Owns cross-channel ordering without comparing co-located manifests' {
        $preRelease = Resolve-ReleasePromotionVersion `
            -Channel PreRelease `
            -CurrentPreReleaseVersion ([version]'3.3.102') `
            -CurrentStableVersion ([version]'3.4.0') `
            -ReleaseClass patch
        $preRelease.Version | Should -BeExactly '3.5.0'

        $stable = Resolve-ReleasePromotionVersion `
            -Channel Stable `
            -CurrentPreReleaseVersion ([version]$preRelease.Version) `
            -CurrentStableVersion ([version]'3.4.0') `
            -PromotedSourceVersion ([version]$preRelease.Version) `
            -ReleaseClass patch
        $stable.Version | Should -BeExactly '3.4.1'
    }

    It 'Emits compressed JSON from the script entry point' {
        $json = & $script:ScriptPath `
            -Channel Stable `
            -CurrentPreReleaseVersion '3.3.102' `
            -CurrentStableVersion '3.2.2' `
            -PromotedSourceVersion '3.3.102' `
            -ReleaseClass minor `
            -AsJson

        ($json | ConvertFrom-Json).Version | Should -BeExactly '3.4.0'
    }
}
