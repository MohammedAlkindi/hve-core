#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

BeforeAll {
    $script:ScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '../../release/Assert-ReleaseAssetSet.ps1')).Path
    $script:SourceCommit = '0123456789abcdef0123456789abcdef01234567'
    $script:ReleaseTag = 'prerelease-v3.3.0'

    . $script:ScriptPath `
        -AssetNamePath 'unused' `
        -EvidencePath 'unused' `
        -RequiredAssetPath 'unused' `
        -Channel PreRelease `
        -Version '3.3.0' `
        -ReleaseTag $script:ReleaseTag `
        -SourceCommit $script:SourceCommit

    $script:RequiredAsset = [string[]]@('dependencies.spdx.json', 'plugin-release-evidence.json')
    $script:ExpectedVsix = [string[]]@('hve-alpha-3.3.0.vsix', 'hve-beta-3.3.0.vsix')

    function New-ReleasedCatalog {
        <#
        .SYNOPSIS
        Writes a released marketplace catalog for fixture use.
        .DESCRIPTION
        VSIX membership and the evidence package set both derive from this
        catalog. The deprecated entry is excluded by channel policy, so the
        expected identities follow policy rather than a hand-maintained count.
        .PARAMETER Root
        Directory to populate.
        .OUTPUTS
        [string] Absolute path to the written catalog.
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory = $true)][string]$Root
        )

        New-Item -ItemType Directory -Path (Join-Path $Root '.github/plugin') -Force | Out-Null
        $catalog = [ordered]@{
            metadata = [ordered]@{ version = '3.3.0' }
            plugins  = @(
                [ordered]@{
                    name    = 'alpha'
                    version = '3.3.0'
                    source  = [ordered]@{ source = 'github'; repo = 'contoso/hve'; path = 'plugins/alpha'; ref = 'prerelease-v3.3.0' }
                }
                [ordered]@{
                    name    = 'beta'
                    version = '3.3.0'
                    source  = [ordered]@{ source = 'github'; repo = 'contoso/hve'; path = 'plugins/beta'; ref = 'prerelease-v3.3.0' }
                }
                [ordered]@{
                    name    = 'retired'
                    version = '3.3.0'
                    source  = [ordered]@{ source = 'github'; repo = 'contoso/hve'; path = 'plugins/retired'; ref = 'prerelease-v3.3.0' }
                    'x-hve' = [ordered]@{ maturity = 'deprecated' }
                }
            )
        }
        $catalogPath = Join-Path $Root '.github/plugin/marketplace.json'
        Set-Content -LiteralPath $catalogPath -Value (($catalog | ConvertTo-Json -Depth 8) + "`n") -Encoding utf8NoBOM -NoNewline
        return $catalogPath
    }

    $script:FixtureCatalog = New-ReleasedCatalog -Root (Join-Path $TestDrive 'released-repo')

    function New-AssetSet {
        <#
        .SYNOPSIS
        Builds a complete release asset name set with optional mutations.
        .PARAMETER Remove
        Asset names to drop from the complete set.
        .PARAMETER Add
        Asset names to append to the set.
        .OUTPUTS
        [string[]] Release asset names.
        #>
        [CmdletBinding()]
        [OutputType([string[]])]
        param(
            [Parameter(Mandatory = $false)]
            [string[]]$Remove = @(),

            [Parameter(Mandatory = $false)]
            [string[]]$Add = @()
        )

        $names = [System.Collections.Generic.List[string]]::new()
        foreach ($required in $script:RequiredAsset) { $names.Add($required) }
        foreach ($primary in $script:ExpectedVsix) {
            $names.Add($primary)
            foreach ($suffix in @('.spdx.json', '.sigstore.json', '.intoto.jsonl')) {
                $names.Add($primary + $suffix)
            }
        }
        return [string[]]@(@($names | Where-Object { $Remove -notcontains $_ }) + @($Add))
    }

    function Invoke-AssetSetTest {
        <#
        .SYNOPSIS
        Reconciles a mutated asset set against the shared expected identities.
        .PARAMETER AssetName
        Actual release asset names.
        .OUTPUTS
        [string[]] Findings.
        #>
        [CmdletBinding()]
        [OutputType([string[]])]
        param(
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [string[]]$AssetName
        )

        return Test-ReleaseAssetSet -AssetName $AssetName `
            -ExpectedVsix $script:ExpectedVsix `
            -RequiredAsset $script:RequiredAsset
    }

    function New-EvidenceDocument {
        <#
        .SYNOPSIS
        Builds a plugin release evidence document for fixture use.
        .PARAMETER Version
        Recorded release version.
        .PARAMETER PackageName
        Recorded package names. Defaults to the channel-eligible catalog set.
        .PARAMETER PackageCount
        Declared package count. Defaults to the package name count.
        .PARAMETER Schema
        Declared evidence schema.
        .PARAMETER Commit
        Recorded source commit.
        .PARAMETER Ref
        Recorded locator ref.
        .OUTPUTS
        [hashtable] Evidence document.
        #>
        [CmdletBinding()]
        [OutputType([hashtable])]
        param(
            [Parameter(Mandatory = $false)]
            [string]$Version = '3.3.0',

            [Parameter(Mandatory = $false)]
            [AllowEmptyCollection()]
            [string[]]$PackageName = @('alpha', 'beta'),

            [Parameter(Mandatory = $false)]
            [int]$PackageCount = -1,

            [Parameter(Mandatory = $false)]
            [string]$Schema = 'hve-core/plugin-release-evidence/v2',

            [Parameter(Mandatory = $false)]
            [string]$Commit = $script:SourceCommit,

            [Parameter(Mandatory = $false)]
            [string]$Ref = 'prerelease-v3.3.0'
        )

        $packages = @($PackageName | ForEach-Object {
                @{ name = $_; digest = ('0' * 64); fileCount = 3 }
            })

        return @{
            schema       = $Schema
            sourceCommit = $Commit
            version      = $Version
            locator      = @{ source = 'github'; repo = 'contoso/hve'; ref = $Ref }
            packageCount = $(if ($PackageCount -ge 0) { $PackageCount } else { $packages.Count })
            packages     = $packages
            fileCount    = 6
            totalBytes   = 1024
            digest       = ('a' * 64)
        }
    }

    function Invoke-EvidenceAssertion {
        <#
        .SYNOPSIS
        Reconciles an evidence document against the released fixture catalog.
        .PARAMETER Evidence
        Evidence document to reconcile.
        .PARAMETER Version
        Released version.
        .PARAMETER ReleaseTag
        Released channel tag.
        .PARAMETER SourceCommit
        Released source commit.
        .OUTPUTS
        [string[]] Reconciled package names.
        #>
        [CmdletBinding()]
        [OutputType([string[]])]
        param(
            [Parameter(Mandatory = $true)]
            [System.Collections.IDictionary]$Evidence,

            [Parameter(Mandatory = $false)]
            [string]$Version = '3.3.0',

            [Parameter(Mandatory = $false)]
            [string]$ReleaseTag = $script:ReleaseTag,

            [Parameter(Mandatory = $false)]
            [string]$SourceCommit = $script:SourceCommit
        )

        return Assert-ReleaseEvidenceDocument -Evidence $Evidence `
            -Version $Version `
            -ReleaseTag $ReleaseTag `
            -SourceCommit $SourceCommit `
            -CatalogPath $script:FixtureCatalog
    }
}

