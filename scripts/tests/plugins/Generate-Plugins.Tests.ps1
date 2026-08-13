#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

BeforeAll {
    . (Join-Path $PSScriptRoot '../../plugins/Generate-Plugins.ps1')
    Import-Module (Join-Path $PSScriptRoot '../../lib/Modules/CIHelpers.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'PluginTestFixtures.psm1') -Force

    $script:GeneratorHostLog = [System.Collections.Generic.List[string]]::new()
    Mock Write-Host { $script:GeneratorHostLog.Add([string]$Object) }
    Mock Write-Host {} -ModuleName PluginHelpers
    Mock Write-Warning {}
    Mock Write-Warning {} -ModuleName PluginHelpers

    function New-GeneratorFixture {
        <#
        .SYNOPSIS
        Builds a fixture repository with one catalog entry per supplied entry set.
        #>
        param(
            [Parameter(Mandatory)][string]$Root,
            [Parameter(Mandatory)][AllowEmptyCollection()][array]$Entries,
            [Parameter()][switch]$SkipCatalog
        )

        New-PluginFixtureRepository -Path $Root -Version '9.9.9' | Out-Null
        Add-PluginFixtureArtifactSet -RepoRoot $Root | Out-Null
        if (-not $SkipCatalog) {
            Add-PluginFixtureCatalog -RepoRoot $Root -Entries $Entries -Version '9.9.9' | Out-Null
        }
        return $Root
    }

    function New-RpiEntry {
        <#
        .SYNOPSIS
        Builds the standard fixture entry that declares every artifact kind.
        #>
        param(
            [Parameter()][string]$Name = 'rpi',
            [Parameter()][hashtable]$Overlay
        )

        return New-PluginFixtureEntry -Name $Name -Description 'RPI workflow package' -Version '9.9.9' `
            -Agents @('../../.github/agents/rpi/rpi-planner.agent.md') `
            -Commands @('../../.github/prompts/rpi/rpi-plan.prompt.md') `
            -Rules @('../../.github/instructions/shared/hve-core-location.instructions.md') `
            -Skills @('../../.github/skills/rpi/rpi-plan') `
            -Hook '../../.github/hooks/rpi/telemetry.json' `
            -Overlay $Overlay
    }
}

Describe 'Invoke-PluginGeneration' -Tag 'Unit' {
    BeforeEach {
        $script:GeneratorHostLog.Clear()
        $script:generatorRepo = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        $script:generatedPluginsRoot = Join-Path $script:generatorRepo 'plugins'
    }

    Context 'when generating a package that declares every artifact kind' {
        BeforeEach {
            New-GeneratorFixture -Root $script:generatorRepo -Entries @(New-RpiEntry) | Out-Null
            Add-PluginFixtureFile -RepoRoot $script:generatorRepo -RelativePath '.github/skills/rpi/rpi-plan/.venv/lib/site.py' -Content "sentinel_venv`n" -Untracked | Out-Null
            Add-PluginFixtureFile -RepoRoot $script:generatorRepo -RelativePath '.github/skills/rpi/rpi-plan/__pycache__/cache.pyc' -Content "sentinel_pycache`n" -Untracked | Out-Null

            $script:generationResult = Invoke-PluginGeneration -RepoRoot $script:generatorRepo -Refresh
            $script:generatedRoot = Join-Path $script:generatedPluginsRoot 'rpi'
            $script:generatedInventory = @(Get-PluginFixtureInventory -Path $script:generatedRoot)
        }

        It 'Reports one generated package' {
            $script:generationResult.Success | Should -BeTrue
            $script:generationResult.PluginCount | Should -Be 1
            @($script:generationResult.Keys | Sort-Object) | Should -Be @('ErrorMessage', 'PluginCount', 'Success')
        }

        It 'Generates exactly the manifest the package delivers' {
            $script:generatedInventory | Should -Be @('plugin.json')
        }

        It 'References canonical sources in place rather than copying them' {
            $manifest = Get-Content -LiteralPath (Join-Path $script:generatedRoot 'plugin.json') -Raw | ConvertFrom-Json -AsHashtable
            @($manifest['rules']) | Should -Be @('../../.github/instructions/shared/hve-core-location.instructions.md')
            @($manifest['agents']) | Should -Be @('../../.github/agents/rpi/rpi-planner.agent.md')
            @($manifest['commands']) | Should -Be @('../../.github/prompts/rpi/rpi-plan.prompt.md')
            @($manifest['skills']) | Should -Be @('../../.github/skills/rpi/rpi-plan')
            [string]$manifest['hooks'] | Should -BeExactly '../../.github/hooks/rpi/telemetry.json'
        }

        It 'Needs no collections directory' {
            Test-Path -LiteralPath (Join-Path $script:generatorRepo 'collections') | Should -BeFalse
        }

        It 'Copies no untracked residue or its sentinels' {
            $generatedText = @(Get-ChildItem -LiteralPath $script:generatedRoot -File -Recurse -Force |
                    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
            foreach ($sentinel in @('sentinel_venv', 'sentinel_pycache')) {
                $generatedText | Should -Not -Match $sentinel
            }
        }

        It 'Emits no symbolic link' {
            @(Get-PluginFixtureReparsePoint -Path $script:generatedPluginsRoot) | Should -HaveCount 0
        }

        It 'Emits no catalog overlay anywhere in the output' {
            foreach ($generatedFile in Get-ChildItem -LiteralPath $script:generatedRoot -File -Recurse -Force) {
                (Get-Content -LiteralPath $generatedFile.FullName -Raw) | Should -Not -Match 'x-hve'
            }
        }

        It 'Produces byte-identical output on a second refresh' {
            $firstDigest = Get-PluginFixtureTreeDigest -Path $script:generatedPluginsRoot
            Invoke-PluginGeneration -RepoRoot $script:generatorRepo -Refresh | Out-Null
            Get-PluginFixtureTreeDigest -Path $script:generatedPluginsRoot | Should -BeExactly $firstDigest
        }
    }

    Context 'when resolving the catalog path' {
        BeforeEach {
            New-GeneratorFixture -Root $script:generatorRepo -Entries @(New-RpiEntry) | Out-Null
            Add-PluginFixtureCatalog -RepoRoot $script:generatorRepo -Entries @(New-RpiEntry -Name 'alt') `
                -Version '9.9.9' -RelativePath 'alt/marketplace.json' | Out-Null
        }

        It 'Defaults to the repository catalog' {
            Invoke-PluginGeneration -RepoRoot $script:generatorRepo -Refresh | Out-Null
            Test-Path -LiteralPath (Join-Path $script:generatedPluginsRoot 'rpi/plugin.json') -PathType Leaf | Should -BeTrue
        }

        It 'Accepts a repository-relative catalog path' {
            Invoke-PluginGeneration -RepoRoot $script:generatorRepo -Refresh -CatalogPath 'alt/marketplace.json' | Out-Null
            Test-Path -LiteralPath (Join-Path $script:generatedPluginsRoot 'alt/plugin.json') -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $script:generatedPluginsRoot 'rpi') | Should -BeFalse
        }

        It 'Accepts an absolute catalog path' {
            Invoke-PluginGeneration -RepoRoot $script:generatorRepo -Refresh `
                -CatalogPath (Join-Path $script:generatorRepo 'alt/marketplace.json') | Out-Null
            Test-Path -LiteralPath (Join-Path $script:generatedPluginsRoot 'alt/plugin.json') -PathType Leaf | Should -BeTrue
        }
    }

    Context 'when the catalog declares no package' {
        BeforeEach {
            New-GeneratorFixture -Root $script:generatorRepo -Entries @() | Out-Null
            $script:emptyCatalogResult = Invoke-PluginGeneration -RepoRoot $script:generatorRepo -Refresh
        }

        It 'Returns a successful zero-package result' {
            $script:emptyCatalogResult.Success | Should -BeTrue
            $script:emptyCatalogResult.PluginCount | Should -Be 0
            $script:emptyCatalogResult.ErrorMessage | Should -BeExactly ''
        }

        It 'Creates no output directory' {
            Test-Path -LiteralPath $script:generatedPluginsRoot | Should -BeFalse
        }

        It 'Warns that the catalog declares no package' {
            Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -match 'No packages declared in' }
        }
    }

    Context 'when an unknown package name is requested' {
        BeforeEach {
            New-GeneratorFixture -Root $script:generatorRepo -Entries @(New-RpiEntry) | Out-Null
            $script:filteredResult = Invoke-PluginGeneration -RepoRoot $script:generatorRepo -Refresh -PackageNames @('rpi', 'ghost')
        }

        It 'Warns about the missing package name' {
            Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -match 'Packages not found: ghost' }
        }

        It 'Generates only the packages that exist' {
            $script:filteredResult.PluginCount | Should -Be 1
            @(Get-ChildItem -LiteralPath $script:generatedPluginsRoot -Directory | ForEach-Object { $_.Name }) |
                Should -Be @('rpi')
        }
    }

    Context 'when the catalog declares several packages' {
        BeforeEach {
            New-GeneratorFixture -Root $script:generatorRepo -Entries @(
                New-RpiEntry -Name 'zulu'
                New-RpiEntry -Name 'alpha'
                New-RpiEntry -Name 'mike'
            ) | Out-Null
            Invoke-PluginGeneration -RepoRoot $script:generatorRepo -Refresh | Out-Null
        }

        It 'Generates packages in sorted order' {
            $generationLines = @($script:GeneratorHostLog | Where-Object { $_ -match '^  \S+ \(\d+ items\)$' })
            $generationLines | Should -Be @('  alpha (5 items)', '  mike (5 items)', '  zulu (5 items)')
        }

        It 'Creates one directory per package' {
            @(Get-ChildItem -LiteralPath $script:generatedPluginsRoot -Directory | ForEach-Object { $_.Name } | Sort-Object) |
                Should -Be @('alpha', 'mike', 'zulu')
        }
    }

    Context 'when a package is deprecated or removed' {
        BeforeEach {
            New-GeneratorFixture -Root $script:generatorRepo -Entries @(
                New-RpiEntry -Name 'active'
                New-RpiEntry -Name 'retired' -Overlay @{ maturity = 'deprecated' }
                New-RpiEntry -Name 'deleted' -Overlay @{ maturity = 'removed' }
            ) | Out-Null
            $script:maturityResult = Invoke-PluginGeneration -RepoRoot $script:generatorRepo -Refresh
        }

        It 'Generates only the active package' {
            @(Get-ChildItem -LiteralPath $script:generatedPluginsRoot -Directory | ForEach-Object { $_.Name }) |
                Should -Be @('active')
            $script:maturityResult.PluginCount | Should -Be 1
        }
    }

    Context 'when a component declares a non-stable maturity' {
        BeforeEach {
            New-PluginFixtureRepository -Path $script:generatorRepo -Version '9.9.9' | Out-Null
            Add-PluginFixtureArtifactSet -RepoRoot $script:generatorRepo | Out-Null
            Add-PluginFixtureFile -RepoRoot $script:generatorRepo -RelativePath '.github/skills/rpi/rpi-lab/SKILL.md' `
                -Content "---`nname: rpi-lab`ndescription: Experimental lab skill`n---`n`n# Lab`n" | Out-Null
            Add-PluginFixtureCatalog -RepoRoot $script:generatorRepo -Version '9.9.9' -Entries @(
                New-PluginFixtureEntry -Name 'rpi' -Description 'RPI workflow package' -Version '9.9.9' `
                    -Skills @('../../.github/skills/rpi/rpi-plan', '../../.github/skills/rpi/rpi-lab') `
                    -Overlay @{ componentMaturity = @{ '../../.github/skills/rpi/rpi-lab' = 'experimental' } }
            ) | Out-Null
        }

        It 'Includes the experimental component on the <Channel> channel' -ForEach @(
            @{ Channel = 'Stable' }
            @{ Channel = 'PreRelease' }
        ) {
            Invoke-PluginGeneration -RepoRoot $script:generatorRepo -Refresh -Channel $Channel | Out-Null
            $manifest = Get-Content -LiteralPath (Join-Path $script:generatedPluginsRoot 'rpi/plugin.json') -Raw | ConvertFrom-Json -AsHashtable
            @($manifest['skills']) | Should -Be @('../../.github/skills/rpi/rpi-lab', '../../.github/skills/rpi/rpi-plan')
        }
    }

    Context 'when refreshing over stale output' {
        BeforeEach {
            New-GeneratorFixture -Root $script:generatorRepo -Entries @(New-RpiEntry) | Out-Null
            $script:staleFile = Join-Path $script:generatedPluginsRoot 'rpi/stale/orphan.md'
            New-Item -ItemType Directory -Path (Split-Path -Parent $script:staleFile) -Force | Out-Null
            Set-Content -LiteralPath $script:staleFile -Value "sentinel_orphan`n" -Encoding utf8NoBOM -NoNewline
            Invoke-PluginGeneration -RepoRoot $script:generatorRepo -Refresh | Out-Null
        }

        It 'Removes the orphaned file' {
            Test-Path -LiteralPath $script:staleFile | Should -BeFalse
        }

        It 'Removes the directory the orphan left empty' {
            Test-Path -LiteralPath (Join-Path $script:generatedPluginsRoot 'rpi/stale') | Should -BeFalse
        }
    }

    Context 'when a package is dropped from the catalog' {
        BeforeEach {
            New-GeneratorFixture -Root $script:generatorRepo -Entries @(
                New-RpiEntry -Name 'hve-core'
                New-RpiEntry -Name 'ado'
                New-RpiEntry -Name 'security'
            ) | Out-Null
            Invoke-PluginGeneration -RepoRoot $script:generatorRepo -Refresh | Out-Null

            Add-PluginFixtureCatalog -RepoRoot $script:generatorRepo -Version '9.9.9' -Entries @(
                New-RpiEntry -Name 'hve-core'
            ) | Out-Null
        }

        It 'Leaves only the declared package root' {
            Invoke-PluginGeneration -RepoRoot $script:generatorRepo -Refresh | Out-Null
            @(Get-ChildItem -LiteralPath $script:generatedPluginsRoot -Directory | ForEach-Object { $_.Name } | Sort-Object) |
                Should -Be @('hve-core')
        }

        It 'Converges on repeated generation' {
            Invoke-PluginGeneration -RepoRoot $script:generatorRepo -Refresh | Out-Null
            Invoke-PluginGeneration -RepoRoot $script:generatorRepo -Refresh | Out-Null
            @(Get-ChildItem -LiteralPath $script:generatedPluginsRoot -Directory | ForEach-Object { $_.Name }) |
                Should -Be @('hve-core')
        }

        It 'Removes a stale root that was never declared' {
            $undeclared = Join-Path $script:generatedPluginsRoot 'hve-core-all/plugin.json'
            New-Item -ItemType Directory -Path (Split-Path -Parent $undeclared) -Force | Out-Null
            Set-Content -LiteralPath $undeclared -Value "{}`n" -Encoding utf8NoBOM -NoNewline
            Invoke-PluginGeneration -RepoRoot $script:generatorRepo -Refresh | Out-Null
            Test-Path -LiteralPath (Join-Path $script:generatedPluginsRoot 'hve-core-all') | Should -BeFalse
        }

        It 'Preserves a stale root when generating a named subset' {
            Invoke-PluginGeneration -RepoRoot $script:generatorRepo -Refresh -PackageNames 'hve-core' | Out-Null
            @(Get-ChildItem -LiteralPath $script:generatedPluginsRoot -Directory | ForEach-Object { $_.Name } | Sort-Object) |
                Should -Be @('ado', 'hve-core', 'security')
        }

        It 'Reports the stale roots without deleting them on a dry run' {
            Invoke-PluginGeneration -RepoRoot $script:generatorRepo -Refresh -DryRun | Out-Null
            $script:GeneratorHostLog | Should -Contain '  [DRY RUN] Would remove stale plugin root: ado'
            @(Get-ChildItem -LiteralPath $script:generatedPluginsRoot -Directory | ForEach-Object { $_.Name } | Sort-Object) |
                Should -Be @('ado', 'hve-core', 'security')
        }
    }

    Context 'when a component is dropped from the catalog' {
        BeforeEach {
            New-GeneratorFixture -Root $script:generatorRepo -Entries @(New-RpiEntry) | Out-Null
            Invoke-PluginGeneration -RepoRoot $script:generatorRepo -Refresh | Out-Null

            Add-PluginFixtureCatalog -RepoRoot $script:generatorRepo -Version '9.9.9' -Entries @(
                New-PluginFixtureEntry -Name 'rpi' -Description 'RPI workflow package' -Version '9.9.9' `
                    -Agents @('../../.github/agents/rpi/rpi-planner.agent.md')
            ) | Out-Null
            Invoke-PluginGeneration -RepoRoot $script:generatorRepo -Refresh | Out-Null
        }

        It 'Removes the dropped component from the runtime manifest' {
            @(Get-PluginFixtureInventory -Path (Join-Path $script:generatedPluginsRoot 'rpi')) | Should -Be @('plugin.json')
            $manifest = Get-Content -LiteralPath (Join-Path $script:generatedPluginsRoot 'rpi/plugin.json') -Raw | ConvertFrom-Json -AsHashtable
            @($manifest['agents']) | Should -Be @('../../.github/agents/rpi/rpi-planner.agent.md')
            $manifest.Contains('skills') | Should -BeFalse
            $manifest.Contains('commands') | Should -BeFalse
            $manifest.Contains('rules') | Should -BeFalse
            $manifest.Contains('hooks') | Should -BeFalse
        }
    }

    Context 'when running as a dry run' {
        BeforeEach {
            New-GeneratorFixture -Root $script:generatorRepo -Entries @(New-RpiEntry) | Out-Null
            $script:dryRunGeneration = Invoke-PluginGeneration -RepoRoot $script:generatorRepo -DryRun
        }

        It 'Reports the packages it would generate' {
            $script:dryRunGeneration.PluginCount | Should -Be 1
        }

        It 'Writes nothing to disk' {
            Test-Path -LiteralPath $script:generatedPluginsRoot | Should -BeFalse
        }
    }
}

Describe 'Invoke-PluginGenerationCheck' -Tag 'Unit' {
    BeforeEach {
        $script:GeneratorHostLog.Clear()
        $script:checkRepo = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-GeneratorFixture -Root $script:checkRepo -Entries @(New-RpiEntry) | Out-Null
        Invoke-PluginGeneration -RepoRoot $script:checkRepo -Refresh | Out-Null
        $script:checkedRoot = Join-Path $script:checkRepo 'plugins/rpi'
    }

    Context 'when the tracked roots match the catalog projection' {
        It 'Reports no drift' {
            $result = Invoke-PluginGenerationCheck -RepoRoot $script:checkRepo
            $result.Success | Should -BeTrue
            $result.PluginCount | Should -Be 1
            $result.ErrorMessage | Should -BeExactly ''
        }

        It 'Leaves the tracked roots byte-identical' {
            $before = Get-PluginFixtureTreeDigest -Path (Join-Path $script:checkRepo 'plugins')
            Invoke-PluginGenerationCheck -RepoRoot $script:checkRepo | Out-Null
            Get-PluginFixtureTreeDigest -Path (Join-Path $script:checkRepo 'plugins') | Should -BeExactly $before
        }
    }

    Context 'when a tracked root disagrees with the catalog projection' {
        It 'Fails on a missing generated manifest' {
            Remove-Item -LiteralPath (Join-Path $script:checkedRoot 'plugin.json') -Force

            $result = Invoke-PluginGenerationCheck -RepoRoot $script:checkRepo
            $result.Success | Should -BeFalse
            $result.ErrorMessage | Should -Match 'Tracked plugins/ differs from the catalog projection'
            Test-Path -LiteralPath (Join-Path $script:checkedRoot 'plugin.json') | Should -BeFalse
        }

        It 'Fails on an extra file without removing it' {
            $extraFile = Join-Path $script:checkedRoot 'EXTRA.md'
            Set-Content -LiteralPath $extraFile -Value "extra`n" -Encoding utf8NoBOM -NoNewline

            (Invoke-PluginGenerationCheck -RepoRoot $script:checkRepo).Success | Should -BeFalse
            Test-Path -LiteralPath $extraFile -PathType Leaf | Should -BeTrue
        }

        It 'Fails on altered content without rewriting it' {
            $manifestPath = Join-Path $script:checkedRoot 'plugin.json'
            Set-Content -LiteralPath $manifestPath -Value "{}`n" -Encoding utf8NoBOM -NoNewline

            (Invoke-PluginGenerationCheck -RepoRoot $script:checkRepo).Success | Should -BeFalse
            Get-Content -LiteralPath $manifestPath -Raw | Should -BeExactly "{}`n"
        }

        It 'Fails on a package root the catalog no longer declares' {
            $staleManifest = Join-Path $script:checkRepo 'plugins/ghost/plugin.json'
            New-Item -ItemType Directory -Path (Split-Path -Parent $staleManifest) -Force | Out-Null
            Set-Content -LiteralPath $staleManifest -Value "{}`n" -Encoding utf8NoBOM -NoNewline

            (Invoke-PluginGenerationCheck -RepoRoot $script:checkRepo).Success | Should -BeFalse
            Test-Path -LiteralPath $staleManifest -PathType Leaf | Should -BeTrue
        }
    }
}

Describe 'Start-PluginGeneration' -Tag 'Unit' {
    BeforeEach {
        $script:GeneratorHostLog.Clear()
        $script:entryRepo = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-GeneratorFixture -Root $script:entryRepo -Entries @(New-RpiEntry) | Out-Null
        $script:entryScriptPath = Add-PluginFixtureFile -RepoRoot $script:entryRepo `
            -RelativePath 'scripts/plugins/Generate-Plugins.ps1' -Content "# fixture entry point`n"
        Mock Write-CIAnnotation {}
    }

    Context 'when generation succeeds' {
        It 'Returns the success exit code' {
            Start-PluginGeneration -ScriptPath $script:entryScriptPath | Should -Be 0
        }

        It 'Writes the tracked package root' {
            Start-PluginGeneration -ScriptPath $script:entryScriptPath | Should -Be 0
            Test-Path -LiteralPath (Join-Path $script:entryRepo 'plugins/rpi/plugin.json') -PathType Leaf | Should -BeTrue
        }

        It 'Defaults to refreshing every package' {
            $orphanFile = Join-Path $script:entryRepo 'plugins/rpi/stale/orphan.md'
            New-Item -ItemType Directory -Path (Split-Path -Parent $orphanFile) -Force | Out-Null
            Set-Content -LiteralPath $orphanFile -Value "orphan`n" -Encoding utf8NoBOM -NoNewline

            Start-PluginGeneration -ScriptPath $script:entryScriptPath | Should -Be 0
            Test-Path -LiteralPath $orphanFile | Should -BeFalse
        }
    }

    Context 'when the drift check runs' {
        It 'Returns the success exit code for tracked roots that match' {
            Start-PluginGeneration -ScriptPath $script:entryScriptPath | Should -Be 0
            Start-PluginGeneration -ScriptPath $script:entryScriptPath -Check | Should -Be 0
        }

        It 'Returns the failure exit code for drifted tracked roots' {
            Start-PluginGeneration -ScriptPath $script:entryScriptPath | Should -Be 0
            Set-Content -LiteralPath (Join-Path $script:entryRepo 'plugins/rpi/plugin.json') -Value "{}`n" -Encoding utf8NoBOM -NoNewline

            Start-PluginGeneration -ScriptPath $script:entryScriptPath -Check -ErrorAction SilentlyContinue | Should -Be 1
            Get-Content -LiteralPath (Join-Path $script:entryRepo 'plugins/rpi/plugin.json') -Raw | Should -BeExactly "{}`n"
        }
    }

    Context 'when generation fails' {
        It 'Returns the failure exit code' {
            Start-PluginGeneration -ScriptPath $script:entryScriptPath -CatalogPath 'absent/marketplace.json' -ErrorAction SilentlyContinue |
                Should -Be 1
        }

        It 'Emits a CI annotation for the failure' {
            Start-PluginGeneration -ScriptPath $script:entryScriptPath -CatalogPath 'absent/marketplace.json' -ErrorAction SilentlyContinue | Out-Null
            Should -Invoke Write-CIAnnotation -Times 1 -Exactly -ParameterFilter { $Level -eq 'Error' }
        }
    }

    Context 'when the YAML prerequisite is unavailable' {
        It 'Fails before generating anything' {
            Mock Get-Module { } -ParameterFilter { $ListAvailable.IsPresent -and $Name -contains 'PowerShell-Yaml' }

            Start-PluginGeneration -ScriptPath $script:entryScriptPath -ErrorAction SilentlyContinue | Should -Be 1
            Test-Path -LiteralPath (Join-Path $script:entryRepo 'plugins') | Should -BeFalse
            Should -Invoke Write-CIAnnotation -Times 1 -Exactly -ParameterFilter { $Message -match "PowerShell-Yaml' is not installed" }
        }
    }
}

AfterAll {
    Remove-Module PluginTestFixtures -Force -ErrorAction SilentlyContinue
    Remove-Module PluginHelpers -Force -ErrorAction SilentlyContinue
    Remove-Module CIHelpers -Force -ErrorAction SilentlyContinue
}
