#Requires -Modules Pester
# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT

[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
param()

BeforeAll {
    Import-Module $PSScriptRoot/../../plugins/Modules/PluginHelpers.psm1 -Force
}

Describe 'New-PluginReadmeContent - maturity notice' {
    It 'Includes experimental notice when maturity is experimental' {
        $collection = @{
            id          = 'test-exp'
            name        = 'Test Experimental'
            description = 'An experimental collection'
        }
        $items = @(@{ Name = 'test-agent'; Description = 'desc'; Kind = 'agent' })
        $result = New-PluginReadmeContent -Collection $collection -Items $items -Maturity 'experimental'
        $result | Should -Match '\u26A0' # warning sign emoji
    }

    It 'Has no notice when maturity is stable' {
        $collection = @{
            id          = 'test-stable'
            name        = 'Test Stable'
            description = 'A stable collection'
        }
        $items = @(@{ Name = 'test-agent'; Description = 'desc'; Kind = 'agent' })
        $result = New-PluginReadmeContent -Collection $collection -Items $items -Maturity 'stable'
        $result | Should -Not -Match '\u26A0'
    }

    It 'Has no notice when maturity is omitted' {
        $collection = @{
            id          = 'test-default'
            name        = 'Test Default'
            description = 'A default collection'
        }
        $items = @(@{ Name = 'test-agent'; Description = 'desc'; Kind = 'agent' })
        $result = New-PluginReadmeContent -Collection $collection -Items $items
        $result | Should -Not -Match '\u26A0'
    }

    It 'Has no notice when maturity is null' {
        $collection = @{
            id          = 'test-null'
            name        = 'Test Null'
            description = 'A null maturity collection'
        }
        $items = @(@{ Name = 'test-agent'; Description = 'desc'; Kind = 'agent' })
        $result = New-PluginReadmeContent -Collection $collection -Items $items -Maturity $null
        $result | Should -Not -Match '\u26A0'
    }
}

Describe 'New-PluginReadmeContent - CollectionContent H1 stripping' {
    BeforeAll {
        $baseCollection = @{
            id          = 'test-h1'
            name        = 'Test Collection'
            description = 'A test collection'
        }
        $items = @(@{ Name = 'test-agent'; Description = 'desc'; Kind = 'agent' })
    }

    It 'Strips leading H1 from CollectionContent to avoid duplicate title' {
        $content = "# Test Collection`n`nBody text here.`n"
        $result = New-PluginReadmeContent -Collection $baseCollection -Items $items -CollectionContent $content
        $h1Matches = [regex]::Matches($result, '(?m)^# ')
        $h1Matches.Count | Should -Be 1
        $result | Should -Match 'Body text here\.'
    }

    It 'Preserves artifact markers and tables in CollectionContent' {
        $content = "# Test Collection`n`nBody text.`n`n## Included Artifacts`n`n<!-- BEGIN AUTO-GENERATED ARTIFACTS -->`n`n### Chat Agents`n`n<!-- END AUTO-GENERATED ARTIFACTS -->`n"
        $result = New-PluginReadmeContent -Collection $baseCollection -Items $items -CollectionContent $content
        $result | Should -Match '<!-- BEGIN AUTO-GENERATED ARTIFACTS -->'
        $result | Should -Match '<!-- END AUTO-GENERATED ARTIFACTS -->'
        $result | Should -Match '## Included Artifacts'
        $includedArtifactMatches = [regex]::Matches($result, '(?m)^## Included Artifacts$')
        $includedArtifactMatches.Count | Should -Be 1
        $result | Should -Not -Match '(?m)^## Agents$'
    }

    It 'Does not duplicate sections when CollectionContent already holds rendered artifacts' {
        $content = "# Test Collection`n`nBody text.`n`n## Included Artifacts`n`n<!-- BEGIN AUTO-GENERATED ARTIFACTS -->`n`n### Chat Agents`n`n| Agent | Description |`n|-------|-------------|`n| test-agent | desc |`n`n<!-- END AUTO-GENERATED ARTIFACTS -->`n"
        $result = New-PluginReadmeContent -Collection $baseCollection -Items $items -CollectionContent $content
        [regex]::Matches($result, '(?m)^## Included Artifacts\r?$').Count | Should -Be 1
        [regex]::Matches($result, '(?m)^## Overview\r?$').Count | Should -Be 1
        [regex]::Matches($result, '(?m)^## Install\r?$').Count | Should -Be 1
        [regex]::Matches($result, '(?m)^# ').Count | Should -Be 1
        [regex]::Matches($result, '<!-- BEGIN AUTO-GENERATED ARTIFACTS -->').Count | Should -Be 1
        $result | Should -Not -Match '(?m)^## Agents\r?$'
        $result | Should -Not -Match '(?m)^## Commands\r?$'
    }

    It 'Emits Overview section when CollectionContent has body text' {
        $content = "# Test Collection`n`nSome description.`n"
        $result = New-PluginReadmeContent -Collection $baseCollection -Items $items -CollectionContent $content
        $result | Should -Match '## Overview'
        $result | Should -Match 'Some description\.'
    }

    It 'Omits Overview section when CollectionContent is null' {
        $result = New-PluginReadmeContent -Collection $baseCollection -Items $items -CollectionContent $null
        $result | Should -Not -Match '## Overview'
    }

    It 'Omits Overview section when CollectionContent is whitespace' {
        $result = New-PluginReadmeContent -Collection $baseCollection -Items $items -CollectionContent '   '
        $result | Should -Not -Match '## Overview'
    }
}

Describe 'Get-PluginItemName' {
    It 'Strips .agent.md to .md for agents' {
        $result = Get-PluginItemName -FileName 'sample-agent.agent.md' -Kind 'agent'
        $result | Should -Be 'sample-agent.md'
    }

    It 'Strips .prompt.md to .md for prompts' {
        $result = Get-PluginItemName -FileName 'gen-plan.prompt.md' -Kind 'prompt'
        $result | Should -Be 'gen-plan.md'
    }

    It 'Preserves .instructions.md suffix' {
        $result = Get-PluginItemName -FileName 'csharp.instructions.md' -Kind 'instruction'
        $result | Should -Be 'csharp.instructions.md'
    }

    It 'Returns skill directory name unchanged' {
        $result = Get-PluginItemName -FileName 'video-to-gif' -Kind 'skill'
        $result | Should -Be 'video-to-gif'
    }
}

Describe 'Get-PluginItemSubpath' {
    It 'Extracts single-level collection subdirectory for agents' {
        $result = Get-PluginItemSubpath -Path '.github/agents/hve-core/rpi-agent.agent.md' -Kind 'agent'
        $result | Should -Be 'hve-core'
    }

    It 'Extracts nested subdirectory path for agent subagents' {
        $result = Get-PluginItemSubpath -Path '.github/agents/hve-core/subagents/sample-subagent.agent.md' -Kind 'agent'
        $result | Should -Be 'hve-core/subagents'
    }

    It 'Returns empty string when item is at kind root' {
        $result = Get-PluginItemSubpath -Path '.github/agents/root-agent.agent.md' -Kind 'agent'
        $result | Should -Be ''
    }

    It 'Extracts subdirectory for instructions' {
        $result = Get-PluginItemSubpath -Path '.github/instructions/shared/hve-core-location.instructions.md' -Kind 'instruction'
        $result | Should -Be 'shared'
    }

    It 'Extracts subdirectory for skills' {
        $result = Get-PluginItemSubpath -Path '.github/skills/shared/pr-reference' -Kind 'skill'
        $result | Should -Be 'shared'
    }

    It 'Handles backslash-separated paths' {
        $result = Get-PluginItemSubpath -Path '.github\agents\hve-core\rpi-agent.agent.md' -Kind 'agent'
        $result | Should -Be 'hve-core'
    }

    It 'Extracts subdirectory for prompts' {
        $result = Get-PluginItemSubpath -Path '.github/prompts/hve-core/git-commit-message.prompt.md' -Kind 'prompt'
        $result | Should -Be 'hve-core'
    }

    It 'Returns empty string when path does not match kind prefix' {
        $result = Get-PluginItemSubpath -Path 'some/other/path/file.md' -Kind 'agent'
        $result | Should -Be ''
    }
}

Describe 'New-PluginManifestContent' {
    It 'Returns hashtable with name, description, and version' {
        $result = New-PluginManifestContent -PackageName 'test-plugin' -Description 'A test plugin' -Version '2.0.0'
        $result.name | Should -Be 'test-plugin'
        $result.description | Should -Be 'A test plugin'
        $result.version | Should -Be '2.0.0'
    }

    It 'Includes explicit path arrays when provided' {
        $result = New-PluginManifestContent `
            -PackageName 'with-paths' -Description 'desc' -Version '1.0.0' `
            -AgentPaths @('agents/core/') `
            -CommandPaths @('commands/core/', 'commands/ado/') `
            -SkillPaths @('skills/shared/')
        $result.agents | Should -Be @('agents/core/')
        $result.commands | Should -Be @('commands/ado/', 'commands/core/')
        $result.skills | Should -Be @('skills/shared/')
    }

    It 'Omits component keys when no paths provided' {
        $result = New-PluginManifestContent -PackageName 'minimal' -Description 'desc' -Version '1.0.0'
        $result.Contains('agents') | Should -BeFalse
        $result.Contains('commands') | Should -BeFalse
        $result.Contains('skills') | Should -BeFalse
    }

    It 'Returns ordered hashtable' {
        $result = New-PluginManifestContent -PackageName 'ordered-test' -Description 'desc' -Version '1.0.0'
        $result | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
    }
}

Describe 'Get-PluginSubdirectory' {
    It 'Maps agent to agents' {
        $result = Get-PluginSubdirectory -Kind 'agent'
        $result | Should -Be 'agents'
    }

    It 'Maps prompt to commands' {
        $result = Get-PluginSubdirectory -Kind 'prompt'
        $result | Should -Be 'commands'
    }

    It 'Maps instruction to rules' {
        $result = Get-PluginSubdirectory -Kind 'instruction'
        $result | Should -Be 'rules'
    }

    It 'Maps skill to skills' {
        $result = Get-PluginSubdirectory -Kind 'skill'
        $result | Should -Be 'skills'
    }
}

Describe 'Write-PluginDirectory - DryRun mode' {
    BeforeAll {
        $script:repoRoot = Join-Path $TestDrive 'wpd-repo'
        $script:pluginsDir = Join-Path $TestDrive 'wpd-plugins'
        New-Item -ItemType Directory -Path $script:repoRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:pluginsDir -Force | Out-Null

        # Create a valid agent file with frontmatter
        $agentDir = Join-Path $script:repoRoot '.github/agents/test'
        New-Item -ItemType Directory -Path $agentDir -Force | Out-Null
        Set-Content -Path (Join-Path $agentDir 'example.agent.md') -Value "---`ndescription: An example agent`n---`nAgent body"

        # Create a valid skill directory with SKILL.md
        $skillDir = Join-Path $script:repoRoot '.github/skills/test/my-skill'
        New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
        Set-Content -Path (Join-Path $skillDir 'SKILL.md') -Value "---`ndescription: A skill`n---`nSkill body"

        # Create shared dirs
        New-Item -ItemType Directory -Path (Join-Path $script:repoRoot 'docs/templates') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:repoRoot 'scripts/lib') -Force | Out-Null
    }

    It 'Completes DryRun without creating files for agents' {
        $entry = @{ name = 'dryrun-test'; description = 'Testing DryRun mode' }
        $items = @(
            @{ Kind = 'agent'; Field = 'agents'; PackagePath = 'agents/test/example.md'; SourcePath = '.github/agents/test/example.agent.md' }
        )

        $result = Write-PluginDirectory -Entry $entry -Items $items -PluginsDir $script:pluginsDir `
            -RepoRoot $script:repoRoot -Version '1.0.0' -DryRun

        $result.Success | Should -BeTrue
        $result.AgentCount | Should -Be 1

        # Verify no actual files were created
        $pluginDir = Join-Path $script:pluginsDir 'dryrun-test'
        Test-Path -Path $pluginDir | Should -BeFalse
    }

    It 'Includes the declared subdirectory in GeneratedFiles path' {
        $entry = @{ name = 'subpath-test'; description = 'Testing subpath in destination' }
        $items = @(
            @{ Kind = 'agent'; Field = 'agents'; PackagePath = 'agents/test/example.md'; SourcePath = '.github/agents/test/example.agent.md' }
        )

        $result = Write-PluginDirectory -Entry $entry -Items $items -PluginsDir $script:pluginsDir `
            -RepoRoot $script:repoRoot -Version '1.0.0' -DryRun

        $result.Success | Should -BeTrue
        # GeneratedFiles should contain a path with the 'test' subdirectory preserved
        $agentPaths = @($result.GeneratedFiles | Where-Object { $_ -match 'agents' -and $_ -match 'example' })
        $agentPaths | Should -Not -BeNullOrEmpty
        $agentPaths[0] | Should -Match 'agents[/\\]test[/\\]example\.md$'
    }

    It 'Completes DryRun with skill items' {
        $entry = @{ name = 'dryrun-skill'; description = 'Testing DryRun with skills' }
        $items = @(
            @{ Kind = 'skill'; Field = 'skills'; PackagePath = 'skills/test/my-skill'; SourcePath = '.github/skills/test/my-skill' }
        )

        $result = Write-PluginDirectory -Entry $entry -Items $items -PluginsDir $script:pluginsDir `
            -RepoRoot $script:repoRoot -Version '1.0.0' -DryRun

        $result.Success | Should -BeTrue
        $result.SkillCount | Should -Be 1
    }

    It 'Handles source file not found for non-skill items' {
        $entry = @{ name = 'missing-source'; description = 'Non-existent source file' }
        $items = @(
            @{ Kind = 'agent'; Field = 'agents'; PackagePath = 'agents/test/nonexistent.md'; SourcePath = '.github/agents/test/nonexistent.agent.md' }
        )

        $result = Write-PluginDirectory -Entry $entry -Items $items -PluginsDir $script:pluginsDir `
            -RepoRoot $script:repoRoot -Version '1.0.0' -DryRun

        $result.Success | Should -BeTrue
        $result.AgentCount | Should -Be 1
    }

    It 'Warns when shared directory is missing' {
        $emptyRepo = Join-Path $TestDrive 'empty-repo'
        New-Item -ItemType Directory -Path $emptyRepo -Force | Out-Null

        # Create agent file but no shared directories
        $agentDir = Join-Path $emptyRepo '.github/agents/test'
        New-Item -ItemType Directory -Path $agentDir -Force | Out-Null
        Set-Content -Path (Join-Path $agentDir 'a.agent.md') -Value "---`ndescription: test`n---"

        $entry = @{ name = 'no-shared'; description = 'Missing shared dirs' }
        $items = @(
            @{ Kind = 'agent'; Field = 'agents'; PackagePath = 'agents/test/a.md'; SourcePath = '.github/agents/test/a.agent.md' }
        )

        $result = Write-PluginDirectory -Entry $entry -Items $items -PluginsDir $script:pluginsDir `
            -RepoRoot $emptyRepo -Version '1.0.0' -DryRun

        $result.Success | Should -BeTrue
    }
}

Describe 'Write-PluginDirectory - destination artifact naming' {
    BeforeAll {
        $script:namingRepo = Join-Path $TestDrive 'naming-repo'
        $script:namingPluginsDir = Join-Path $script:namingRepo 'plugins'
        New-Item -ItemType Directory -Path $script:namingPluginsDir -Force | Out-Null

        $namingAgentDir = Join-Path $script:namingRepo '.github/agents/team'
        $namingPromptDir = Join-Path $script:namingRepo '.github/prompts/team'
        $namingInstructionDir = Join-Path $script:namingRepo '.github/instructions/team'
        New-Item -ItemType Directory -Path $namingAgentDir -Force | Out-Null
        New-Item -ItemType Directory -Path $namingPromptDir -Force | Out-Null
        New-Item -ItemType Directory -Path $namingInstructionDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:namingRepo 'docs/templates') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:namingRepo 'scripts/lib') -Force | Out-Null

        Set-Content -LiteralPath (Join-Path $namingAgentDir 'example.agent.md') `
            -Value "---`ndescription: An example agent`n---`nAgent body" -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $namingPromptDir 'example.prompt.md') `
            -Value "---`ndescription: An example prompt`n---`nPrompt body" -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $namingInstructionDir 'example.instructions.md') `
            -Value "---`ndescription: An example instruction`n---`nInstruction body" -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $script:namingRepo 'docs/templates/sample.md') `
            -Value 'template' -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $script:namingRepo 'scripts/lib/sample.sh') `
            -Value 'echo lib' -Encoding utf8NoBOM

        # Materialization enumerates git-tracked paths, so the fixture is a repo.
        Push-Location $script:namingRepo
        try {
            git init --quiet 2>$null
            git config user.email 'test@test.com'
            git config user.name 'Test'
            git add -A 2>$null
        }
        finally {
            Pop-Location
        }

        $namingEntry = @{ name = 'naming-test'; description = 'Destination naming coverage' }
        $namingItems = @(
            @{ Kind = 'agent'; Field = 'agents'; PackagePath = 'agents/team/example.md'; SourcePath = '.github/agents/team/example.agent.md' }
            @{ Kind = 'prompt'; Field = 'commands'; PackagePath = 'commands/team/example.md'; SourcePath = '.github/prompts/team/example.prompt.md' }
            @{ Kind = 'instruction'; Field = 'rules'; PackagePath = 'rules/team/example.instructions.md'; SourcePath = '.github/instructions/team/example.instructions.md' }
        )

        $script:namingResult = Write-PluginDirectory -Entry $namingEntry -Items $namingItems `
            -PluginsDir $script:namingPluginsDir -RepoRoot $script:namingRepo -Version '1.0.0'
        $script:namingPluginRoot = Join-Path $script:namingPluginsDir 'naming-test'
    }

    It 'Drops the .agent suffix from the materialized agent' {
        Test-Path -LiteralPath (Join-Path $script:namingPluginRoot 'agents/team/example.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:namingPluginRoot 'agents/team/example.agent.md') | Should -BeFalse
    }

    It 'Drops the .prompt suffix from the materialized command' {
        Test-Path -LiteralPath (Join-Path $script:namingPluginRoot 'commands/team/example.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:namingPluginRoot 'commands/team/example.prompt.md') | Should -BeFalse
    }

    It 'Materializes instructions under rules with the .instructions.md suffix' {
        Test-Path -LiteralPath (Join-Path $script:namingPluginRoot 'rules/team/example.instructions.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:namingPluginRoot 'rules/team/example.md') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:namingPluginRoot 'instructions') | Should -BeFalse
    }

    It 'Emits exactly one root manifest with no legacy location' {
        Test-Path -LiteralPath (Join-Path $script:namingPluginRoot 'plugin.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:namingPluginRoot '.github/plugin/plugin.json') | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:namingPluginRoot -Filter 'plugin.json' -Recurse -File).Count | Should -Be 1
    }

    It 'Declares the rules directory in the root manifest' {
        $manifest = Get-Content -LiteralPath (Join-Path $script:namingPluginRoot 'plugin.json') -Raw | ConvertFrom-Json
        $manifest.rules | Should -Contain 'rules/team/'
        $manifest.PSObject.Properties.Name | Should -Not -Contain 'x-hve'
    }

    It 'Reports the mapped destinations through GeneratedFiles' {
        $generated = @($script:namingResult.GeneratedFiles)
        $generated | Should -Contain (Join-Path $script:namingPluginRoot 'agents/team/example.md')
        $generated | Should -Contain (Join-Path $script:namingPluginRoot 'commands/team/example.md')
        $generated | Should -Contain (Join-Path $script:namingPluginRoot 'rules/team/example.instructions.md')
    }
}

Describe 'Get-PluginTrackedPathIndex' {
    BeforeAll {
        $script:indexRepo = Join-Path $TestDrive 'index-repo'
        New-Item -ItemType Directory -Path $script:indexRepo -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:indexRepo 'tracked.md') -Value 'tracked' -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $script:indexRepo 'untracked.md') -Value 'untracked' -Encoding utf8NoBOM

        Push-Location $script:indexRepo
        try {
            git init --quiet 2>$null
            git config user.email 'test@test.com'
            git config user.name 'Test'
            git add -- tracked.md 2>$null
        }
        finally {
            Pop-Location
        }
    }

    It 'Lists tracked paths with forward slashes' {
        $index = Get-PluginTrackedPathIndex -RepoRoot $script:indexRepo
        $index.Paths | Should -Contain 'tracked.md'
        $index.Lookup.Contains('tracked.md') | Should -BeTrue
    }

    It 'Omits untracked paths' {
        $index = Get-PluginTrackedPathIndex -RepoRoot $script:indexRepo
        $index.Paths | Should -Not -Contain 'untracked.md'
    }

    It 'Throws outside a git working tree' {
        $bareDir = Join-Path $TestDrive 'not-a-repo'
        New-Item -ItemType Directory -Path $bareDir -Force | Out-Null
        { Get-PluginTrackedPathIndex -RepoRoot $bareDir } | Should -Throw '*git-tracked paths*'
    }
}

Describe 'Copy-PluginSource' {
    BeforeAll {
        $script:copyRepo = Join-Path $TestDrive 'copy-repo'
        $script:copyDest = Join-Path $TestDrive 'copy-dest'
        New-Item -ItemType Directory -Path $script:copyDest -Force | Out-Null

        $skillDir = Join-Path $script:copyRepo '.github/skills/team/demo'
        $nestedDir = Join-Path $skillDir 'references/nested'
        $venvDir = Join-Path $skillDir '.venv'
        $agentDir = Join-Path $script:copyRepo '.github/agents/team'
        New-Item -ItemType Directory -Path $nestedDir -Force | Out-Null
        New-Item -ItemType Directory -Path $venvDir -Force | Out-Null
        New-Item -ItemType Directory -Path $agentDir -Force | Out-Null

        Set-Content -LiteralPath (Join-Path $skillDir 'SKILL.md') -Value 'skill body' -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $nestedDir 'deep.md') -Value 'deep tracked fixture' -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $agentDir 'solo.agent.md') -Value 'agent body' -Encoding utf8NoBOM

        Push-Location $script:copyRepo
        try {
            git init --quiet 2>$null
            git config user.email 'test@test.com'
            git config user.name 'Test'
            git add -A 2>$null
        }
        finally {
            Pop-Location
        }

        # Untracked residue written after staging so it is never in the index.
        Set-Content -LiteralPath (Join-Path $skillDir 'untracked-sentinel.md') -Value 'sentinel' -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $venvDir 'pyvenv.cfg') -Value 'home = /usr' -Encoding utf8NoBOM

        $script:copyIndex = Get-PluginTrackedPathIndex -RepoRoot $script:copyRepo
        $script:copySkillSource = $skillDir
        $script:copyAgentSource = Join-Path $agentDir 'solo.agent.md'
    }

    Context 'When the source is a directory' {
        BeforeAll {
            $script:skillDest = Join-Path $script:copyDest 'skills/team/demo'
            $script:skillWritten = @(Copy-PluginSource -SourcePath $script:copySkillSource `
                    -DestinationPath $script:skillDest -RepoRoot $script:copyRepo -TrackedIndex $script:copyIndex)
        }

        It 'Reconstructs the tracked directory tree' {
            Test-Path -LiteralPath (Join-Path $script:skillDest 'SKILL.md') | Should -BeTrue
        }

        It 'Copies a tracked nested fixture byte-for-byte' {
            $destination = Join-Path $script:skillDest 'references/nested/deep.md'
            Test-Path -LiteralPath $destination | Should -BeTrue
            $sourceHash = (Get-FileHash -LiteralPath (Join-Path $script:copySkillSource 'references/nested/deep.md') -Algorithm SHA256).Hash
            (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash | Should -Be $sourceHash
        }

        It 'Excludes an untracked sentinel in the same source directory' {
            Test-Path -LiteralPath (Join-Path $script:skillDest 'untracked-sentinel.md') | Should -BeFalse
        }

        It 'Excludes untracked development residue' {
            Test-Path -LiteralPath (Join-Path $script:skillDest '.venv') | Should -BeFalse
        }

        It 'Creates only regular files and real directories' {
            $links = @(Get-ChildItem -LiteralPath $script:skillDest -Recurse -Force | Where-Object { $_.LinkType })
            $links.Count | Should -Be 0
        }

        It 'Returns every materialized destination for orphan bookkeeping' {
            $script:skillWritten.Count | Should -Be 2
            $script:skillWritten | Should -Contain (Join-Path $script:skillDest 'SKILL.md')
            $script:skillWritten | Should -Contain ([System.IO.Path]::GetFullPath((Join-Path $script:skillDest 'references/nested/deep.md')))
        }
    }

    Context 'When the source is a file' {
        It 'Writes exactly the requested destination path' {
            $destination = Join-Path $script:copyDest 'agents/team/solo.md'
            $written = @(Copy-PluginSource -SourcePath $script:copyAgentSource `
                    -DestinationPath $destination -RepoRoot $script:copyRepo -TrackedIndex $script:copyIndex)
            $written | Should -Be @($destination)
            Get-Content -LiteralPath $destination -Raw | Should -Match 'agent body'
        }

        It 'Copies current working-tree bytes for a modified tracked file' {
            $destination = Join-Path $script:copyDest 'agents/team/modified.md'
            Set-Content -LiteralPath $script:copyAgentSource -Value 'agent body modified' -Encoding utf8NoBOM
            Copy-PluginSource -SourcePath $script:copyAgentSource -DestinationPath $destination `
                -RepoRoot $script:copyRepo -TrackedIndex $script:copyIndex | Out-Null
            Get-Content -LiteralPath $destination -Raw | Should -Match 'agent body modified'
        }

    }

    Context 'When the source is not eligible' {
        It 'Warns and copies nothing for an untracked source' {
            $untracked = Join-Path $script:copySkillSource 'untracked-sentinel.md'
            $destination = Join-Path $script:copyDest 'agents/team/sentinel.md'
            $written = @(Copy-PluginSource -SourcePath $untracked -DestinationPath $destination `
                    -RepoRoot $script:copyRepo -TrackedIndex $script:copyIndex -WarningAction SilentlyContinue)
            $written.Count | Should -Be 0
            Test-Path -LiteralPath $destination | Should -BeFalse
        }

        It 'Throws when the source resolves outside the repository root' {
            $outside = Join-Path $TestDrive 'outside.md'
            Set-Content -LiteralPath $outside -Value 'outside' -Encoding utf8NoBOM
            {
                Copy-PluginSource -SourcePath $outside -DestinationPath (Join-Path $script:copyDest 'outside.md') `
                    -RepoRoot $script:copyRepo -TrackedIndex $script:copyIndex
            } | Should -Throw '*outside the repository root*'
        }
    }
}