Describe 'Assert-ReleaseAssetSet expected identities' -Tag 'Unit' {
    Context 'Evidence package set from the released catalog' {
        It 'Reconciles one package per released catalog entry' {
            # A deprecated catalog entry contributes no expected package, so the
            # count follows channel policy rather than a hand-maintained number.
            Invoke-EvidenceAssertion -Evidence (New-EvidenceDocument) | Should -Be @('alpha', 'beta')
        }

        It 'Derives the expectation from the catalog rather than the evidence ordering' {
            Invoke-EvidenceAssertion -Evidence (New-EvidenceDocument -PackageName @('beta', 'alpha')) |
                Should -Be @('alpha', 'beta')
        }

        # A tampered release can rewrite plugin-release-evidence.json into a
        # smaller self-consistent document, so the released catalog is the
        # authority the document is reconciled against.
        It 'Rejects a self-consistent evidence document that omits a released catalog package' {
            { Invoke-EvidenceAssertion -Evidence (New-EvidenceDocument -PackageName @('alpha')) } |
                Should -Throw '*omits released catalog package(s): beta*'
        }

        It 'Rejects evidence recording a package the released catalog does not publish' {
            { Invoke-EvidenceAssertion -Evidence (New-EvidenceDocument -PackageName @('alpha', 'beta', 'gamma')) } |
                Should -Throw '*does not publish: gamma*'
        }

        It 'Rejects evidence recording a package the channel policy excludes' {
            { Invoke-EvidenceAssertion -Evidence (New-EvidenceDocument -PackageName @('alpha', 'beta', 'retired')) } |
                Should -Throw '*does not publish: retired*'
        }

        It 'Matches evidence package names ordinally' {
            { Invoke-EvidenceAssertion -Evidence (New-EvidenceDocument -PackageName @('Alpha', 'beta')) } |
                Should -Throw '*omits released catalog package(s): alpha*'
        }

        It 'Rejects evidence recorded for a different version' {
            { Invoke-EvidenceAssertion -Evidence (New-EvidenceDocument -Version '3.1.0') } |
                Should -Throw '*records version 3.1.0 but the release is 3.3.0*'
        }

        It 'Rejects a packageCount that disagrees with the package array' {
            { Invoke-EvidenceAssertion -Evidence (New-EvidenceDocument -PackageCount 5) } |
                Should -Throw '*declares packageCount 5 but carries 2 package entries*'
        }

        It 'Rejects an empty package set' {
            { Invoke-EvidenceAssertion -Evidence (New-EvidenceDocument -PackageName @() -PackageCount 0) } |
                Should -Throw '*declares packageCount 0*'
        }

        It 'Rejects duplicate package names' {
            { Invoke-EvidenceAssertion -Evidence (New-EvidenceDocument -PackageName @('alpha', 'alpha')) } |
                Should -Throw '*duplicate package names*'
        }

        It 'Rejects a package entry without a name' {
            { Invoke-EvidenceAssertion -Evidence (New-EvidenceDocument -PackageName @('alpha', ' ')) } |
                Should -Throw '*package entry without a name*'
        }

        It 'Rejects evidence missing a required field' {
            $evidence = New-EvidenceDocument
            $evidence.Remove('packageCount')
            { Invoke-EvidenceAssertion -Evidence $evidence } |
                Should -Throw "*declares no 'packageCount' field*"
        }
    }

    # The current schema is the only contract a release may carry, and every
    # binding it records is checked against the release it is attached to.
    Context 'Current evidence schema and release bindings' {
        It 'Rejects a superseded evidence schema' {
            { Invoke-EvidenceAssertion -Evidence (New-EvidenceDocument -Schema 'hve-core/plugin-release-evidence/v1') } |
                Should -Throw '*declares schema hve-core/plugin-release-evidence/v1 but hve-core/plugin-release-evidence/v2 is required*'
        }

        It 'Rejects evidence recorded from a different source commit' {
            { Invoke-EvidenceAssertion -Evidence (New-EvidenceDocument -Commit 'fedcba9876543210fedcba9876543210fedcba98') } |
                Should -Throw '*but the release was published from*'
        }

        It 'Rejects evidence whose locator addresses another channel tag' {
            { Invoke-EvidenceAssertion -Evidence (New-EvidenceDocument -Ref 'v3.3.0') } |
                Should -Throw '*records locator ref v3.3.0 but the release tag is prerelease-v3.3.0*'
        }

        It 'Rejects evidence carrying no locator object' {
            $evidence = New-EvidenceDocument
            $evidence['locator'] = 'prerelease-v3.3.0'
            { Invoke-EvidenceAssertion -Evidence $evidence } | Should -Throw '*carries no locator object*'
        }
    }

    Context 'VSIX identities from the released catalog' {
        It 'Derives one VSIX identity per <Channel>-eligible catalog package' -ForEach @(
            @{ Channel = 'PreRelease' }
            @{ Channel = 'Stable' }
        ) {
            # The count follows the catalog under channel policy, so a
            # deprecated package contributes no expected VSIX.
            Get-ReleaseExpectedVsixName -Channel $Channel -Version '3.3.0' -CatalogPath $script:FixtureCatalog |
                Should -Be @('hve-alpha-3.3.0.vsix', 'hve-beta-3.3.0.vsix')
        }

        It 'Resolves the repository catalog and its extension identities' {
            $catalog = (Resolve-Path (Join-Path $PSScriptRoot '../../../.github/plugin/marketplace.json')).Path
            $actual = Get-ReleaseExpectedVsixName -Channel Stable -Version '9.9.9' -CatalogPath $catalog
            @($actual).Count | Should -BeGreaterThan 1
            $actual | Should -Contain 'hve-core-9.9.9.vsix'
            $actual | Should -Contain 'hve-security-9.9.9.vsix'
            @($actual | Where-Object { $_ -notmatch '^hve-[a-z0-9-]+-9\.9\.9\.vsix$' }) | Should -BeNullOrEmpty
        }
    }

    Context 'Repeated import' {
        # A ReadOnly script variable cannot be replaced without -Force, so a
        # second dot-source of the helper must stay possible.
        It 'Dot-sources again without failing on its script-scoped state' {
            {
                . $script:ScriptPath `
                    -AssetNamePath 'unused' `
                    -EvidencePath 'unused' `
                    -RequiredAssetPath 'unused' `
                    -Channel PreRelease `
                    -Version '3.3.0' `
                    -ReleaseTag $script:ReleaseTag `
                    -SourceCommit $script:SourceCommit
            } | Should -Not -Throw
        }
    }
}

Describe 'Assert-ReleaseAssetSet reconciliation' -Tag 'Unit' {
    It 'Accepts a complete asset set' {
        Invoke-AssetSetTest -AssetName (New-AssetSet) | Should -BeNullOrEmpty
    }

    It 'Reports a missing VSIX asset' {
        $findings = Invoke-AssetSetTest -AssetName (New-AssetSet -Remove @('hve-alpha-3.3.0.vsix'))
        $findings | Should -Contain "missing VSIX asset 'hve-alpha-3.3.0.vsix'"
    }

    It 'Reports an unexpected VSIX asset' {
        $findings = Invoke-AssetSetTest -AssetName (New-AssetSet -Add @(
                'hve-gamma-3.3.0.vsix'
                'hve-gamma-3.3.0.vsix.spdx.json'
                'hve-gamma-3.3.0.vsix.sigstore.json'
                'hve-gamma-3.3.0.vsix.intoto.jsonl'
            ))
        $findings | Should -Contain "unexpected VSIX asset 'hve-gamma-3.3.0.vsix'"
    }

    It 'Reports a stale VSIX carrying the wrong release version' {
        # A leftover asset from an earlier attempt is an identity mismatch, not
        # an acceptable extra file.
        $findings = Invoke-AssetSetTest -AssetName (New-AssetSet -Add @('hve-alpha-3.1.0.vsix'))
        $findings | Should -Contain "unexpected VSIX asset 'hve-alpha-3.1.0.vsix'"
    }

    It 'Reports a duplicate asset name' {
        $findings = Invoke-AssetSetTest -AssetName (New-AssetSet -Add @('hve-alpha-3.3.0.vsix'))
        $findings | Should -Contain "duplicate asset 'hve-alpha-3.3.0.vsix' appears 2 times"
    }

    It 'Reports an incomplete <Sidecar> sidecar for VSIX asset <Primary>' -ForEach @(
        @{ Primary = 'hve-beta-3.3.0.vsix'; Sidecar = '.spdx.json' }
        @{ Primary = 'hve-beta-3.3.0.vsix'; Sidecar = '.sigstore.json' }
        @{ Primary = 'hve-beta-3.3.0.vsix'; Sidecar = '.intoto.jsonl' }
    ) {
        $findings = Invoke-AssetSetTest -AssetName (New-AssetSet -Remove @("$Primary$Sidecar"))
        $findings | Should -Be @("missing sidecar '$Primary$Sidecar' for VSIX asset '$Primary'")
    }

    It 'Reports a missing required singleton asset' {
        $findings = Invoke-AssetSetTest -AssetName (New-AssetSet -Remove @('dependencies.spdx.json'))
        $findings | Should -Contain "missing required asset 'dependencies.spdx.json'"
    }

    # Release asset names are ordinal identities, so a case variant is a
    # different asset rather than the expected one.
    It 'Treats a mixed-case VSIX asset as a distinct identity' {
        $findings = Invoke-AssetSetTest -AssetName (New-AssetSet -Remove @('hve-alpha-3.3.0.vsix') -Add @('HVE-Alpha-3.3.0.vsix'))
        $findings | Should -Contain "missing VSIX asset 'hve-alpha-3.3.0.vsix'"
        $findings | Should -Contain "unexpected VSIX asset 'HVE-Alpha-3.3.0.vsix'"
    }

    It 'Does not collapse two case-colliding assets into one duplicate' {
        $findings = Invoke-AssetSetTest -AssetName (New-AssetSet -Add @('Hve-alpha-3.3.0.vsix'))
        $findings | Should -Contain "unexpected VSIX asset 'Hve-alpha-3.3.0.vsix'"
        @($findings | Where-Object { $_ -like 'duplicate asset*' }) | Should -BeNullOrEmpty
    }

    It 'Treats a mixed-case required asset as absent' {
        $findings = Invoke-AssetSetTest -AssetName (New-AssetSet -Remove @('dependencies.spdx.json') -Add @('Dependencies.spdx.json'))
        $findings | Should -Be @("missing required asset 'dependencies.spdx.json'")
    }

    It 'Treats a mixed-case sidecar as absent' {
        $findings = Invoke-AssetSetTest -AssetName (New-AssetSet -Remove @('hve-alpha-3.3.0.vsix.spdx.json') -Add @('hve-alpha-3.3.0.vsix.SPDX.json'))
        $findings | Should -Be @("missing sidecar 'hve-alpha-3.3.0.vsix.spdx.json' for VSIX asset 'hve-alpha-3.3.0.vsix'")
    }

    It 'Rejects a release carrying only one expected VSIX' {
        # The superseded contract accepted any nonzero VSIX count.
        $partial = [string[]]@(
            'dependencies.spdx.json'
            'plugin-release-evidence.json'
            'hve-alpha-3.3.0.vsix'
            'hve-alpha-3.3.0.vsix.spdx.json'
            'hve-alpha-3.3.0.vsix.sigstore.json'
            'hve-alpha-3.3.0.vsix.intoto.jsonl'
        )
        $findings = Invoke-AssetSetTest -AssetName $partial
        $findings | Should -Contain "missing VSIX asset 'hve-beta-3.3.0.vsix'"
    }

    It 'Reports every finding rather than stopping at the first' {
        $findings = Invoke-AssetSetTest -AssetName (New-AssetSet -Remove @(
                'hve-beta-3.3.0.vsix'
                'hve-beta-3.3.0.vsix.spdx.json'
                'hve-beta-3.3.0.vsix.sigstore.json'
                'hve-beta-3.3.0.vsix.intoto.jsonl'
                'hve-alpha-3.3.0.vsix.spdx.json'
                'dependencies.spdx.json'
            ))
        @($findings).Count | Should -Be 3
    }

    It 'Does not echo sidecar findings for an absent primary asset' {
        $findings = Invoke-AssetSetTest -AssetName (New-AssetSet -Remove @(
                'hve-beta-3.3.0.vsix'
                'hve-beta-3.3.0.vsix.spdx.json'
                'hve-beta-3.3.0.vsix.sigstore.json'
                'hve-beta-3.3.0.vsix.intoto.jsonl'
            ))
        $findings | Should -Be @("missing VSIX asset 'hve-beta-3.3.0.vsix'")
    }
}

Describe 'Assert-ReleaseAssetSet end to end' -Tag 'Unit' {
    BeforeAll {
        $script:EvidenceFile = Join-Path $TestDrive 'e2e-evidence.json'
        New-EvidenceDocument | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:EvidenceFile -Encoding utf8

        $script:PartialEvidenceFile = Join-Path $TestDrive 'e2e-partial-evidence.json'
        New-EvidenceDocument -PackageName @('alpha') | ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath $script:PartialEvidenceFile -Encoding utf8

        $script:RequiredFile = Join-Path $TestDrive 'e2e-required.txt'
        Set-Content -LiteralPath $script:RequiredFile -Encoding utf8 -Value @(
            'dependencies.spdx.json'
            'plugin-release-evidence.json'
            ''
        )

        function Invoke-AssertOverFile {
            <#
            .SYNOPSIS
            Runs the orchestrator over a written asset list.
            .PARAMETER AssetName
            Actual release asset names.
            .PARAMETER EvidencePath
            Evidence document to reconcile. Defaults to the complete fixture.
            .PARAMETER Version
            Released version. Defaults to the fixture version.
            .OUTPUTS
            [pscustomobject] The verified identities.
            #>
            [CmdletBinding()]
            [OutputType([pscustomobject])]
            param(
                [Parameter(Mandatory = $true)]
                [AllowEmptyCollection()]
                [string[]]$AssetName,

                [Parameter(Mandatory = $false)]
                [string]$EvidencePath = $script:EvidenceFile,

                [Parameter(Mandatory = $false)]
                [string]$Version = '3.3.0'
            )

            $listPath = Join-Path $TestDrive "assets-$([guid]::NewGuid().ToString('n')).txt"
            Set-Content -LiteralPath $listPath -Encoding utf8 -Value ([string[]]@($AssetName))
            return Assert-ReleaseAssetSet -AssetNamePath $listPath `
                -EvidencePath $EvidencePath `
                -RequiredAssetPath $script:RequiredFile `
                -Channel PreRelease `
                -Version $Version `
                -ReleaseTag $script:ReleaseTag `
                -SourceCommit $script:SourceCommit `
                -CatalogPath $script:FixtureCatalog
        }
    }

    It 'Reports the verified identities for a complete published release' {
        $result = Invoke-AssertOverFile -AssetName (New-AssetSet)
        $result.EvidencePackage | Should -Be @('alpha', 'beta')
        $result.Vsix | Should -Be $script:ExpectedVsix
        $result.ReleaseTag | Should -BeExactly $script:ReleaseTag
    }

    It 'Fails an incomplete published release with a finding count' {
        { Invoke-AssertOverFile -AssetName (New-AssetSet -Remove @(
                    'hve-beta-3.3.0.vsix'
                    'hve-beta-3.3.0.vsix.spdx.json'
                    'hve-beta-3.3.0.vsix.sigstore.json'
                    'hve-beta-3.3.0.vsix.intoto.jsonl'
                )) } |
            Should -Throw '*has incomplete release assets: 1 findings*'
    }

    # The verified release is complete under its own evidence, so only the
    # released catalog can expose the shortened package list.
    It 'Fails a self-consistent release whose evidence omits a catalog package' {
        { Invoke-AssertOverFile -AssetName (New-AssetSet) -EvidencePath $script:PartialEvidenceFile } |
            Should -Throw '*omits released catalog package(s): beta*'
    }

    It 'Rejects a version that is not MAJOR.MINOR.PATCH' {
        { Invoke-AssertOverFile -AssetName (New-AssetSet) -Version '3.3' } |
            Should -Throw '*does not match the*'
    }

    It 'Fails a release carrying no assets' {
        $listPath = Join-Path $TestDrive 'empty-assets.txt'
        Set-Content -LiteralPath $listPath -Encoding utf8 -Value "`n   `n"
        {
            Assert-ReleaseAssetSet -AssetNamePath $listPath `
                -EvidencePath $script:EvidenceFile `
                -RequiredAssetPath $script:RequiredFile `
                -Channel PreRelease `
                -Version '3.3.0' `
                -ReleaseTag $script:ReleaseTag `
                -SourceCommit $script:SourceCommit `
                -CatalogPath $script:FixtureCatalog
        } | Should -Throw '*carries no release assets*'
    }

    It 'Fails when the evidence document is absent' {
        $listPath = Join-Path $TestDrive 'absent-evidence-assets.txt'
        Set-Content -LiteralPath $listPath -Encoding utf8 -Value (New-AssetSet)
        {
            Assert-ReleaseAssetSet -AssetNamePath $listPath `
                -EvidencePath (Join-Path $TestDrive 'missing-evidence.json') `
                -RequiredAssetPath $script:RequiredFile `
                -Channel PreRelease `
                -Version '3.3.0' `
                -ReleaseTag $script:ReleaseTag `
                -SourceCommit $script:SourceCommit `
                -CatalogPath $script:FixtureCatalog
        } | Should -Throw '*carries no readable plugin-release-evidence.json*'
    }
}
