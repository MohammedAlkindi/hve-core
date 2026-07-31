#Requires -Modules Pester
# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT

BeforeAll {
    . $PSScriptRoot/../../plugins/Assert-PluginReleaseEvidence.ps1

    function New-EvidenceFixtureRepo {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Path,

            [Parameter(Mandatory = $false)]
            [string]$Version = '1.2.3'
        )

        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Set-Content -Path (Join-Path $Path 'package.json') -Value "{`"version`":`"$Version`"}"

        foreach ($package in @('alpha', 'beta')) {
            $packageDir = Join-Path $Path "plugins/$package"
            New-Item -ItemType Directory -Path (Join-Path $packageDir 'agents') -Force | Out-Null
            Set-Content -Path (Join-Path $packageDir 'plugin.json') -Value "{`"name`":`"$package`"}" -NoNewline
            Set-Content -Path (Join-Path $packageDir 'agents/sample.md') -Value "# $package agent" -NoNewline
        }

        return $Path
    }

    $script:knownCommit = '0123456789abcdef0123456789abcdef01234567'
    $script:otherCommit = 'fedcba9876543210fedcba9876543210fedcba98'
}

Describe 'Get-PluginContentDigest' {
    BeforeAll {
        $script:treeA = Join-Path $TestDrive 'digest/a'
        $script:treeB = Join-Path $TestDrive 'digest/b'
        foreach ($tree in @($script:treeA, $script:treeB)) {
            New-Item -ItemType Directory -Path (Join-Path $tree 'nested') -Force | Out-Null
            Set-Content -Path (Join-Path $tree 'root.txt') -Value 'root' -NoNewline
            Set-Content -Path (Join-Path $tree 'nested/leaf.txt') -Value 'leaf' -NoNewline
        }
    }

    It 'Produces a lowercase hexadecimal SHA-256 digest' {
        (Get-PluginContentDigest -Path $script:treeA).Digest | Should -Match '^[0-9a-f]{64}$'
    }

    It 'Produces the same digest for identical trees at different paths' {
        (Get-PluginContentDigest -Path $script:treeA).Digest |
            Should -Be (Get-PluginContentDigest -Path $script:treeB).Digest
    }

    It 'Is stable across repeated computation' {
        (Get-PluginContentDigest -Path $script:treeA).Digest |
            Should -Be (Get-PluginContentDigest -Path $script:treeA).Digest
    }

    It 'Ignores file timestamps' {
        $baseline = (Get-PluginContentDigest -Path $script:treeA).Digest
        (Get-Item (Join-Path $script:treeA 'root.txt')).LastWriteTimeUtc = [datetime]'2001-02-03T04:05:06Z'
        (Get-PluginContentDigest -Path $script:treeA).Digest | Should -Be $baseline
    }

    It 'Changes when file content changes' {
        $baseline = (Get-PluginContentDigest -Path $script:treeB).Digest
        Set-Content -Path (Join-Path $script:treeB 'root.txt') -Value 'root-modified' -NoNewline
        (Get-PluginContentDigest -Path $script:treeB).Digest | Should -Not -Be $baseline
    }

    It 'Changes when a file is renamed without content change' {
        $tree = Join-Path $TestDrive 'digest/rename'
        New-Item -ItemType Directory -Path $tree -Force | Out-Null
        Set-Content -Path (Join-Path $tree 'one.txt') -Value 'same' -NoNewline
        $baseline = (Get-PluginContentDigest -Path $tree).Digest

        Rename-Item -Path (Join-Path $tree 'one.txt') -NewName 'two.txt'
        (Get-PluginContentDigest -Path $tree).Digest | Should -Not -Be $baseline
    }

    It 'Reports file count and total bytes' {
        $report = Get-PluginContentDigest -Path $script:treeA
        $report.FileCount | Should -Be 2
        $report.TotalBytes | Should -Be 8
    }
}

Describe 'Get-PluginTreeEvidence' {
    BeforeAll {
        $script:repoRoot = New-EvidenceFixtureRepo -Path (Join-Path $TestDrive 'tree-repo')
        $script:pluginsDir = Join-Path $script:repoRoot 'plugins'
    }

    It 'Reports every package in ordinal order' {
        $evidence = Get-PluginTreeEvidence -PluginsDir $script:pluginsDir
        @($evidence.Packages).Count | Should -Be 2
        @($evidence.Packages)[0].name | Should -Be 'alpha'
        @($evidence.Packages)[1].name | Should -Be 'beta'
    }

    It 'Gives each package its own digest' {
        $evidence = Get-PluginTreeEvidence -PluginsDir $script:pluginsDir
        @($evidence.Packages)[0].digest | Should -Match '^[0-9a-f]{64}$'
        @($evidence.Packages)[0].digest | Should -Not -Be @($evidence.Packages)[1].digest
    }

    It 'Throws when the package tree is absent' {
        { Get-PluginTreeEvidence -PluginsDir (Join-Path $TestDrive 'missing-tree') } |
            Should -Throw '*Generated package tree not found*'
    }
}

