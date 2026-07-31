#Requires -Modules Pester
# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT

# Transitional YAML-to-JSON parity gate.
#
# Collection YAML is frozen but still present, so this suite reads both the
# retiring recipes and the marketplace catalog and proves they describe the same
# packages. Every difference must appear in the classified delta table below; an
# unexplained difference fails. The suite is deleted together with the YAML
# inputs, so it is the only place a legacy reader remains outside test scope.

BeforeDiscovery {
    $script:parityRepoRoot = (Resolve-Path "$PSScriptRoot/../../..").Path
    $script:parityCollectionsDir = Join-Path $script:parityRepoRoot 'collections'
    $script:parityPackageNames = @(
        Get-ChildItem -Path $script:parityCollectionsDir -Filter '*.collection.yml' -File |
            Sort-Object Name |
            ForEach-Object { $_.BaseName -replace '\.collection$', '' }
    )
    $script:parityChannels = @('Stable', 'PreRelease')
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../plugins/Modules/PluginHelpers.psm1') -Force
    Import-Module PowerShell-Yaml -Force

    $script:repoRoot = (Resolve-Path "$PSScriptRoot/../../..").Path
    $script:collectionsDir = Join-Path $script:repoRoot 'collections'
    $script:packageNames = @(
        Get-ChildItem -Path $script:collectionsDir -Filter '*.collection.yml' -File |
            Sort-Object Name |
            ForEach-Object { $_.BaseName -replace '\.collection$', '' }
    )
    $script:catalog = Get-MarketplaceCatalog -Path (Join-Path $script:repoRoot '.github/plugin/marketplace.json')
    $script:agentIndex = Get-MarketplaceAgentIndex -Catalog $script:catalog -RepoRoot $script:repoRoot

    # Classified deltas. Anything outside this table fails the gate.
    #
    # DependencyClosure: agents reached through a declared handoff that the YAML
    # recipe never listed. Handoff targets bypass maturity filtering by design,
    # so a Stable package can gain an agent whose own maturity is not stable.
    $script:expectedDeltas = @{
        'Stable|hve-core-all'      = @{
            JsonOnly   = @(
                'agent|.github/agents/rai-planning/rai-planner.agent.md',
                'agent|.github/agents/security/security-planner.agent.md',
                'agent|.github/agents/security/sssc-planner.agent.md'
            )
            LegacyOnly = @()
        }
        'Stable|project-planning'  = @{
            JsonOnly   = @(
                'agent|.github/agents/rai-planning/rai-planner.agent.md',
                'agent|.github/agents/security/security-planner.agent.md',
                'agent|.github/agents/security/sssc-planner.agent.md'
            )
            LegacyOnly = @()
        }
        'PreRelease|data-science'  = @{
            JsonOnly   = @(
                'agent|.github/agents/security/security-planner.agent.md',
                'agent|.github/agents/security/sssc-planner.agent.md'
            )
            LegacyOnly = @()
        }
    }

    function Get-LegacyRecipe {
        param(
            [Parameter(Mandatory = $true)][string]$PackageName,
            [Parameter(Mandatory = $true)][string]$Channel
        )

        $manifest = ConvertFrom-Yaml -Yaml (Get-Content (Join-Path $script:collectionsDir "$PackageName.collection.yml") -Raw)
        $allowed = if ($Channel -eq 'Stable') { @('stable') } else { @('stable', 'preview', 'experimental') }
        $roots = Get-MarketplaceComponentSourceRoot
        $members = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

        foreach ($item in $manifest.items) {
            $kind = [string]$item.kind
            $path = [string]$item.path
            $maturity = if ($item.ContainsKey('maturity') -and $item.maturity) { [string]$item.maturity } else { 'stable' }
            if ($allowed -notcontains $maturity) { continue }

            $expectedRoot = "$($roots[(Get-MarketplaceComponentField -Kind $kind)].SourceRoot)/"
            if (-not $path.StartsWith($expectedRoot)) {
                [void]$members.Add("OFFROOT|$kind|$path")
                continue
            }
            [void]$members.Add("$kind|$path")
        }

        return @{
            Members     = $members
            Description = [string]$manifest.description
            Tags        = @($manifest.tags | ForEach-Object { [string]$_ })
            Maturity    = if ($manifest.ContainsKey('maturity') -and $manifest.maturity) { [string]$manifest.maturity } else { 'stable' }
        }
    }

    function Get-CatalogRecipe {
        param(
            [Parameter(Mandatory = $true)][string]$PackageName,
            [Parameter(Mandatory = $true)][string]$Channel
        )

        $entry = @($script:catalog.plugins | Where-Object { $_.name -eq $PackageName })[0]
        $items = @(Get-MarketplacePackageRecipe -Entry $entry -Channel $Channel)
        $seeds = @($items | Where-Object { $_.Kind -eq 'agent' } | ForEach-Object { $_.PackagePath })
        $closed = @(Expand-MarketplaceAgentDependency -Index $script:agentIndex -SeedPackagePaths $seeds -PackageName $PackageName)

        $members = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($item in $items) { [void]$members.Add("$($item.Kind)|$($item.SourcePath)") }
        foreach ($agentPath in $closed) {
            $component = Resolve-MarketplaceComponentSource -PackagePath $agentPath -Field 'agents'
            [void]$members.Add("agent|$($component.SourcePath)")
        }

        return @{
            Entry         = $entry
            Members       = $members
            Description   = [string]$entry.description
            Keywords      = @($entry.keywords | ForEach-Object { [string]$_ })
            Maturity      = Get-MarketplaceEntryMaturity -Entry $entry
            Documentation = Get-MarketplaceEntryOverlayValue -Entry $entry -Key 'documentation'
        }
    }
}

