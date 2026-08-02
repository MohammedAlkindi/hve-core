#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../lib/Modules/MarketplaceHelpers.psm1') -Force

    function New-TestAgentFile {
        param(
            [Parameter(Mandatory)][string]$RepoRoot,
            [Parameter(Mandatory)][string]$SourcePath,
            [Parameter(Mandatory)][string]$DisplayName,
            [Parameter()][string[]]$Handoffs = @(),
            [Parameter()][switch]$UseObjectHandoffs
        )

        $absolutePath = Join-Path $RepoRoot $SourcePath
        New-Item -ItemType Directory -Path (Split-Path -Path $absolutePath -Parent) -Force | Out-Null

        $lines = @('---', "name: $DisplayName")
        if ($Handoffs.Count -gt 0) {
            $lines += 'handoffs:'
            foreach ($target in $Handoffs) {
                $lines += if ($UseObjectHandoffs) { "  - agent: $target" } else { "  - $target" }
            }
        }
        $lines += @('---', '', '# Body')
        Set-Content -LiteralPath $absolutePath -Value (($lines -join "`n") + "`n") -NoNewline
    }
}

Describe 'ConvertTo-MarketplaceAgentKey' -Tag 'Unit' {
    It 'Normalizes <Name> to <Expected>' -ForEach @(
        @{ Name = 'Alpha Agent'; Expected = 'alpha-agent' }
        @{ Name = 'alpha-agent'; Expected = 'alpha-agent' }
        @{ Name = '  Code Review  '; Expected = 'code-review' }
        @{ Name = 'RPI: Plan/Implement'; Expected = 'rpi-plan-implement' }
        @{ Name = '__underscore__'; Expected = 'underscore' }
        @{ Name = 'ABC123'; Expected = 'abc123' }
        @{ Name = '---'; Expected = '' }
        @{ Name = ''; Expected = '' }
    ) {
        ConvertTo-MarketplaceAgentKey -Name $Name | Should -BeExactly $Expected
    }

    It 'Maps a file stem and its display name onto the same key' {
        $stemKey = ConvertTo-MarketplaceAgentKey -Name 'code-review'
        $displayKey = ConvertTo-MarketplaceAgentKey -Name 'Code Review'
        $stemKey | Should -BeExactly $displayKey
    }
}

