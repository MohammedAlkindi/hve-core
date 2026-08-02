#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Discovery-time capability probe: the Bash parity fixtures execute the real
# collision-detection.sh, so they are skipped where no Bash interpreter is present.
$script:BashAvailable = [bool](Get-Command bash -ErrorAction SilentlyContinue)

BeforeAll {
    $script:PowerShellScript = (Resolve-Path (Join-Path $PSScriptRoot '../scripts/collision-detection.ps1')).Path
    $script:BashScript = (Resolve-Path (Join-Path $PSScriptRoot '../scripts/collision-detection.sh')).Path
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../../..')).Path
    $script:FixtureCounter = 0

    # The default bundle offered when the user declines package selection.
    $script:DefaultBundleFiles = @('rpi-agent.agent.md', 'documentation.agent.md')

    function script:New-CollisionFixture {
        param([string[]]$ExistingAgents = @())

        $script:FixtureCounter++
        $target = Join-Path $TestDrive "collision-$($script:FixtureCounter)"
        New-Item -ItemType Directory -Path $target -Force | Out-Null

        if ($ExistingAgents.Count -gt 0) {
            $agentsDir = Join-Path $target '.github/agents'
            New-Item -ItemType Directory -Path $agentsDir -Force | Out-Null
            foreach ($name in $ExistingAgents) {
                Set-Content -LiteralPath (Join-Path $agentsDir $name) -Value "# $name" -NoNewline
            }
        }

        return $target
    }

    function script:Get-CollisionFile {
        param([string]$Output)

        $match = [regex]::Match($Output, '(?m)^COLLISION_FILES=(.*)$')
        if (-not $match.Success) { return @() }
        return @($match.Groups[1].Value.Trim() -split ',' | Where-Object { $_ })
    }
}

Describe 'collision-detection parameter contract' -Tag 'Unit' {
    BeforeAll {
        $script:command = Get-Command -Name $script:PowerShellScript
        # System.Collections.* is the .NET base class library namespace, not
        # installer bundle vocabulary, so it is removed before the domain scan.
        $script:powerShellSource = (Get-Content -LiteralPath $script:PowerShellScript -Raw) -replace 'System\.Collections\.\w+', ''
        $script:bashSource = Get-Content -LiteralPath $script:BashScript -Raw
    }

    It 'Declares Selection and PackageAgents and no collection-named parameter' {
        $script:command.Parameters.Keys | Should -Contain 'Selection'
        $script:command.Parameters.Keys | Should -Contain 'PackageAgents'
        @($script:command.Parameters.Keys | Where-Object { $_ -match 'collection' }) | Should -BeNullOrEmpty
    }

    It 'Uses package vocabulary and no collection fallback in the PowerShell implementation' {
        $script:powerShellSource | Should -Match '\$PackageAgents'
        $script:powerShellSource | Should -Not -Match '(?i)collection'
    }

    It 'Uses package vocabulary and no collection fallback in the Bash implementation' {
        $script:bashSource | Should -Match 'package_agents'
        $script:bashSource | Should -Not -Match '(?i)collection'
    }
}

Describe 'collision-detection default bundle' -Tag 'Unit' {
    It 'Reports no collisions when the target has no agents directory' {
        $target = New-CollisionFixture
        Push-Location $target
        try {
            $output = & $script:PowerShellScript -Selection 'hve-core' 6>&1 | Out-String
        }
        finally { Pop-Location }

        $output | Should -Match 'COLLISIONS_DETECTED=false'
        $output | Should -Not -Match 'COLLISION_FILES='
    }

    It 'Reports no collisions when only unrelated agents exist' {
        $target = New-CollisionFixture -ExistingAgents @('unrelated.agent.md')
        Push-Location $target
        try {
            $output = & $script:PowerShellScript -Selection 'hve-core' 6>&1 | Out-String
        }
        finally { Pop-Location }

        $output | Should -Match 'COLLISIONS_DETECTED=false'
    }

    It 'Reports every default bundle agent that already exists' {
        $target = New-CollisionFixture -ExistingAgents $script:DefaultBundleFiles
        Push-Location $target
        try {
            $output = & $script:PowerShellScript -Selection 'hve-core' 6>&1 | Out-String
        }
        finally { Pop-Location }

        $output | Should -Match 'COLLISIONS_DETECTED=true'
        @(Get-CollisionFile -Output $output | Sort-Object) | Should -Be @(
            '.github/agents/documentation.agent.md'
            '.github/agents/rpi-agent.agent.md'
        )
    }
}