Describe 'Get-PluginItemName - hook kind' {
    It 'Returns the filename unchanged for a hook' {
        Get-PluginItemName -FileName 'telemetry.json' -Kind 'hook' | Should -Be 'telemetry.json'
    }
}

Describe 'Get-PluginItemSubpath - hook kind' {
    It 'Strips the .github/hooks prefix and returns the collection subpath' {
        $result = Get-PluginItemSubpath -Path '.github/hooks/shared/telemetry.json' -Kind 'hook'
        $result | Should -Be 'shared'
    }

    It 'Returns the nested subpath for deeper hook layouts' {
        $result = Get-PluginItemSubpath -Path '.github/hooks/shared/telemetry/config.json' -Kind 'hook'
        $result | Should -Be 'shared/telemetry'
    }

    It 'Returns empty string for a hook directly under the kind root' {
        $result = Get-PluginItemSubpath -Path '.github/hooks/telemetry.json' -Kind 'hook'
        $result | Should -Be ''
    }
}

Describe 'Get-PluginSubdirectory - hook kind' {
    It 'Returns hooks for the hook kind' {
        Get-PluginSubdirectory -Kind 'hook' | Should -Be 'hooks'
    }
}

Describe 'New-PluginManifestContent - hook paths' {
    It 'Emits a single hooks string for one hook path' {
        $manifest = New-PluginManifestContent -PackageName 'shared' -Description 'desc' -Version '1.0.0' -HookPaths @('hooks/shared/telemetry.json')
        $manifest['hooks'] | Should -BeOfType [string]
        $manifest['hooks'] | Should -Be 'hooks/shared/telemetry.json'
    }

    It 'Uses the first sorted hook path and warns when multiple are declared' {
        $warnings = $null
        $manifest = New-PluginManifestContent -PackageName 'shared' -Description 'desc' -Version '1.0.0' `
            -HookPaths @('hooks/shared/zeta.json', 'hooks/shared/alpha.json') -WarningVariable warnings -WarningAction SilentlyContinue
        $manifest['hooks'] | Should -Be 'hooks/shared/alpha.json'
        $warnings | Should -Not -BeNullOrEmpty
        ($warnings -join "`n") | Should -Match 'references only one'
    }

    It 'Omits the hooks key when no hook paths are provided' {
        $manifest = New-PluginManifestContent -PackageName 'shared' -Description 'desc' -Version '1.0.0'
        $manifest.Contains('hooks') | Should -BeFalse
    }
}

