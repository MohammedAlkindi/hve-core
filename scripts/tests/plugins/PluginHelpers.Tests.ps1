#Requires -Modules Pester
# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT

[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
param()

BeforeAll {
    Import-Module $PSScriptRoot/../../plugins/Modules/PluginHelpers.psm1 -Force
}

Describe 'New-PluginManifestContent' -Tag 'Unit' {
    It 'Emits sorted component paths and a single hook path' {
        $manifest = New-PluginManifestContent `
            -CollectionId 'test' `
            -Description 'Test plugin' `
            -Version '1.0.0' `
            -AgentPaths @('.github/agents/z/', '.github/agents/a/') `
            -CommandPaths @('.github/prompts/test/') `
            -SkillPaths @('.github/skills/test/skill') `
            -RulePaths @('.github/instructions/test/') `
            -HookPaths @('.github/hooks/test/hooks.json')

        $manifest.name | Should -Be 'test'
        $manifest.agents | Should -Be @('.github/agents/a/', '.github/agents/z/')
        $manifest.commands | Should -Be @('.github/prompts/test/')
        $manifest.skills | Should -Be @('.github/skills/test/skill')
        $manifest.rules | Should -Be @('.github/instructions/test/')
        $manifest.hooks | Should -Be '.github/hooks/test/hooks.json'
    }

    It 'Omits component fields when no paths are provided' {
        $manifest = New-PluginManifestContent -CollectionId 'empty' -Description 'Empty' -Version '1.0.0'

        $manifest.Keys | Should -Be @('name', 'description', 'version')
    }
}

Describe 'Write-PluginDirectory' -Tag 'Unit' {
    BeforeAll {
        $script:repoRoot = Join-Path $TestDrive 'repo'
        $script:pluginsDir = Join-Path $script:repoRoot 'plugins'
        $sourcePaths = @(
            '.github/agents/test/example.agent.md',
            '.github/prompts/test/example.prompt.md',
            '.github/instructions/test/example.instructions.md',
            '.github/skills/test/example-skill/SKILL.md',
            '.github/hooks/test/hooks.json'
        )
        foreach ($sourcePath in $sourcePaths) {
            $fullPath = Join-Path $script:repoRoot $sourcePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $fullPath) -Force | Out-Null
            Set-Content -LiteralPath $fullPath -Value 'test'
        }
        $collectionsDir = Join-Path $script:repoRoot 'collections'
        New-Item -ItemType Directory -Path $collectionsDir -Force | Out-Null
        $script:collectionReadme = "# Test Plugin`n`nCollection overview.`n"
        Set-Content -LiteralPath (Join-Path $collectionsDir 'test-plugin.collection.md') `
            -Value $script:collectionReadme -Encoding utf8NoBOM -NoNewline

        $script:collection = @{
            id = 'test-plugin'
            name = 'Test Plugin'
            description = 'Manifest projection test'
            items = @(
                @{ kind = 'agent'; path = '.github/agents/test/example.agent.md' }
                @{ kind = 'prompt'; path = '.github/prompts/test/example.prompt.md' }
                @{ kind = 'instruction'; path = '.github/instructions/test/example.instructions.md' }
                @{ kind = 'skill'; path = '.github/skills/test/example-skill' }
                @{ kind = 'hook'; path = '.github/hooks/test/hooks.json' }
            )
        }
    }

    It 'Writes plugin.json and a README copied from collection markdown' {
        $result = Write-PluginDirectory -Collection $script:collection -PluginsDir $script:pluginsDir `
            -RepoRoot $script:repoRoot -Version '1.0.0'

        $pluginRoot = Join-Path $script:pluginsDir 'test-plugin'
        $manifestPath = Join-Path $pluginRoot '.github/plugin/plugin.json'
        $readmePath = Join-Path $pluginRoot 'README.md'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $generatedFiles = @(Get-ChildItem -LiteralPath $pluginRoot -File -Recurse -Force)

        $result.AgentCount | Should -Be 1
        $result.CommandCount | Should -Be 1
        $result.InstructionCount | Should -Be 1
        $result.SkillCount | Should -Be 1
        $result.HookCount | Should -Be 1
        $generatedFiles.Count | Should -Be 2
        $generatedFiles.FullName | Should -Contain $manifestPath
        $generatedFiles.FullName | Should -Contain $readmePath
        Get-Content -LiteralPath $readmePath -Raw | Should -BeExactly $script:collectionReadme

        $expectedTargets = @{
            agents = Join-Path $script:repoRoot '.github/agents/test'
            commands = Join-Path $script:repoRoot '.github/prompts/test'
            rules = Join-Path $script:repoRoot '.github/instructions/test'
            skills = Join-Path $script:repoRoot '.github/skills/test/example-skill'
            hooks = Join-Path $script:repoRoot '.github/hooks/test/hooks.json'
        }
        foreach ($field in $expectedTargets.Keys) {
            $declaredPath = @($manifest.$field)[0]
            $resolvedPath = [System.IO.Path]::TrimEndingDirectorySeparator(
                [System.IO.Path]::GetFullPath((Join-Path $script:repoRoot $declaredPath))
            )
            $expectedPath = [System.IO.Path]::TrimEndingDirectorySeparator(
                [System.IO.Path]::GetFullPath($expectedTargets[$field])
            )
            $resolvedPath | Should -Be $expectedPath
        }
    }

    It 'Validates sources without writing during DryRun' {
        $dryRunPlugins = Join-Path $script:repoRoot 'dry-run-plugins'

        $result = Write-PluginDirectory -Collection $script:collection -PluginsDir $dryRunPlugins `
            -RepoRoot $script:repoRoot -Version '1.0.0' -DryRun

        $result.Success | Should -BeTrue
        Test-Path $dryRunPlugins | Should -BeFalse
    }

    It 'Rejects a missing collection source' {
        $collection = @{
            id = 'missing'
            description = 'Missing source'
            items = @(@{ kind = 'agent'; path = '.github/agents/missing.agent.md' })
        }

        {
            Write-PluginDirectory -Collection $collection -PluginsDir $script:pluginsDir `
                -RepoRoot $script:repoRoot -Version '1.0.0' -DryRun
        } | Should -Throw '*Plugin source not found*'
    }

    It 'Rejects a collection source outside the repository root' {
        $outsidePath = Join-Path (Split-Path -Parent $script:repoRoot) 'outside.agent.md'
        Set-Content -LiteralPath $outsidePath -Value 'outside'
        $collection = @{
            id = 'escape'
            description = 'Escaping source'
            items = @(@{ kind = 'agent'; path = '../outside.agent.md' })
        }

        {
            Write-PluginDirectory -Collection $collection -PluginsDir $script:pluginsDir `
                -RepoRoot $script:repoRoot -Version '1.0.0' -DryRun
        } | Should -Throw '*inside the repository root*'
    }
}