Describe 'collision-detection package identity' -Tag 'Unit' {
    It 'Checks the supplied package agents rather than the default bundle' {
        $target = New-CollisionFixture -ExistingAgents @('rpi-agent.agent.md', 'adr-creation.agent.md')
        Push-Location $target
        try {
            $output = & $script:PowerShellScript -Selection 'project-planning' -PackageAgents @('project-planning/adr-creation.agent.md') 6>&1 | Out-String
        }
        finally { Pop-Location }

        @(Get-CollisionFile -Output $output) | Should -Be @('.github/agents/adr-creation.agent.md')
    }

    It 'Reports no collisions when a package projects no agents' {
        $target = New-CollisionFixture -ExistingAgents @('rpi-agent.agent.md')
        Push-Location $target
        try {
            $output = & $script:PowerShellScript -Selection 'project-planning' -PackageAgents @() 6>&1 | Out-String
        }
        finally { Pop-Location }

        $output | Should -Match 'COLLISIONS_DETECTED=false'
    }

    It 'Ignores PackageAgents for the default bundle selection' {
        $target = New-CollisionFixture -ExistingAgents @('adr-creation.agent.md')
        Push-Location $target
        try {
            $output = & $script:PowerShellScript -Selection 'hve-core' -PackageAgents @('project-planning/adr-creation.agent.md') 6>&1 | Out-String
        }
        finally { Pop-Location }

        $output | Should -Match 'COLLISIONS_DETECTED=false'
    }
}

Describe 'collision-detection path handling' -Tag 'Unit' {
    It 'Emits forward-slash target paths regardless of host platform' {
        $target = New-CollisionFixture -ExistingAgents @('adr-creation.agent.md')
        Push-Location $target
        try {
            $output = & $script:PowerShellScript -Selection 'project-planning' -PackageAgents @('project-planning/adr-creation.agent.md') 6>&1 | Out-String
        }
        finally { Pop-Location }

        Get-CollisionFile -Output $output | Should -Be @('.github/agents/adr-creation.agent.md')
        $output | Should -Not -Match '\\'
    }

    It 'Reports a target shared by two package agents exactly once' {
        $target = New-CollisionFixture -ExistingAgents @('rpi-agent.agent.md')
        Push-Location $target
        try {
            $output = & $script:PowerShellScript -Selection 'hve-core-all' -PackageAgents @(
                'hve-core/rpi-agent.agent.md'
                'rpi/rpi-agent.agent.md'
            ) 6>&1 | Out-String
        }
        finally { Pop-Location }

        @(Get-CollisionFile -Output $output) | Should -Be @('.github/agents/rpi-agent.agent.md')
    }
}

Describe 'collision-detection marketplace recipe input' -Tag 'Unit' {
    BeforeAll {
        Import-Module (Join-Path $script:RepoRoot 'scripts/lib/Modules/MarketplaceHelpers.psm1') -Force

        $catalog = Get-MarketplaceCatalog -Path (Join-Path $script:RepoRoot '.github/plugin/marketplace.json')
        $agentIndex = Get-MarketplaceAgentIndex -Catalog $catalog -RepoRoot $script:RepoRoot
        $entry = @($catalog['plugins']) | Where-Object { $_['name'] -eq 'rpi' }
        $recipe = Get-MarketplaceResolvedPackageRecipe -Entry $entry -Channel Stable -AgentIndex $agentIndex

        # The agent list handed to the installer: agent recipe items with the
        # .github/agents/ prefix removed, as the package selection sub-flow builds it.
        $script:RpiPackageAgents = @(
            $recipe |
                Where-Object { $_.Kind -eq 'agent' } |
                ForEach-Object { $_.SourcePath -replace '^\.github/agents/', '' } |
                Sort-Object
        )
    }

    AfterAll {
        Remove-Module MarketplaceHelpers -Force -ErrorAction SilentlyContinue
    }

    It 'Resolves the rpi package Stable recipe to its published agent set' {
        $script:RpiPackageAgents | Should -Be @(
            'hve-core/subagents/rpi-planner.agent.md'
            'hve-core/subagents/rpi-researcher.agent.md'
        ) -Because 'the rpi marketplace package publishes the two RPI subagents at Stable maturity'
    }

    It 'Detects collisions for every agent the Stable recipe projects' {
        $target = New-CollisionFixture -ExistingAgents @('rpi-planner.agent.md', 'rpi-researcher.agent.md')
        Push-Location $target
        try {
            $output = & $script:PowerShellScript -Selection 'rpi' -PackageAgents $script:RpiPackageAgents 6>&1 | Out-String
        }
        finally { Pop-Location }

        $output | Should -Match 'COLLISIONS_DETECTED=true'
        @(Get-CollisionFile -Output $output | Sort-Object) | Should -Be @(
            '.github/agents/rpi-planner.agent.md'
            '.github/agents/rpi-researcher.agent.md'
        )
    }

    It 'Detects no collisions for a Stable recipe against an untouched target' {
        $target = New-CollisionFixture
        Push-Location $target
        try {
            $output = & $script:PowerShellScript -Selection 'rpi' -PackageAgents $script:RpiPackageAgents 6>&1 | Out-String
        }
        finally { Pop-Location }

        $output | Should -Match 'COLLISIONS_DETECTED=false'
    }
}

