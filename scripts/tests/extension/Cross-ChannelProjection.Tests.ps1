#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

BeforeAll {
    # MarketplaceHelpers reloads its nested ArtifactHelpers dependency, so shared
    # modules load before the script whose own imports settle the session state.
    Import-Module (Join-Path $PSScriptRoot '../../lib/Modules/MarketplaceHelpers.psm1') -Force
    . (Join-Path $PSScriptRoot '../../extension/Prepare-Extension.ps1')

    $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
    $script:Catalog = Get-MarketplaceCatalog -Path (Join-Path $script:RepositoryRoot '.github/plugin/marketplace.json')
    $script:AgentIndex = Get-MarketplaceAgentIndex -Catalog $script:Catalog -RepoRoot $script:RepositoryRoot
    $script:Channels = @('Stable', 'PreRelease')

    function Get-ExtensionCanonicalSource {
        <#
        .SYNOPSIS
        Reduces VS Code contributions back to canonical repository source paths.
        .PARAMETER Contribution
        Contribution buckets produced by Get-ExtensionContributions.
        .OUTPUTS
        [string[]] Sorted canonical source paths.
        #>
        [CmdletBinding()]
        [OutputType([string[]])]
        param(
            [Parameter(Mandatory = $true)]
            [hashtable]$Contribution
        )

        $sources = @()
        foreach ($bucket in @('Agents', 'Prompts', 'Instructions')) {
            $sources += @($Contribution[$bucket] | ForEach-Object { [string]$_.path })
        }
        $sources += @($Contribution['Skills'] | ForEach-Object { [string]$_.path -replace '/SKILL\.md$', '' })
        $normalized = [string[]]@(
            $sources | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                ForEach-Object { $_ -replace '^\./', '' } | Sort-Object -Unique
        )
        return $normalized
    }

    $script:Projections = @()
    foreach ($channel in $script:Channels) {
        foreach ($entry in @($script:Catalog['plugins'])) {
            if (-not (Test-MarketplaceEntryEligible -Entry $entry -Channel $channel)) { continue }
            $recipe = @(Get-MarketplaceResolvedPackageRecipe -Entry $entry -Channel $channel -AgentIndex $script:AgentIndex)
            $declaredAgents = @(Get-MarketplacePackageRecipe -Entry $entry -Channel $channel |
                    Where-Object { $_.Kind -eq 'agent' } | ForEach-Object { $_.PackagePath })
            $resolvedAgents = @($recipe | Where-Object { $_.Kind -eq 'agent' } | ForEach-Object { $_.PackagePath })
            $script:Projections += @{
                Channel        = $channel
                PackageName    = [string]$entry['name']
                Entry          = $entry
                Recipe         = $recipe
                HookSources    = @($recipe | Where-Object { $_.Kind -eq 'hook' } | ForEach-Object { $_.SourcePath })
                PluginSources  = [string[]]@($recipe | ForEach-Object { $_.SourcePath } | Sort-Object -Unique)
                NonHookSources = [string[]]@($recipe | Where-Object { $_.Kind -ne 'hook' } | ForEach-Object { $_.SourcePath } | Sort-Object -Unique)
                ClosureAdded   = [string[]]@($resolvedAgents | Where-Object { $_ -notin $declaredAgents } | Sort-Object)
            }
        }
    }
}