Describe 'New-PluginReleaseLocator' {
    It 'Derives the immutable tag from a package version' {
        $locator = New-PluginReleaseLocator -Version '1.2.3'
        $locator.Repo | Should -Be 'microsoft/hve-core'
        $locator.Ref | Should -Be 'plugins-v1.2.3'
        $locator.PathPrefix | Should -Be 'plugins'
    }

    It 'Accepts an explicit immutable tag' {
        (New-PluginReleaseLocator -Tag 'plugins-v0.9.0-beta.1').Ref | Should -Be 'plugins-v0.9.0-beta.1'
    }

    It 'Accepts an explicit repository and path prefix' {
        $locator = New-PluginReleaseLocator -Tag 'plugins-v1.2.3' -Repo 'contoso/fork' -PathPrefix '/packages/'
        $locator.Repo | Should -Be 'contoso/fork'
        $locator.PathPrefix | Should -Be 'packages'
    }

    It 'Rejects a full commit sha' {
        { New-PluginReleaseLocator -Tag '0123456789abcdef0123456789abcdef01234567' } |
            Should -Throw '*Sha-pinned catalog sources are not supported*'
    }

    It 'Rejects a release-please style tag' {
        { New-PluginReleaseLocator -Tag 'v1.2.3' } | Should -Throw "*must use the immutable 'plugins-v<version>' tag form*"
    }

    It 'Rejects a moving branch name' {
        { New-PluginReleaseLocator -Tag 'release/plugins' } | Should -Throw "*must use the immutable 'plugins-v<version>' tag form*"
    }

    It 'Rejects a non-semantic version' {
        { New-PluginReleaseLocator -Version '1.2' } | Should -Throw '*is not a semantic version*'
    }

    It 'Rejects a malformed repository locator' {
        { New-PluginReleaseLocator -Tag 'plugins-v1.2.3' -Repo 'hve-core' } | Should -Throw "*must use 'owner/name' form*"
    }

    It 'Rejects an escaping path prefix' {
        { New-PluginReleaseLocator -Tag 'plugins-v1.2.3' -PathPrefix '../plugins' } |
            Should -Throw '*must be a relative forward-slash path inside the repository*'
    }
}

