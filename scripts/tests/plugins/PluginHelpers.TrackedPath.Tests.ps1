#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../plugins/Modules/PluginHelpers.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'PluginTestFixtures.psm1') -Force
    Mock Write-Host {} -ModuleName PluginHelpers
    Mock Write-Warning {} -ModuleName PluginHelpers
}

Describe 'Get-PluginTrackedPathIndex' -Tag 'Unit' {
    Context 'when the working tree mixes tracked and untracked content' {
        BeforeAll {
            $script:indexRepo = Join-Path $TestDrive 'tracked-index'
            New-PluginFixtureRepository -Path $script:indexRepo -SkipSharedResources -SkipAgentRoot -SkipDocumentationRoot | Out-Null
            Add-PluginFixtureFile -RepoRoot $script:indexRepo -RelativePath '.github/skills/rpi/rpi-plan/SKILL.md' -Content "# Skill`n" | Out-Null
            Add-PluginFixtureFile -RepoRoot $script:indexRepo -RelativePath '.github/skills/rpi/rpi-plan/references/checklist.md' -Content "# Checklist`n" | Out-Null
            Add-PluginFixtureFile -RepoRoot $script:indexRepo -RelativePath '.github/skills/rpi/rpi-plan/.venv/lib/site.py' -Content "sentinel_venv`n" -Untracked | Out-Null
            Add-PluginFixtureFile -RepoRoot $script:indexRepo -RelativePath '.github/skills/rpi/rpi-plan/__pycache__/cache.pyc' -Content "sentinel_pycache`n" -Untracked | Out-Null
            Add-PluginFixtureFile -RepoRoot $script:indexRepo -RelativePath '.github/skills/rpi/rpi-plan/scratch.md' -Content "sentinel_scratch`n" -Untracked | Out-Null

            $script:trackedIndex = Get-PluginTrackedPathIndex -RepoRoot $script:indexRepo
        }

        It 'Returns exactly the staged paths' {
            @($script:trackedIndex.Paths | Sort-Object) | Should -Be @(
                @(
                    '.github/skills/rpi/rpi-plan/SKILL.md',
                    '.github/skills/rpi/rpi-plan/references/checklist.md',
                    'package.json'
                ) | Sort-Object
            )
        }

        It 'Records only real files, never directories' {
            foreach ($trackedPath in $script:trackedIndex.Paths) {
                Test-Path -LiteralPath (Join-Path $script:indexRepo $trackedPath) -PathType Leaf | Should -BeTrue
            }
        }

        It 'Excludes the untracked sentinel <Path>' -ForEach @(
            @{ Path = '.github/skills/rpi/rpi-plan/.venv/lib/site.py' }
            @{ Path = '.github/skills/rpi/rpi-plan/__pycache__/cache.pyc' }
            @{ Path = '.github/skills/rpi/rpi-plan/scratch.md' }
        ) {
            $script:trackedIndex.Lookup.Contains($Path) | Should -BeFalse
        }

        It 'Exposes an ordinal lookup for tracked paths' {
            $script:trackedIndex.Lookup.Contains('package.json') | Should -BeTrue
            $script:trackedIndex.Lookup.Contains('PACKAGE.JSON') | Should -BeFalse
        }

        It 'Records the resolved working tree root' {
            $script:trackedIndex.RepoRoot | Should -BeExactly ([System.IO.Path]::GetFullPath($script:indexRepo))
        }
    }

    Context 'when the directory is not a git working tree' {
        It 'Refuses to build an allowlist' {
            $plainDirectory = Join-Path $TestDrive 'not-a-repo'
            New-Item -ItemType Directory -Path $plainDirectory -Force | Out-Null
            { Get-PluginTrackedPathIndex -RepoRoot $plainDirectory } |
                Should -Throw -ExpectedMessage '*Unable to enumerate git-tracked paths*'
        }
    }
}

AfterAll {
    Remove-Module PluginHelpers -Force -ErrorAction SilentlyContinue
    Remove-Module PluginTestFixtures -Force -ErrorAction SilentlyContinue
}