Describe 'Marketplace agent index and handoff closure' -Tag 'Unit' {
    BeforeAll {
        $script:ClosureRoot = Join-Path $TestDrive 'closure-repo'

        New-TestAgentFile -RepoRoot $script:ClosureRoot -SourcePath '.github/agents/demo/alpha.agent.md' -DisplayName 'Alpha Agent' -Handoffs @('Bravo Agent')
        New-TestAgentFile -RepoRoot $script:ClosureRoot -SourcePath '.github/agents/demo/bravo.agent.md' -DisplayName 'Bravo Agent' -Handoffs @('charlie') -UseObjectHandoffs
        New-TestAgentFile -RepoRoot $script:ClosureRoot -SourcePath '.github/agents/demo/charlie.agent.md' -DisplayName 'Charlie Agent' -Handoffs @('delta')
        New-TestAgentFile -RepoRoot $script:ClosureRoot -SourcePath '.github/agents/demo/delta.agent.md' -DisplayName 'Delta Agent'
        New-TestAgentFile -RepoRoot $script:ClosureRoot -SourcePath '.github/agents/demo/echo.agent.md' -DisplayName 'Echo Agent' -Handoffs @('Delta Agent')
        New-TestAgentFile -RepoRoot $script:ClosureRoot -SourcePath '.github/agents/cycle/loop-one.agent.md' -DisplayName 'Loop One' -Handoffs @('loop-two')
        New-TestAgentFile -RepoRoot $script:ClosureRoot -SourcePath '.github/agents/cycle/loop-two.agent.md' -DisplayName 'Loop Two' -Handoffs @('loop-one')
        New-TestAgentFile -RepoRoot $script:ClosureRoot -SourcePath '.github/agents/cycle/mirror.agent.md' -DisplayName 'Mirror' -Handoffs @('mirror')
        New-TestAgentFile -RepoRoot $script:ClosureRoot -SourcePath '.github/agents/broken/orphan.agent.md' -DisplayName 'Orphan' -Handoffs @('Nonexistent Agent')
        New-TestAgentFile -RepoRoot $script:ClosureRoot -SourcePath '.github/agents/one/shared.agent.md' -DisplayName 'One Shared'
        New-TestAgentFile -RepoRoot $script:ClosureRoot -SourcePath '.github/agents/one/requester.agent.md' -DisplayName 'Requester' -Handoffs @('Shared')
        New-TestAgentFile -RepoRoot $script:ClosureRoot -SourcePath '.github/agents/two/other.agent.md' -DisplayName 'Shared'

        $script:ClosureCatalog = @{
            plugins = @(
                @{ name = 'chain'; agents = @('agents/demo/alpha.md', 'agents/demo/bravo.md', 'agents/demo/charlie.md', 'agents/demo/delta.md', 'agents/demo/echo.md') }
                @{ name = 'cycles'; agents = @('agents/cycle/loop-one.md', 'agents/cycle/loop-two.md', 'agents/cycle/mirror.md') }
                @{ name = 'broken'; agents = @('agents/broken/orphan.md') }
                @{ name = 'ambiguous'; agents = @('agents/one/shared.md', 'agents/one/requester.md', 'agents/two/other.md') }
            )
        }
        $script:ClosureIndex = Get-MarketplaceAgentIndex -Catalog $script:ClosureCatalog -RepoRoot $script:ClosureRoot
    }

    Context 'when the index is built' {
        It 'Indexes every declared agent under its file stem' {
            foreach ($stem in @('alpha', 'bravo', 'charlie', 'delta', 'echo', 'loop-one', 'loop-two', 'mirror', 'orphan', 'shared', 'requester', 'other')) {
                $script:ClosureIndex.Lookup.ContainsKey($stem) | Should -BeTrue -Because "'$stem' is a declared agent file stem"
            }
        }

        It 'Indexes agents under their frontmatter display name as well' {
            $script:ClosureIndex.Lookup['alpha-agent'].SourcePath | Should -BeExactly '.github/agents/demo/alpha.agent.md'
            $script:ClosureIndex.Lookup['delta-agent'].SourcePath | Should -BeExactly '.github/agents/demo/delta.agent.md'
            $script:ClosureIndex.Lookup['one-shared'].SourcePath | Should -BeExactly '.github/agents/one/shared.agent.md'
        }

        It 'Records both the package path and the source path for each agent' {
            $script:ClosureIndex.Lookup['alpha'].PackagePath | Should -BeExactly 'agents/demo/alpha.md'
            $script:ClosureIndex.Lookup['alpha'].SourcePath | Should -BeExactly '.github/agents/demo/alpha.agent.md'
        }

        It 'Reads string handoff targets' {
            $handoffs = @($script:ClosureIndex.Lookup['alpha'].Handoffs)
            $handoffs.Count | Should -Be 1
            $handoffs[0] | Should -BeExactly 'Bravo Agent'
        }

        It 'Reads object handoff targets' {
            $handoffs = @($script:ClosureIndex.Lookup['bravo'].Handoffs)
            $handoffs.Count | Should -Be 1
            $handoffs[0] | Should -BeExactly 'charlie'
        }

        It 'Records an empty handoff list for a terminal agent' {
            @($script:ClosureIndex.Lookup['delta'].Handoffs).Count | Should -Be 0
        }

        It 'Records exactly one ambiguous key' {
            @($script:ClosureIndex.Ambiguous.Keys).Count | Should -Be 1
            $script:ClosureIndex.Ambiguous.ContainsKey('shared') | Should -BeTrue
        }

        It 'Lists every source that competes for the ambiguous key' {
            (@($script:ClosureIndex.Ambiguous['shared']) -join ', ') |
                Should -BeExactly '.github/agents/one/shared.agent.md, .github/agents/two/other.agent.md'
        }
    }

    Context 'when a declared agent source is missing' {
        BeforeAll {
            $script:GhostCatalog = @{ plugins = @(@{ name = 'ghost'; agents = @('agents/ghost/missing.md') }) }
            $script:GhostIndex = Get-MarketplaceAgentIndex -Catalog $script:GhostCatalog -RepoRoot $script:ClosureRoot -WarningVariable capturedWarnings -WarningAction SilentlyContinue
            $script:GhostWarnings = @($capturedWarnings)
        }

        It 'Warns about the missing source' {
            $script:GhostWarnings | Should -Not -BeNullOrEmpty
            $script:GhostWarnings[0].Message | Should -BeExactly 'Declared agent source not found: .github/agents/ghost/missing.agent.md'
        }

        It 'Still indexes the agent with no handoffs' {
            $script:GhostIndex.Lookup.ContainsKey('missing') | Should -BeTrue
            @($script:GhostIndex.Lookup['missing'].Handoffs).Count | Should -Be 0
        }
    }

    Context 'when agent frontmatter cannot be parsed' {
        BeforeAll {
            $script:MalformedRoot = Join-Path $TestDrive 'malformed-repo'
            $malformedPath = Join-Path $script:MalformedRoot '.github/agents/demo/broken.agent.md'
            New-Item -ItemType Directory -Path (Split-Path -Path $malformedPath -Parent) -Force | Out-Null
            Set-Content -LiteralPath $malformedPath -Value "---`nname: Broken`n  bad: indentation`n---`n" -NoNewline

            $script:MalformedCatalog = @{ plugins = @(@{ name = 'malformed'; agents = @('agents/demo/broken.md') }) }
            $script:MalformedIndex = Get-MarketplaceAgentIndex -Catalog $script:MalformedCatalog -RepoRoot $script:MalformedRoot -WarningVariable capturedWarnings -WarningAction SilentlyContinue
            $script:MalformedWarnings = @($capturedWarnings)
        }

        It 'Warns and names the source path' {
            $script:MalformedWarnings | Should -Not -BeNullOrEmpty
            $script:MalformedWarnings[0].Message | Should -BeLike 'Failed to parse frontmatter from .github/agents/demo/broken.agent.md*'
        }

        It 'Falls back to the file stem key with no handoffs' {
            $script:MalformedIndex.Lookup.ContainsKey('broken') | Should -BeTrue
            @($script:MalformedIndex.Lookup['broken'].Handoffs).Count | Should -Be 0
        }
    }

    Context 'when transitive dependencies are closed' {
        It 'Follows a three-hop handoff chain to its terminal agent' {
            $closed = @(Expand-MarketplaceAgentDependency -Index $script:ClosureIndex -SeedPackagePaths @('agents/demo/alpha.md') -PackageName 'chain')
            $closed.Count | Should -Be 4
            ($closed -join '|') | Should -BeExactly 'agents/demo/alpha.md|agents/demo/bravo.md|agents/demo/charlie.md|agents/demo/delta.md'
        }

        It 'Collapses a target reached from two independent seeds' {
            $closed = @(Expand-MarketplaceAgentDependency -Index $script:ClosureIndex -SeedPackagePaths @('agents/demo/alpha.md', 'agents/demo/echo.md') -PackageName 'chain')
            $closed.Count | Should -Be 5
            @($closed | Where-Object { $_ -eq 'agents/demo/delta.md' }).Count | Should -Be 1
        }

        It 'Terminates on a two-agent cycle' {
            $closed = @(Expand-MarketplaceAgentDependency -Index $script:ClosureIndex -SeedPackagePaths @('agents/cycle/loop-one.md') -PackageName 'cycles')
            $closed.Count | Should -Be 2
            ($closed -join '|') | Should -BeExactly 'agents/cycle/loop-one.md|agents/cycle/loop-two.md'
        }

        It 'Terminates on a self-referencing agent' {
            $closed = @(Expand-MarketplaceAgentDependency -Index $script:ClosureIndex -SeedPackagePaths @('agents/cycle/mirror.md') -PackageName 'cycles')
            $closed.Count | Should -Be 1
            $closed[0] | Should -BeExactly 'agents/cycle/mirror.md'
        }

        It 'Returns nothing for an empty seed set' {
            @(Expand-MarketplaceAgentDependency -Index $script:ClosureIndex -SeedPackagePaths @() -PackageName 'chain').Count |
                Should -Be 0
        }

        It 'Returns package paths in sorted order' {
            $closed = @(Expand-MarketplaceAgentDependency -Index $script:ClosureIndex -SeedPackagePaths @('agents/demo/echo.md', 'agents/demo/alpha.md') -PackageName 'chain')
            ($closed -join '|') | Should -BeExactly (($closed | Sort-Object) -join '|')
        }
    }

    Context 'when closure cannot be resolved' {
        It 'Rejects a seed that is absent from the index' {
            { Expand-MarketplaceAgentDependency -Index $script:ClosureIndex -SeedPackagePaths @('agents/demo/absent.md') -PackageName 'chain' } |
                Should -Throw -ExpectedMessage "Package 'chain' declares agent 'agents/demo/absent.md', which is absent from the catalog agent index."
        }

        It 'Names the package as unknown when none is supplied' {
            { Expand-MarketplaceAgentDependency -Index $script:ClosureIndex -SeedPackagePaths @('agents/demo/absent.md') } |
                Should -Throw -ExpectedMessage "Package 'unknown' declares agent 'agents/demo/absent.md', which is absent from the catalog agent index."
        }

        It 'Rejects a handoff target that resolves to no catalog agent' {
            { Expand-MarketplaceAgentDependency -Index $script:ClosureIndex -SeedPackagePaths @('agents/broken/orphan.md') -PackageName 'broken' } |
                Should -Throw -ExpectedMessage "Package 'broken': handoff target 'Nonexistent Agent' in '.github/agents/broken/orphan.agent.md' does not resolve to a catalog-declared agent."
        }

        It 'Rejects a handoff target whose key is ambiguous' {
            { Expand-MarketplaceAgentDependency -Index $script:ClosureIndex -SeedPackagePaths @('agents/one/requester.md') -PackageName 'ambiguous' } |
                Should -Throw -ExpectedMessage "Package 'ambiguous': handoff target 'Shared' in '.github/agents/one/requester.agent.md' is ambiguous across .github/agents/one/shared.agent.md, .github/agents/two/other.agent.md."
        }
    }

    Context 'when an ambiguous key is never requested' {
        It 'Confirms the index really does carry an ambiguous key' {
            @($script:ClosureIndex.Ambiguous.Keys).Count | Should -BeGreaterThan 0
        }

        It 'Closes a package that never reaches the ambiguous key' {
            $closed = @(Expand-MarketplaceAgentDependency -Index $script:ClosureIndex -SeedPackagePaths @('agents/demo/delta.md') -PackageName 'chain')
            $closed.Count | Should -Be 1
            $closed[0] | Should -BeExactly 'agents/demo/delta.md'
        }
    }

    Context 'when a resolved recipe closes its agents' {
        It 'Adds every transitively reachable agent to the recipe' {
            $entry = @{ name = 'consumer'; agents = @('agents/demo/alpha.md') }
            $recipe = @(Get-MarketplaceResolvedPackageRecipe -Entry $entry -Channel 'PreRelease' -AgentIndex $script:ClosureIndex)
            $recipe.Count | Should -Be 4
            ($recipe.PackagePath -join '|') | Should -BeExactly 'agents/demo/alpha.md|agents/demo/bravo.md|agents/demo/charlie.md|agents/demo/delta.md'
        }

        It 'Stamps closure-added agents as agent components in the agents field' {
            $entry = @{ name = 'consumer'; agents = @('agents/demo/alpha.md') }
            $recipe = @(Get-MarketplaceResolvedPackageRecipe -Entry $entry -Channel 'PreRelease' -AgentIndex $script:ClosureIndex)
            $added = @($recipe | Where-Object { $_.PackagePath -ne 'agents/demo/alpha.md' })
            $added.Count | Should -Be 3
            foreach ($item in $added) {
                $item.Kind | Should -BeExactly 'agent'
                $item.Field | Should -BeExactly 'agents'
                $item.SourcePath | Should -BeLike '.github/agents/demo/*.agent.md'
            }
        }

        It 'Stamps closure-added agents as stable regardless of componentMaturity metadata' {
            $entry = @{
                name    = 'consumer'
                agents  = @('agents/demo/alpha.md')
                'x-hve' = @{ componentMaturity = @{ 'agents/demo/bravo.md' = 'experimental' } }
            }
            $recipe = @(Get-MarketplaceResolvedPackageRecipe -Entry $entry -Channel 'Stable' -AgentIndex $script:ClosureIndex)
            $recipe.Count | Should -Be 4

            $bravo = @($recipe | Where-Object { $_.PackagePath -eq 'agents/demo/bravo.md' })
            $bravo.Count | Should -Be 1
            $bravo[0].Maturity | Should -BeExactly 'stable'
        }

        It 'Filters seeds by channel before closing dependencies' {
            $entry = @{
                name    = 'consumer'
                agents  = @('agents/demo/alpha.md', 'agents/demo/echo.md')
                'x-hve' = @{ componentMaturity = @{ 'agents/demo/echo.md' = 'experimental' } }
            }

            $stableRecipe = @(Get-MarketplaceResolvedPackageRecipe -Entry $entry -Channel 'Stable' -AgentIndex $script:ClosureIndex)
            $stableRecipe.Count | Should -Be 4
            $stableRecipe.PackagePath | Should -Not -Contain 'agents/demo/echo.md'

            $preReleaseRecipe = @(Get-MarketplaceResolvedPackageRecipe -Entry $entry -Channel 'PreRelease' -AgentIndex $script:ClosureIndex)
            $preReleaseRecipe.Count | Should -Be 5
            $preReleaseRecipe.PackagePath | Should -Contain 'agents/demo/echo.md'
        }

        It 'Preserves the declared maturity of seed agents' {
            $entry = @{
                name    = 'consumer'
                agents  = @('agents/demo/echo.md')
                'x-hve' = @{ componentMaturity = @{ 'agents/demo/echo.md' = 'preview' } }
            }
            $recipe = @(Get-MarketplaceResolvedPackageRecipe -Entry $entry -Channel 'PreRelease' -AgentIndex $script:ClosureIndex)
            $echo = @($recipe | Where-Object { $_.PackagePath -eq 'agents/demo/echo.md' })
            $echo.Count | Should -Be 1
            $echo[0].Maturity | Should -BeExactly 'preview'
        }

        It 'Leaves non-agent components untouched by closure' {
            $entry = @{ name = 'consumer'; skills = @('skills/demo/toolkit') }
            $recipe = @(Get-MarketplaceResolvedPackageRecipe -Entry $entry -Channel 'PreRelease' -AgentIndex $script:ClosureIndex)
            $recipe.Count | Should -Be 1
            $recipe[0].Kind | Should -BeExactly 'skill'
        }

        It 'Returns an empty recipe when the entry declares nothing' {
            @(Get-MarketplaceResolvedPackageRecipe -Entry @{ name = 'consumer' } -Channel 'PreRelease' -AgentIndex $script:ClosureIndex).Count |
                Should -Be 0
        }
    }
}

AfterAll {
    Remove-Module MarketplaceHelpers -Force -ErrorAction SilentlyContinue
}