Describe 'New-MarketplaceManifestContent - source forms' {
    BeforeAll {
        $script:plugins = @(
            [ordered]@{
                name = 'rpi'; source = [ordered]@{
                    source = 'github'; repo = 'microsoft/hve-core'; path = 'plugins/rpi'; ref = 'plugins-v1.2.3'
                }; description = 'RPI'; version = '1.2.3'
            }
            [ordered]@{
                name = 'security'; source = [ordered]@{
                    source = 'github'; repo = 'microsoft/hve-core'; path = 'plugins/security'; ref = 'plugins-v1.2.3'
                }; description = 'Security'; version = '1.2.3'
            }
        )
    }

    It 'Preserves immutable object sources when no locator is supplied' {
        $manifest = New-MarketplaceManifestContent -RepoName 'hve-core' -Description 'd' -Version '1.2.3' `
            -OwnerName 'Microsoft' -Plugins $script:plugins

        $manifest.plugins[0].source.ref | Should -Be 'plugins-v1.2.3'
        $manifest.plugins[0].source.path | Should -Be 'plugins/rpi'
        $manifest.plugins[1].source.path | Should -Be 'plugins/security'
    }

    It 'Rejects a bare source when no locator is supplied' {
        $plugins = @([ordered]@{ name = 'rpi'; source = 'rpi'; description = 'RPI'; version = '1.2.3' })

        { New-MarketplaceManifestContent -RepoName 'hve-core' -Description 'd' -Version '1.2.3' `
                -OwnerName 'Microsoft' -Plugins $plugins } |
            Should -Throw '*Bare package sources are not supported*'
    }

    It 'Preserves standard membership and the x-hve overlay' {
        $entries = @(
            [ordered]@{
                name        = 'rpi'
                source      = [ordered]@{
                    source = 'github'; repo = 'microsoft/hve-core'; path = 'plugins/rpi'; ref = 'plugins-v1.2.3'
                }
                description = 'RPI'
                version     = '1.2.3'
                skills      = @('skills/rpi/rpi-plan')
                'x-hve'     = [ordered]@{ documentation = 'docs/plugins/rpi.md' }
            }
        )

        $manifest = New-MarketplaceManifestContent -RepoName 'hve-core' -Description 'd' -Version '1.2.3' `
            -OwnerName 'Microsoft' -Plugins $entries

        $manifest.plugins[0].skills | Should -Be @('skills/rpi/rpi-plan')
        $manifest.plugins[0].'x-hve'.documentation | Should -Be 'docs/plugins/rpi.md'
    }

    It 'Emits tag-pinned object sources when a locator is supplied' {
        $manifest = New-MarketplaceManifestContent -RepoName 'hve-core' -Description 'd' -Version '1.2.3' `
            -OwnerName 'Microsoft' -Plugins $script:plugins `
            -ReleaseLocator (New-PluginReleaseLocator -Version '1.2.3')

        $manifest.plugins[0].source.source | Should -Be 'github'
        $manifest.plugins[0].source.repo | Should -Be 'microsoft/hve-core'
        $manifest.plugins[0].source.path | Should -Be 'plugins/rpi'
        $manifest.plugins[0].source.ref | Should -Be 'plugins-v1.2.3'
        $manifest.plugins[1].source.path | Should -Be 'plugins/security'
        $manifest.plugins[0].source.Contains('sha') | Should -BeFalse
    }

    It 'Keeps entry name and version unchanged in locator mode' {
        $manifest = New-MarketplaceManifestContent -RepoName 'hve-core' -Description 'd' -Version '1.2.3' `
            -OwnerName 'Microsoft' -Plugins $script:plugins `
            -ReleaseLocator (New-PluginReleaseLocator -Version '1.2.3')

        $manifest.plugins[0].name | Should -Be 'rpi'
        $manifest.plugins[0].version | Should -Be '1.2.3'
        $manifest.metadata.version | Should -Be '1.2.3'
    }
}

Describe 'Write-MarketplaceManifest - catalog projection' {
    BeforeAll {
        $script:repoRoot = Join-Path $TestDrive 'marketplace-repo'
        New-Item -ItemType Directory -Path $script:repoRoot -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:repoRoot '.github/plugin') -Force | Out-Null
        Set-Content -Path (Join-Path $script:repoRoot 'package.json') `
            -Value '{"name":"hve-core","description":"d","version":"1.2.3","author":"Microsoft"}'
        Set-Content -Path (Join-Path $script:repoRoot '.github/plugin/marketplace.json') -Value '{"sentinel":true}'
        $script:catalog = @{
            plugins = @(
                [ordered]@{
                    name = 'rpi'; source = [ordered]@{
                        source = 'github'; repo = 'microsoft/hve-core'; path = 'plugins/rpi'; ref = 'plugins-v1.2.3'
                    }; description = 'RPI'; version = '1.2.3'
                }
                [ordered]@{
                    name = 'security'; source = [ordered]@{
                        source = 'github'; repo = 'microsoft/hve-core'; path = 'plugins/security'; ref = 'plugins-v1.2.3'
                    }; description = 'Security'; version = '1.2.3'
                }
            )
        }
        Mock Write-Host {}
    }

    It 'Writes an immutable catalog projection to an explicit output path' {
        $outputPath = Join-Path $TestDrive 'plain/marketplace.json'
        Write-MarketplaceManifest -RepoRoot $script:repoRoot -Catalog $script:catalog -OutputPath $outputPath
        $manifest = Get-Content -Path $outputPath -Raw | ConvertFrom-Json
        $manifest.plugins[0].source.ref | Should -Be 'plugins-v1.2.3'
        $manifest.plugins[0].source.path | Should -Be 'plugins/rpi'
    }

    It 'Writes tag-pinned object sources to an explicit output path' {
        $outputPath = Join-Path $TestDrive 'snapshot/marketplace.json'
        Write-MarketplaceManifest -RepoRoot $script:repoRoot -Catalog $script:catalog `
            -ReleaseLocator (New-PluginReleaseLocator -Version '1.2.3') -OutputPath $outputPath

        $manifest = Get-Content -Path $outputPath -Raw | ConvertFrom-Json
        $manifest.plugins[0].source.repo | Should -Be 'microsoft/hve-core'
        $manifest.plugins[0].source.ref | Should -Be 'plugins-v1.2.3'
        $manifest.plugins[0].source.path | Should -Be 'plugins/rpi'
    }

    It 'Refuses any projection targeting the production catalog' {
        { Write-MarketplaceManifest -RepoRoot $script:repoRoot -Catalog $script:catalog `
                -OutputPath '.github/plugin/marketplace.json' } |
            Should -Throw '*must not write the production catalog*'
    }

    It 'Refuses locator mode targeting the production catalog' {
        { Write-MarketplaceManifest -RepoRoot $script:repoRoot -Catalog $script:catalog `
                -ReleaseLocator (New-PluginReleaseLocator -Version '1.2.3') `
                -OutputPath '.github/plugin/marketplace.json' } |
            Should -Throw '*must not write the production catalog*'
    }

    It 'Leaves the production catalog untouched after a refused write' {
        Set-Content -Path (Join-Path $script:repoRoot '.github/plugin/marketplace.json') -Value '{"sentinel":true}'
        { Write-MarketplaceManifest -RepoRoot $script:repoRoot -Catalog $script:catalog `
                -ReleaseLocator (New-PluginReleaseLocator -Version '1.2.3') `
                -OutputPath '.github/plugin/marketplace.json' } | Should -Throw

        (Get-Content -Path (Join-Path $script:repoRoot '.github/plugin/marketplace.json') -Raw).Trim() |
            Should -Be '{"sentinel":true}'
    }
}