Describe 'New-PluginReleaseEvidenceDocument' {
    BeforeAll {
        $script:treeEvidence = @{
            Digest     = 'a' * 64
            FileCount  = 4
            TotalBytes = 128
            Packages   = @([ordered]@{ name = 'alpha'; digest = 'b' * 64; fileCount = 2 })
        }
    }

    It 'Binds source commit, version, locator, and digest' {
        $document = New-PluginReleaseEvidenceDocument -SourceCommit $script:knownCommit -Version '1.2.3' `
            -Locator (New-PluginReleaseLocator -Version '1.2.3') -TreeEvidence $script:treeEvidence

        $document.schema | Should -Be 'hve-core/plugin-release-evidence/v1'
        $document.sourceCommit | Should -Be $script:knownCommit
        $document.version | Should -Be '1.2.3'
        $document.locator.repo | Should -Be 'microsoft/hve-core'
        $document.locator.ref | Should -Be 'plugins-v1.2.3'
        $document.digest | Should -Be ('a' * 64)
        $document.packageCount | Should -Be 1
    }

    It 'Rejects an abbreviated source commit' {
        { New-PluginReleaseEvidenceDocument -SourceCommit '0123456' -Version '1.2.3' `
                -Locator (New-PluginReleaseLocator -Version '1.2.3') -TreeEvidence $script:treeEvidence } |
            Should -Throw '*must be a full 40-character lowercase commit id*'
    }

    It 'Rejects a locator that disagrees with the version' {
        { New-PluginReleaseEvidenceDocument -SourceCommit $script:knownCommit -Version '1.2.3' `
                -Locator (New-PluginReleaseLocator -Version '9.9.9') -TreeEvidence $script:treeEvidence } |
            Should -Throw "*does not match package version '1.2.3'*"
    }
}

Describe 'Compare-PluginReleaseEvidence' {
    BeforeAll {
        $script:actual = New-PluginReleaseEvidenceDocument -SourceCommit $script:knownCommit -Version '1.2.3' `
            -Locator (New-PluginReleaseLocator -Version '1.2.3') `
            -TreeEvidence @{
            Digest     = 'a' * 64
            FileCount  = 4
            TotalBytes = 128
            Packages   = @(
                [ordered]@{ name = 'alpha'; digest = 'b' * 64; fileCount = 2 }
                [ordered]@{ name = 'beta'; digest = 'c' * 64; fileCount = 2 }
            )
        }

        function Copy-Evidence {
            param([System.Collections.IDictionary]$Source)
            return ($Source | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable)
        }
    }

    It 'Reports no differences for matching evidence' {
        Compare-PluginReleaseEvidence -Expected (Copy-Evidence $script:actual) -Actual $script:actual |
            Should -BeNullOrEmpty
    }

    It 'Ignores the generation timestamp' {
        $expected = Copy-Evidence $script:actual
        $expected['generatedAt'] = '1999-01-01T00:00:00.0000000Z'
        Compare-PluginReleaseEvidence -Expected $expected -Actual $script:actual | Should -BeNullOrEmpty
    }

    It 'Fails on induced source commit disagreement' {
        $expected = Copy-Evidence $script:actual
        $expected['sourceCommit'] = $script:otherCommit
        @(Compare-PluginReleaseEvidence -Expected $expected -Actual $script:actual)[0] |
            Should -BeLike 'sourceCommit disagreement*'
    }

    It 'Fails on induced version disagreement' {
        $expected = Copy-Evidence $script:actual
        $expected['version'] = '9.9.9'
        @(Compare-PluginReleaseEvidence -Expected $expected -Actual $script:actual)[0] |
            Should -BeLike 'version disagreement*'
    }

    It 'Fails on induced locator disagreement' {
        $expected = Copy-Evidence $script:actual
        $expected['locator']['ref'] = 'plugins-v9.9.9'
        @(Compare-PluginReleaseEvidence -Expected $expected -Actual $script:actual)[0] |
            Should -BeLike 'locator.ref disagreement*'
    }

    It 'Fails on induced digest disagreement' {
        $expected = Copy-Evidence $script:actual
        $expected['digest'] = 'd' * 64
        @(Compare-PluginReleaseEvidence -Expected $expected -Actual $script:actual)[0] |
            Should -BeLike 'digest disagreement*'
    }

    It 'Fails on induced package digest disagreement' {
        $expected = Copy-Evidence $script:actual
        $expected['packages'][0]['digest'] = 'e' * 64
        @(Compare-PluginReleaseEvidence -Expected $expected -Actual $script:actual)[0] |
            Should -BeLike "package 'alpha' digest disagreement*"
    }

    It 'Fails when a package is missing from recorded evidence' {
        $expected = Copy-Evidence $script:actual
        $expected['packages'] = @($expected['packages'][0])
        @(Compare-PluginReleaseEvidence -Expected $expected -Actual $script:actual) |
            Should -Contain "package 'beta' is present in the snapshot but absent from recorded evidence"
    }

    It 'Fails when recorded evidence names an absent package' {
        $expected = Copy-Evidence $script:actual
        $expected['packages'] += [ordered]@{ name = 'gamma'; digest = 'f' * 64; fileCount = 1 }
        @(Compare-PluginReleaseEvidence -Expected $expected -Actual $script:actual) |
            Should -Contain "package 'gamma' is recorded in evidence but absent from the snapshot"
    }

    It 'Fails when a required field is absent from recorded evidence' {
        $expected = Copy-Evidence $script:actual
        $expected.Remove('digest')
        @(Compare-PluginReleaseEvidence -Expected $expected -Actual $script:actual) |
            Should -Contain "recorded evidence is missing required field 'digest'"
    }
}

Describe 'Invoke-PluginReleaseEvidence' {
    BeforeAll {
        $script:repoRoot = New-EvidenceFixtureRepo -Path (Join-Path $TestDrive 'invoke-repo')
        $script:evidencePath = Join-Path $TestDrive 'invoke-evidence.json'
        Mock Write-Host {}
    }

    It 'Records evidence without comparing to committed output' {
        $result = Invoke-PluginReleaseEvidence -RepoRoot $script:repoRoot -SourceCommit $script:knownCommit `
            -OutputPath $script:evidencePath

        $result.Success | Should -BeTrue
        $result.Evidence.digest | Should -Match '^[0-9a-f]{64}$'
        Test-Path -LiteralPath $script:evidencePath | Should -BeTrue
    }

    It 'Verifies recorded evidence against an unchanged snapshot' {
        $result = Invoke-PluginReleaseEvidence -RepoRoot $script:repoRoot -SourceCommit $script:knownCommit `
            -ExpectedEvidencePath $script:evidencePath

        $result.Success | Should -BeTrue
        $result.ErrorCount | Should -Be 0
    }

    It 'Fails when the snapshot content changes' {
        Set-Content -Path (Join-Path $script:repoRoot 'plugins/alpha/agents/sample.md') -Value 'tampered' -NoNewline
        try {
            $result = Invoke-PluginReleaseEvidence -RepoRoot $script:repoRoot -SourceCommit $script:knownCommit `
                -ExpectedEvidencePath $script:evidencePath

            $result.Success | Should -BeFalse
            @($result.Errors) | Should -Not -BeNullOrEmpty
        }
        finally {
            Set-Content -Path (Join-Path $script:repoRoot 'plugins/alpha/agents/sample.md') -Value '# alpha agent' -NoNewline
        }
    }

    It 'Fails when the source commit changes' {
        $result = Invoke-PluginReleaseEvidence -RepoRoot $script:repoRoot -SourceCommit $script:otherCommit `
            -ExpectedEvidencePath $script:evidencePath

        $result.Success | Should -BeFalse
        @($result.Errors)[0] | Should -BeLike 'sourceCommit disagreement*'
    }

    It 'Fails when the package version changes' {
        Set-Content -Path (Join-Path $script:repoRoot 'package.json') -Value '{"version":"9.9.9"}'
        try {
            $result = Invoke-PluginReleaseEvidence -RepoRoot $script:repoRoot -SourceCommit $script:knownCommit `
                -ExpectedEvidencePath $script:evidencePath

            $result.Success | Should -BeFalse
            @($result.Errors) | Should -Not -BeNullOrEmpty
        }
        finally {
            Set-Content -Path (Join-Path $script:repoRoot 'package.json') -Value '{"version":"1.2.3"}'
        }
    }

    It 'Fails on corrupt recorded evidence' {
        $corruptPath = Join-Path $TestDrive 'corrupt-evidence.json'
        Set-Content -Path $corruptPath -Value '{ not json'

        $result = Invoke-PluginReleaseEvidence -RepoRoot $script:repoRoot -SourceCommit $script:knownCommit `
            -ExpectedEvidencePath $corruptPath

        $result.Success | Should -BeFalse
        @($result.Errors)[0] | Should -BeLike '*not valid JSON*'
    }

    It 'Fails when recorded evidence is absent' {
        $result = Invoke-PluginReleaseEvidence -RepoRoot $script:repoRoot -SourceCommit $script:knownCommit `
            -ExpectedEvidencePath (Join-Path $TestDrive 'no-such-evidence.json')

        $result.Success | Should -BeFalse
        @($result.Errors)[0] | Should -BeLike '*recorded evidence not found*'
    }

    It 'Rejects a sha release locator' {
        { Invoke-PluginReleaseEvidence -RepoRoot $script:repoRoot -SourceCommit $script:knownCommit `
                -ReleaseTag $script:knownCommit } |
            Should -Throw '*Sha-pinned catalog sources are not supported*'
    }

    It 'Passes a satisfied package count precondition' {
        $result = Invoke-PluginReleaseEvidence -RepoRoot $script:repoRoot -SourceCommit $script:knownCommit `
            -ExpectedPackageCount 2

        $result.Success | Should -BeTrue
    }

    It 'Fails an unsatisfied package count precondition' {
        $result = Invoke-PluginReleaseEvidence -RepoRoot $script:repoRoot -SourceCommit $script:knownCommit `
            -ExpectedPackageCount 15

        $result.Success | Should -BeFalse
        @($result.Errors)[0] | Should -BeLike '*package count precondition failed: expected 15, snapshot has 2*'
    }
}