Describe 'collision-detection PowerShell and Bash parity' -Tag 'Unit' -Skip:(-not $script:BashAvailable) {
    BeforeAll {
        $script:sourceRoot = Join-Path $TestDrive 'parity-source'
        New-Item -ItemType Directory -Path $script:sourceRoot -Force | Out-Null
    }

    It 'Produces identical output for the default bundle with collisions' {
        $target = New-CollisionFixture -ExistingAgents $script:DefaultBundleFiles
        Push-Location $target
        try {
            $powerShellOutput = (& $script:PowerShellScript -Selection 'hve-core' 6>&1 | Out-String).Trim()
            $bashOutput = (& bash $script:BashScript $script:sourceRoot 'hve-core' 2>&1 | Out-String).Trim()
        }
        finally { Pop-Location }

        $bashOutput | Should -Be $powerShellOutput
    }

    It 'Produces identical output for the default bundle without collisions' {
        $target = New-CollisionFixture
        Push-Location $target
        try {
            $powerShellOutput = (& $script:PowerShellScript -Selection 'hve-core' 6>&1 | Out-String).Trim()
            $bashOutput = (& bash $script:BashScript $script:sourceRoot 'hve-core' 2>&1 | Out-String).Trim()
        }
        finally { Pop-Location }

        $bashOutput | Should -Be $powerShellOutput
    }

    It 'Produces identical output for a package agent list' {
        $target = New-CollisionFixture -ExistingAgents @('adr-creation.agent.md', 'prd-builder.agent.md')
        Push-Location $target
        try {
            $powerShellOutput = (& $script:PowerShellScript -Selection 'project-planning' -PackageAgents @(
                    'project-planning/adr-creation.agent.md'
                    'project-planning/prd-builder.agent.md'
                ) 6>&1 | Out-String).Trim()
            $bashOutput = (& bash $script:BashScript $script:sourceRoot 'project-planning' 'project-planning/adr-creation.agent.md' 'project-planning/prd-builder.agent.md' 2>&1 | Out-String).Trim()
        }
        finally { Pop-Location }

        $bashOutput | Should -Be $powerShellOutput
    }

    It 'Produces identical output when two package agents share one target' {
        $target = New-CollisionFixture -ExistingAgents @('rpi-agent.agent.md')
        Push-Location $target
        try {
            $powerShellOutput = (& $script:PowerShellScript -Selection 'hve-core-all' -PackageAgents @(
                    'hve-core/rpi-agent.agent.md'
                    'rpi/rpi-agent.agent.md'
                ) 6>&1 | Out-String).Trim()
            $bashOutput = (& bash $script:BashScript $script:sourceRoot 'hve-core-all' 'hve-core/rpi-agent.agent.md' 'rpi/rpi-agent.agent.md' 2>&1 | Out-String).Trim()
        }
        finally { Pop-Location }

        $bashOutput | Should -Be $powerShellOutput
    }

    It 'Produces identical output for a package that projects no agents' {
        $target = New-CollisionFixture -ExistingAgents @('rpi-agent.agent.md')
        Push-Location $target
        try {
            $powerShellOutput = (& $script:PowerShellScript -Selection 'project-planning' -PackageAgents @() 6>&1 | Out-String).Trim()
            $bashOutput = (& bash $script:BashScript $script:sourceRoot 'project-planning' 2>&1 | Out-String).Trim()
        }
        finally { Pop-Location }

        $bashOutput | Should -Be $powerShellOutput
    }

    It 'Declares the same default bundle in both implementations' {
        $pattern = '["'']hve-core/([^"'']+\.agent\.md)["'']'
        $powerShellDefaults = @([regex]::Matches((Get-Content -LiteralPath $script:PowerShellScript -Raw), $pattern) | ForEach-Object { $_.Groups[1].Value })
        $bashDefaults = @([regex]::Matches((Get-Content -LiteralPath $script:BashScript -Raw), $pattern) | ForEach-Object { $_.Groups[1].Value })

        $powerShellDefaults | Should -Be $script:DefaultBundleFiles
        $bashDefaults | Should -Be $script:DefaultBundleFiles
    }
}