Describe 'Assert-PluginSnapshotTarget' {
    It 'Accepts disposable branch and tag targets' {
        $target = Assert-PluginSnapshotTarget -Branch 'plugins-snapshot/run-42' -Tag 'plugins-snapshot/run-42-tag'
        $target.Branch | Should -Be 'plugins-snapshot/run-42'
        $target.Tag | Should -Be 'plugins-snapshot/run-42-tag'
        $target.RefSpecs | Should -Contain 'HEAD:refs/heads/plugins-snapshot/run-42'
        $target.RefSpecs | Should -Contain 'refs/tags/plugins-snapshot/run-42-tag'
    }

    It 'Refuses the moving release branch' {
        { Assert-PluginSnapshotTarget -Branch 'release/plugins' -Tag 'plugins-snapshot/run-42-tag' } |
            Should -Throw '*targets a protected production reference*'
    }

    It 'Refuses the default branch' {
        { Assert-PluginSnapshotTarget -Branch 'main' -Tag 'plugins-snapshot/run-42-tag' } |
            Should -Throw '*targets a protected production reference*'
    }

    It 'Refuses a production version tag' {
        { Assert-PluginSnapshotTarget -Branch 'plugins-snapshot/run-42' -Tag 'plugins-v1.2.3' } |
            Should -Throw '*targets a protected production reference*'
    }

    It 'Refuses a target outside the disposable prefix' {
        { Assert-PluginSnapshotTarget -Branch 'feature/publish' -Tag 'plugins-snapshot/run-42-tag' } |
            Should -Throw "*must start with the disposable prefix 'plugins-snapshot/'*"
    }

    It 'Refuses overwriting an existing tag' {
        { Assert-PluginSnapshotTarget -Branch 'plugins-snapshot/run-42' -Tag 'plugins-snapshot/run-42-tag' `
                -ExistingRefs @('refs/tags/plugins-snapshot/run-42-tag') } |
            Should -Throw '*Tags are immutable and are never overwritten*'
    }

    It 'Refuses overwriting an existing short-form tag' {
        { Assert-PluginSnapshotTarget -Branch 'plugins-snapshot/run-42' -Tag 'plugins-snapshot/run-42-tag' `
                -ExistingRefs @('plugins-snapshot/run-42-tag') } |
            Should -Throw '*Tags are immutable and are never overwritten*'
    }

    It 'Allows a tag when only other tags exist' {
        { Assert-PluginSnapshotTarget -Branch 'plugins-snapshot/run-42' -Tag 'plugins-snapshot/run-42-tag' `
                -ExistingRefs @('refs/tags/plugins-v1.2.3', 'refs/tags/plugins-snapshot/run-41-tag') } |
            Should -Not -Throw
    }

    It 'Refuses identical branch and tag names' {
        { Assert-PluginSnapshotTarget -Branch 'plugins-snapshot/run-42' -Tag 'plugins-snapshot/run-42' } |
            Should -Throw '*must differ*'
    }

    It 'Refuses malformed reference names <Value>' -ForEach @(
        @{ Value = '' }
        @{ Value = 'plugins-snapshot/../escape' }
        @{ Value = 'plugins-snapshot/has space' }
        @{ Value = 'plugins-snapshot/tilde~1' }
        @{ Value = 'plugins-snapshot/run.lock' }
        @{ Value = 'plugins-snapshot/' }
    ) {
        { Assert-PluginSnapshotTarget -Branch $Value -Tag 'plugins-snapshot/run-42-tag' } |
            Should -Throw '*is not a valid git reference name*'
    }
}

Describe 'Get-MarketplaceComponentFieldMap' {
    It 'Maps every standard component field to its artifact kind' {
        $map = Get-MarketplaceComponentFieldMap
        @($map.Keys) | Should -Be @('agents', 'commands', 'rules', 'skills', 'hooks')
        $map['commands'] | Should -Be 'prompt'
        $map['rules'] | Should -Be 'instruction'
    }

    It 'Covers the same artifact kinds as plugin subdirectory mapping' {
        $map = Get-MarketplaceComponentFieldMap
        foreach ($kind in $map.Values) {
            { Get-PluginSubdirectory -Kind $kind } | Should -Not -Throw
        }
    }
}

Describe 'Get-MarketplaceMetadataKey' {
    It 'Closes the x-hve overlay to entry-level metadata keys' {
        $keys = Get-MarketplaceMetadataKey
        $keys | Should -Be @('maturity', 'componentMaturity', 'documentation', 'aggregate')
    }

    It 'Excludes every standard component membership field' {
        $metadataKeys = Get-MarketplaceMetadataKey
        foreach ($field in (Get-MarketplaceComponentFieldMap).Keys) {
            $metadataKeys | Should -Not -Contain $field
        }
    }
}

Describe 'Resolve-MarketplaceComponentPath' {
    It 'Returns the normalized path for a package-relative file path' {
        $result = Resolve-MarketplaceComponentPath -Path 'commands/rpi/rpi-research.md'
        $result.Error | Should -BeNullOrEmpty
        $result.Path | Should -Be 'commands/rpi/rpi-research.md'
    }

    It 'Normalizes a trailing directory separator' {
        $result = Resolve-MarketplaceComponentPath -Path 'skills/rpi/'
        $result.Error | Should -BeNullOrEmpty
        $result.Path | Should -Be 'skills/rpi'
    }

    It 'Returns error for an empty path' {
        (Resolve-MarketplaceComponentPath -Path '  ').Error | Should -BeLike '*must be a non-empty string*'
    }

    It 'Returns error for a backslash path' {
        (Resolve-MarketplaceComponentPath -Path 'commands\rpi.md').Error | Should -BeLike '*must use forward slashes*'
    }

    It 'Returns error for an absolute POSIX path' {
        (Resolve-MarketplaceComponentPath -Path '/commands/rpi.md').Error | Should -BeLike '*must be relative to the package root*'
    }

    It 'Returns error for an absolute Windows path' {
        (Resolve-MarketplaceComponentPath -Path 'C:/commands/rpi.md').Error | Should -BeLike '*must be relative to the package root*'
    }

    It 'Returns error for an escaping path' {
        (Resolve-MarketplaceComponentPath -Path '../secrets/key.md').Error | Should -BeLike '*must not escape the package root*'
    }

    It 'Returns error for an embedded escaping segment' {
        (Resolve-MarketplaceComponentPath -Path 'commands/../../secrets').Error | Should -BeLike '*must not escape the package root*'
    }

    It 'Returns error for a relative path segment' {
        (Resolve-MarketplaceComponentPath -Path './commands/rpi.md').Error | Should -BeLike '*must not contain relative path segments*'
    }

    It 'Returns error for an empty path segment' {
        (Resolve-MarketplaceComponentPath -Path 'commands//rpi.md').Error | Should -BeLike '*must not contain empty path segments*'
    }

    It 'Returns error for a control character' {
        (Resolve-MarketplaceComponentPath -Path "commands/rpi`t.md").Error | Should -BeLike '*must not contain control characters*'
    }
}

Describe 'Test-MarketplaceEntryContract - standard component fields' {
    It 'Accepts declared membership across every standard field' {
        $result = Test-MarketplaceEntryContract -Entry ([ordered]@{
                name     = 'sample'
                agents   = @('agents/rpi-planner.md')
                commands = @('commands/rpi-research.md')
                rules    = @('instructions/markdown.instructions.md')
                skills   = @('skills/rpi-plan')
                hooks    = 'hooks/hve-core.json'
            })
        $result | Should -BeNullOrEmpty
    }

    It 'Accepts a single path string for an array-capable field' {
        $result = Test-MarketplaceEntryContract -Entry ([ordered]@{ name = 'sample'; commands = 'commands/rpi-research.md' })
        $result | Should -BeNullOrEmpty
    }

    It 'Returns error for a malformed component path' {
        $result = Test-MarketplaceEntryContract -Entry ([ordered]@{ name = 'sample'; agents = @('/agents/rpi.md') })
        @($result)[0] | Should -BeLike "*component field 'agents'*must be relative to the package root*"
    }

    It 'Returns error for a duplicate path within one field' {
        $result = Test-MarketplaceEntryContract -Entry ([ordered]@{
                name     = 'sample'
                commands = @('commands/rpi-research.md', 'commands/rpi-research.md')
            })
        $result | Should -Contain "component field 'commands' declares duplicate path 'commands/rpi-research.md'"
    }

    It 'Treats a trailing-separator variant as the same declared path' {
        $result = Test-MarketplaceEntryContract -Entry ([ordered]@{ name = 'sample'; skills = @('skills/rpi-plan', 'skills/rpi-plan/') })
        $result | Should -Contain "component field 'skills' declares duplicate path 'skills/rpi-plan'"
    }

    It 'Returns error for cross-kind duplicate membership' {
        $result = Test-MarketplaceEntryContract -Entry ([ordered]@{
                name     = 'sample'
                commands = @('commands/rpi-research.md')
                rules    = @('commands/rpi-research.md')
            })
        $result | Should -Contain "component path 'commands/rpi-research.md' is declared in both 'commands' and 'rules'"
    }

    It 'Returns error for a non-string membership element' {
        $result = Test-MarketplaceEntryContract -Entry ([ordered]@{ name = 'sample'; skills = @(42) })
        $result | Should -Contain "component field 'skills' must contain only path strings"
    }

    It 'Rejects an array-valued hooks field' {
        $result = Test-MarketplaceEntryContract -Entry ([ordered]@{ name = 'sample'; hooks = @('hooks/a.json') })
        $result | Should -Contain "component field 'hooks' must be a single path string"
    }

    It 'Returns error for an empty membership array' {
        $result = Test-MarketplaceEntryContract -Entry ([ordered]@{ name = 'sample'; agents = @() })
        $result | Should -Contain "component field 'agents' must declare at least one path"
    }
}

Describe 'Test-MarketplaceEntryContract - x-hve overlay' {
    It 'Accepts a metadata-only overlay' {
        $result = Test-MarketplaceEntryContract -Entry ([ordered]@{
                name     = 'sample'
                commands = @('commands/rpi-research.md')
                'x-hve'  = [ordered]@{
                    maturity          = 'preview'
                    componentMaturity = [ordered]@{ 'commands/rpi-research.md' = 'experimental' }
                    documentation     = 'docs/plugins/sample.md'
                    aggregate         = $false
                }
            })
        $result | Should -BeNullOrEmpty
    }

    It 'Returns error when the overlay is not an object' {
        Test-MarketplaceEntryContract -Entry ([ordered]@{ name = 'sample'; 'x-hve' = 'stable' }) |
            Should -Contain 'x-hve must be an object'
    }

    It 'Returns error for any membership-owning key' -ForEach @(
        @{ Key = 'instructions' }
        @{ Key = 'artifacts' }
        @{ Key = 'items' }
        @{ Key = 'agents' }
    ) {
        $overlay = [ordered]@{ maturity = 'stable' }
        $overlay[$Key] = @('instructions/markdown.instructions.md')
        Test-MarketplaceEntryContract -Entry ([ordered]@{ name = 'sample'; 'x-hve' = $overlay }) |
            Should -Contain "x-hve contains unsupported key '$Key'"
    }

    It 'Returns error for an unsupported maturity value' {
        $result = Test-MarketplaceEntryContract -Entry ([ordered]@{ name = 'sample'; 'x-hve' = [ordered]@{ maturity = 'retired' } })
        @($result)[0] | Should -BeLike "*x-hve.maturity 'retired' must be one of*"
    }

    It 'Accepts every maturity value in the repository vocabulary' -ForEach @(
        @{ Maturity = 'stable' }
        @{ Maturity = 'preview' }
        @{ Maturity = 'experimental' }
        @{ Maturity = 'deprecated' }
        @{ Maturity = 'removed' }
    ) {
        Test-MarketplaceEntryContract -Entry ([ordered]@{ name = 'sample'; 'x-hve' = [ordered]@{ maturity = $Maturity } }) |
            Should -BeNullOrEmpty
    }

    It 'Accepts a removed tombstone that is absent from active membership' {
        $result = Test-MarketplaceEntryContract -Entry ([ordered]@{
                name     = 'sample'
                commands = @('commands/rpi-research.md')
                'x-hve'  = [ordered]@{
                    componentMaturity = [ordered]@{ 'commands/retired-command.md' = 'removed' }
                }
            })
        $result | Should -BeNullOrEmpty
    }

    It 'Returns error for a non-normalized componentMaturity key' {
        $result = Test-MarketplaceEntryContract -Entry ([ordered]@{
                name    = 'sample'
                'x-hve' = [ordered]@{ componentMaturity = [ordered]@{ 'skills/rpi-plan/' = 'preview' } }
            })
        $result | Should -Contain "x-hve.componentMaturity key 'skills/rpi-plan/' must be a normalized component path"
    }

    It 'Returns error for a malformed componentMaturity key' {
        $result = Test-MarketplaceEntryContract -Entry ([ordered]@{
                name    = 'sample'
                'x-hve' = [ordered]@{ componentMaturity = [ordered]@{ '../escape.md' = 'preview' } }
            })
        @($result)[0] | Should -BeLike '*x-hve.componentMaturity*must not escape the package root*'
    }

    It 'Returns error for an unsupported componentMaturity value' {
        $result = Test-MarketplaceEntryContract -Entry ([ordered]@{
                name    = 'sample'
                'x-hve' = [ordered]@{ componentMaturity = [ordered]@{ 'commands/rpi-research.md' = 'retired' } }
            })
        @($result)[0] | Should -Match "x-hve\.componentMaturity\['commands/rpi-research\.md'\] value 'retired' must be one of"
    }

    It 'Returns error for a componentMaturity map that is not an object' {
        Test-MarketplaceEntryContract -Entry ([ordered]@{ name = 'sample'; 'x-hve' = [ordered]@{ componentMaturity = @('a') } }) |
            Should -Contain 'x-hve.componentMaturity must be an object keyed by component path'
    }

    It 'Returns error for an escaping documentation path' {
        $result = Test-MarketplaceEntryContract -Entry ([ordered]@{
                name    = 'sample'
                'x-hve' = [ordered]@{ documentation = '../../etc/passwd' }
            })
        @($result)[0] | Should -BeLike '*x-hve.documentation*must not escape the package root*'
    }

    It 'Returns error for a non-string documentation value' {
        Test-MarketplaceEntryContract -Entry ([ordered]@{ name = 'sample'; 'x-hve' = [ordered]@{ documentation = 3 } }) |
            Should -Contain 'x-hve.documentation must be a repository-relative path string'
    }

    It 'Returns error for a non-boolean aggregate value' {
        Test-MarketplaceEntryContract -Entry ([ordered]@{ name = 'sample'; 'x-hve' = [ordered]@{ aggregate = 'true' } }) |
            Should -Contain 'x-hve.aggregate must be a boolean'
    }

}

Describe 'New-PluginManifestContent - x-hve containment' {
    It 'Never emits x-hve or any metadata overlay key into a root manifest' {
        $manifest = New-PluginManifestContent -PackageName 'sample' -Description 'Sample' -Version '1.0.0' `
            -AgentPaths @('agents') -CommandPaths @('commands') -SkillPaths @('skills') -HookPaths @('hooks/sample.json')

        $manifest.Keys | Should -Not -Contain 'x-hve'
        foreach ($metadataKey in (Get-MarketplaceMetadataKey)) {
            $manifest.Keys | Should -Not -Contain $metadataKey
        }
    }

    It 'Serializes without any x-hve token' {
        $manifest = New-PluginManifestContent -PackageName 'sample' -Description 'Sample' -Version '1.0.0' -CommandPaths @('commands')
        ($manifest | ConvertTo-Json -Depth 6) | Should -Not -Match 'x-hve'
    }

    It 'Emits provenance and rules membership from the catalog entry' {
        $manifest = New-PluginManifestContent -PackageName 'sample' -Description 'Sample' -Version '1.0.0' `
            -Author ([ordered]@{ name = 'Microsoft'; url = 'https://www.microsoft.com' }) `
            -Homepage 'https://example.invalid' -Repository 'https://example.invalid' `
            -License 'MIT' -Keywords @('a', 'b') -RulePaths @('rules/team/')

        $manifest.author.name | Should -Be 'Microsoft'
        $manifest.author.url | Should -Be 'https://www.microsoft.com'
        $manifest.homepage | Should -Be 'https://example.invalid'
        $manifest.repository | Should -Be 'https://example.invalid'
        $manifest.license | Should -Be 'MIT'
        $manifest.keywords | Should -Be @('a', 'b')
        $manifest.rules | Should -Be @('rules/team/')
    }
}

Describe 'Get-MarketplacePackagePath and Resolve-MarketplaceComponentSource' {
    It 'Round-trips every component kind' {
        $cases = @(
            @{ Kind = 'agent'; Source = '.github/agents/team/x.agent.md'; Package = 'agents/team/x.md'; Field = 'agents' }
            @{ Kind = 'prompt'; Source = '.github/prompts/team/x.prompt.md'; Package = 'commands/team/x.md'; Field = 'commands' }
            @{ Kind = 'instruction'; Source = '.github/instructions/team/x.instructions.md'; Package = 'rules/team/x.instructions.md'; Field = 'rules' }
            @{ Kind = 'skill'; Source = '.github/skills/team/demo'; Package = 'skills/team/demo'; Field = 'skills' }
            @{ Kind = 'hook'; Source = '.github/hooks/team/h.json'; Package = 'hooks/team/h.json'; Field = 'hooks' }
        )

        foreach ($case in $cases) {
            (Get-MarketplacePackagePath -SourcePath $case.Source -Kind $case.Kind) | Should -Be $case.Package
            $resolved = Resolve-MarketplaceComponentSource -PackagePath $case.Package -Field $case.Field
            $resolved.SourcePath | Should -Be $case.Source
            $resolved.Kind | Should -Be $case.Kind
        }
    }

    It 'Rejects a source outside the canonical kind root' {
        { Get-MarketplacePackagePath -SourcePath '.github/skills/team/demo/refs/x.instructions.md' -Kind 'instruction' } |
            Should -Throw '*is not under the canonical*'
    }

    It 'Rejects a component path that escapes the package root' {
        { Resolve-MarketplaceComponentSource -PackagePath 'agents/../../etc/passwd' -Field 'agents' } |
            Should -Throw '*must not escape the package root*'
    }

    It 'Rejects a component path declared under the wrong field directory' {
        { Resolve-MarketplaceComponentSource -PackagePath 'commands/team/x.md' -Field 'agents' } |
            Should -Throw "*must start with the 'agents/' package directory*"
    }

    It 'Rejects a rules path without the instructions suffix' {
        { Resolve-MarketplaceComponentSource -PackagePath 'rules/team/x.md' -Field 'rules' } |
            Should -Throw "*must end with '.instructions.md'*"
    }
}

Describe 'ConvertTo-MarketplaceAgentKey' {
    It 'Normalizes a display name to its file stem form' {
        ConvertTo-MarketplaceAgentKey -Name 'ADR Creation' | Should -Be 'adr-creation'
        ConvertTo-MarketplaceAgentKey -Name 'RPI Agent' | Should -Be 'rpi-agent'
        ConvertTo-MarketplaceAgentKey -Name 'adr-creation' | Should -Be 'adr-creation'
    }
}

Describe 'Expand-MarketplaceAgentDependency' {
    BeforeAll {
        $script:depRepo = Join-Path $TestDrive 'dep-repo'
        $agentsDir = Join-Path $script:depRepo '.github/agents/team'
        New-Item -ItemType Directory -Path $agentsDir -Force | Out-Null

        Set-Content -LiteralPath (Join-Path $agentsDir 'root.agent.md') -Encoding utf8NoBOM -Value @'
---
name: Root Agent
handoffs:
  - agent: Leaf Worker
---
'@
        Set-Content -LiteralPath (Join-Path $agentsDir 'leaf-worker.agent.md') -Encoding utf8NoBOM -Value @'
---
name: Leaf Worker
handoffs:
  - agent: Deep Worker
---
'@
        Set-Content -LiteralPath (Join-Path $agentsDir 'deep-worker.agent.md') -Encoding utf8NoBOM -Value @'
---
name: Deep Worker
---
'@
        Set-Content -LiteralPath (Join-Path $agentsDir 'dangling.agent.md') -Encoding utf8NoBOM -Value @'
---
name: Dangling Agent
handoffs:
  - agent: Never Declared
---
'@

        $script:depCatalog = @{
            plugins = @(
                @{
                    name   = 'all'
                    agents = @(
                        'agents/team/root.md',
                        'agents/team/leaf-worker.md',
                        'agents/team/deep-worker.md',
                        'agents/team/dangling.md'
                    )
                }
            )
        }
        $script:depIndex = Get-MarketplaceAgentIndex -Catalog $script:depCatalog -RepoRoot $script:depRepo
    }

    It 'Indexes declared agents by file stem and display name' {
        $script:depIndex.Lookup.ContainsKey('root') | Should -BeTrue
        $script:depIndex.Lookup.ContainsKey('root-agent') | Should -BeTrue
        $script:depIndex.Ambiguous.Count | Should -Be 0
    }

    It 'Closes transitive handoff dependencies and collapses duplicates' {
        $closed = @(Expand-MarketplaceAgentDependency -Index $script:depIndex `
                -SeedPackagePaths @('agents/team/root.md') -PackageName 'all')
        $closed | Should -Be @('agents/team/deep-worker.md', 'agents/team/leaf-worker.md', 'agents/team/root.md')
    }

    It 'Returns only the seeds when no handoffs are declared' {
        $closed = @(Expand-MarketplaceAgentDependency -Index $script:depIndex `
                -SeedPackagePaths @('agents/team/deep-worker.md') -PackageName 'all')
        $closed | Should -Be @('agents/team/deep-worker.md')
    }

    It 'Returns an empty set for a package with no agents' {
        $closed = @(Expand-MarketplaceAgentDependency -Index $script:depIndex `
                -SeedPackagePaths @() -PackageName 'all')
        $closed.Count | Should -Be 0
    }

    It 'Fails on an unresolved handoff target' {
        { Expand-MarketplaceAgentDependency -Index $script:depIndex `
                -SeedPackagePaths @('agents/team/dangling.md') -PackageName 'all' } |
            Should -Throw '*does not resolve to a catalog-declared agent*'
    }

    It 'Fails on an ambiguous handoff target' {
        $ambiguousRepo = Join-Path $TestDrive 'ambiguous-repo'
        foreach ($area in @('alpha', 'beta')) {
            $dir = Join-Path $ambiguousRepo ".github/agents/$area"
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dir 'worker.agent.md') -Encoding utf8NoBOM -Value @'
---
name: Shared Worker
---
'@
        }
        $callerDir = Join-Path $ambiguousRepo '.github/agents/caller'
        New-Item -ItemType Directory -Path $callerDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $callerDir 'caller.agent.md') -Encoding utf8NoBOM -Value @'
---
name: Caller
handoffs:
  - agent: Shared Worker
---
'@

        $catalog = @{
            plugins = @(
                @{
                    name   = 'all'
                    agents = @('agents/alpha/worker.md', 'agents/beta/worker.md', 'agents/caller/caller.md')
                }
            )
        }
        $index = Get-MarketplaceAgentIndex -Catalog $catalog -RepoRoot $ambiguousRepo
        $index.Ambiguous.Count | Should -BeGreaterThan 0

        { Expand-MarketplaceAgentDependency -Index $index -SeedPackagePaths @('agents/caller/caller.md') -PackageName 'all' } |
            Should -Throw '*is ambiguous across*'
    }
}

Describe 'Split-PluginDocumentationSource' {
    It 'Extracts the frontmatter title, marked notice, and remaining body' {
        $content = @'
---
title: Security
description: Security package
---

<!-- BEGIN PACKAGE NOTICE -->
> [!CAUTION]
> Assistive tools only.
<!-- END PACKAGE NOTICE -->

Body paragraph.
'@
        $parsed = Split-PluginDocumentationSource -Content $content
        $parsed.Title | Should -Be 'Security'
        $parsed.Notice | Should -Be "> [!CAUTION]`n> Assistive tools only."
        $parsed.Body | Should -Be 'Body paragraph.'
    }

    It 'Falls back to a legacy leading H1 when frontmatter is absent' {
        $parsed = Split-PluginDocumentationSource -Content "# Legacy Title`n`nBody."
        $parsed.Title | Should -Be 'Legacy Title'
        $parsed.Body | Should -Be 'Body.'
        $parsed.Notice | Should -Be ''
    }

    It 'Returns empty values for empty content' {
        $parsed = Split-PluginDocumentationSource -Content ''
        $parsed.Title | Should -Be ''
        $parsed.Notice | Should -Be ''
        $parsed.Body | Should -Be ''
    }
}