Describe 'YAML-to-JSON catalog parity' {
    It 'Declares every legacy package exactly once in the catalog' {
        $catalogNames = @($script:catalog.plugins | ForEach-Object { $_.name })
        foreach ($name in $script:packageNames) {
            @($catalogNames | Where-Object { $_ -eq $name }).Count | Should -Be 1 -Because "package '$name' must have exactly one catalog entry"
        }
    }

    It 'Declares no packages beyond the legacy set' {
        $catalogNames = @($script:catalog.plugins | ForEach-Object { $_.name })
        $extra = @($catalogNames | Where-Object { $_ -notin $script:packageNames })
        $extra | Should -BeNullOrEmpty
        $catalogNames | Should -HaveCount 14
    }

    It 'Marks hve-core-all as the aggregate package' {
        $entry = @($script:catalog.plugins | Where-Object { $_.name -eq 'hve-core-all' })[0]
        Get-MarketplaceEntryOverlayValue -Entry $entry -Key 'aggregate' | Should -BeTrue
    }

    It 'Preserves identity, tags, maturity, and documentation for <_>' -ForEach $script:parityPackageNames {
        $legacy = Get-LegacyRecipe -PackageName $_ -Channel 'PreRelease'
        $catalog = Get-CatalogRecipe -PackageName $_ -Channel 'PreRelease'

        $catalog.Description | Should -Be $legacy.Description
        $catalog.Keywords | Should -Be $legacy.Tags
        $catalog.Maturity | Should -Be $legacy.Maturity
        $catalog.Documentation | Should -Be "docs/plugins/$_.md"
        Test-Path (Join-Path $script:repoRoot $catalog.Documentation) | Should -BeTrue
    }

    It 'Declares provenance for every catalog entry' {
        foreach ($entry in $script:catalog.plugins) {
            foreach ($field in @('author', 'homepage', 'repository', 'license', 'keywords')) {
                $entry.Contains($field) | Should -BeTrue -Because "entry '$($entry.name)' must declare $field"
            }
            $entry.author | Should -BeOfType [System.Collections.IDictionary]
            $entry.author.name | Should -Be 'Microsoft'
        }
    }
}

Describe 'YAML-to-JSON membership parity' {
    It 'Matches membership for <channel> / <package> except classified deltas' -ForEach @(
        foreach ($channel in @('Stable', 'PreRelease')) {
            foreach ($package in $script:parityPackageNames) {
                @{ channel = $channel; package = $package }
            }
        }
    ) {
        $legacy = Get-LegacyRecipe -PackageName $package -Channel $channel
        $catalog = Get-CatalogRecipe -PackageName $package -Channel $channel

        $legacyOnly = @($legacy.Members | Where-Object { -not $catalog.Members.Contains($_) } | Sort-Object)
        $jsonOnly = @($catalog.Members | Where-Object { -not $legacy.Members.Contains($_) } | Sort-Object)

        $key = "$channel|$package"
        $expected = if ($script:expectedDeltas.ContainsKey($key)) {
            $script:expectedDeltas[$key]
        }
        else {
            @{ JsonOnly = @(); LegacyOnly = @() }
        }

        $legacyOnly | Should -Be @($expected.LegacyOnly | Sort-Object) -Because "legacy-only members for $key must be classified"
        $jsonOnly | Should -Be @($expected.JsonOnly | Sort-Object) -Because "catalog-only members for $key must be classified"
    }
}

Describe 'Dependency closure deltas' {
    It 'Resolves the ADR Creation handoff to its declared canonical agent' {
        $key = ConvertTo-MarketplaceAgentKey -Name 'ADR Creation'
        $script:agentIndex.Ambiguous.ContainsKey($key) | Should -BeFalse
        $script:agentIndex.Lookup[$key].SourcePath | Should -Be '.github/agents/project-planning/adr-creation.agent.md'
    }

    It 'Resolves every declared handoff across the whole catalog' {
        foreach ($entry in $script:catalog.plugins) {
            if (-not $entry.Contains('agents')) { continue }
            { Expand-MarketplaceAgentDependency -Index $script:agentIndex `
                    -SeedPackagePaths @($entry.agents) -PackageName $entry.name } | Should -Not -Throw
        }
    }

    It 'Records a dependency-closure addition only where classified' {
        $observed = @{}
        foreach ($channel in @('Stable', 'PreRelease')) {
            foreach ($package in $script:packageNames) {
                $legacy = Get-LegacyRecipe -PackageName $package -Channel $channel
                $catalog = Get-CatalogRecipe -PackageName $package -Channel $channel
                $additions = @($catalog.Members | Where-Object { -not $legacy.Members.Contains($_) })
                if ($additions.Count -gt 0) {
                    $observed["$channel|$package"] = $additions.Count
                }
            }
        }

        @($observed.Keys | Sort-Object) | Should -Be @(
            'PreRelease|data-science',
            'Stable|hve-core-all',
            'Stable|project-planning'
        )
    }
}