Describe 'Cross-channel canonical projection' -Tag 'Unit' {
    It 'Projects at least one eligible package per channel' {
        foreach ($channel in $script:Channels) {
            @($script:Projections | Where-Object { $_.Channel -eq $channel }).Count |
                Should -BeGreaterThan 0 -Because "$channel must produce comparable packages"
        }
    }

    It 'Shares canonical sources between the plugin recipe and the VS Code contributions' {
        $compared = 0
        foreach ($projection in $script:Projections) {
            $contributions = Get-ExtensionContributions -Items $projection.Recipe
            $extensionSources = Get-ExtensionCanonicalSource -Contribution $contributions
            ($extensionSources -join "`n") | Should -Be ($projection.NonHookSources -join "`n") `
                -Because "$($projection.Channel)/$($projection.PackageName) must share canonical sources"
            $compared++
        }
        $compared | Should -Be @($script:Projections).Count
    }

    It 'Derives every contribution path from its canonical source path' {
        foreach ($projection in $script:Projections) {
            $contributions = Get-ExtensionContributions -Items $projection.Recipe
            foreach ($item in $projection.Recipe) {
                switch ($item.Kind) {
                    'agent' { @($contributions.Agents.path) | Should -Contain "./$($item.SourcePath)" }
                    'prompt' { @($contributions.Prompts.path) | Should -Contain "./$($item.SourcePath)" }
                    'instruction' { @($contributions.Instructions.path) | Should -Contain "./$($item.SourcePath)" }
                    'skill' { @($contributions.Skills.path) | Should -Contain "./$($item.SourcePath)/SKILL.md" }
                }
            }
        }
    }

    It 'Resolves every canonical source to a file on disk' {
        foreach ($projection in $script:Projections) {
            foreach ($source in $projection.NonHookSources) {
                Test-Path -LiteralPath (Join-Path $script:RepositoryRoot $source) |
                    Should -BeTrue -Because "$($projection.PackageName) declares $source"
            }
        }
    }
}

Describe 'Cross-channel hook exclusion' -Tag 'Unit' {
    BeforeAll {
        $script:HookProjections = @($script:Projections | Where-Object { @($_.HookSources).Count -gt 0 })
    }

    It 'Resolves a non-empty hook component set before asserting the exclusion' {
        @($script:HookProjections).Count | Should -BeGreaterThan 0
        @($script:HookProjections | ForEach-Object { $_.HookSources } | Sort-Object -Unique).Count | Should -BeGreaterThan 0
    }

    It 'Keeps hooks out of every VS Code contribution bucket' {
        foreach ($projection in $script:HookProjections) {
            $contributions = Get-ExtensionContributions -Items $projection.Recipe
            $extensionSources = Get-ExtensionCanonicalSource -Contribution $contributions
            foreach ($hookSource in $projection.HookSources) {
                $extensionSources | Should -Not -Contain $hookSource
            }
        }
    }

    It 'Keeps hook sources under the hooks root only' {
        foreach ($projection in $script:HookProjections) {
            foreach ($hookSource in $projection.HookSources) {
                $hookSource | Should -BeLike '.github/hooks/*'
            }
        }
    }
}

Describe 'Cross-channel handoff closure' -Tag 'Unit' {
    BeforeAll {
        $script:ClosureProjections = @($script:Projections | Where-Object { @($_.ClosureAdded).Count -gt 0 })
    }

    It 'Produces a non-empty closure delta set before asserting its content' {
        @($script:ClosureProjections).Count | Should -BeGreaterThan 0
    }

    It 'Adds only catalog-declared agents through the closure' {
        $catalogAgents = @($script:Catalog['plugins'] | ForEach-Object { @($_['agents']) } | Where-Object { $_ } | Sort-Object -Unique)
        @($catalogAgents).Count | Should -BeGreaterThan 0
        foreach ($projection in $script:ClosureProjections) {
            foreach ($added in $projection.ClosureAdded) {
                $catalogAgents | Should -Contain $added -Because "$($projection.PackageName) closure added $added"
            }
        }
    }

    It 'Includes every closure addition in the resolved recipe and its VS Code contributions' {
        foreach ($projection in $script:ClosureProjections) {
            $contributions = Get-ExtensionContributions -Items $projection.Recipe
            foreach ($added in $projection.ClosureAdded) {
                $component = Resolve-MarketplaceComponentSource -PackagePath $added -Field 'agents'
                @($projection.Recipe | ForEach-Object { $_.SourcePath }) | Should -Contain $component.SourcePath
                @($contributions.Agents.path) | Should -Contain "./$($component.SourcePath)"
                Test-Path -LiteralPath (Join-Path $script:RepositoryRoot $component.SourcePath) -PathType Leaf | Should -BeTrue
            }
        }
    }

    It 'Never removes a declared agent from the resolved recipe' {
        foreach ($projection in $script:Projections) {
            $declared = @(Get-MarketplacePackageRecipe -Entry $projection.Entry -Channel $projection.Channel |
                    Where-Object { $_.Kind -eq 'agent' } | ForEach-Object { $_.PackagePath })
            $resolved = @($projection.Recipe | Where-Object { $_.Kind -eq 'agent' } | ForEach-Object { $_.PackagePath })
            foreach ($agent in $declared) { $resolved | Should -Contain $agent }
        }
    }
}
