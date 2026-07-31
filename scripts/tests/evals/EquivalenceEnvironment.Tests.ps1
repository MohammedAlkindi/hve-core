#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

BeforeAll {
    $script:ModulePath = (Resolve-Path (Join-Path $PSScriptRoot '../../evals/lib/EquivalenceEnvironment.psm1')).Path
    Import-Module $script:ModulePath -Force
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path

    function New-AgentFixture {
        <#
        .SYNOPSIS
            Builds a miniature repository with two agents that reference different skills.
        #>
        param([Parameter(Mandatory = $true)][string]$Root)

        $skillDefs = @{
            'alpha/skill-one'   = 'Skill one.'
            'alpha/skill-two'   = 'Skill two.'
            'beta/skill-three'  = 'Skill three.'
        }
        foreach ($relative in $skillDefs.Keys) {
            $dir = Join-Path $Root ".github/skills/$relative"
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dir 'SKILL.md') -Value $skillDefs[$relative] -Encoding UTF8
        }

        $agentsDir = Join-Path $Root '.github/agents/sample'
        New-Item -ItemType Directory -Path $agentsDir -Force | Out-Null

        # References its skills by backticked name, as the RPI agent does.
        Set-Content -LiteralPath (Join-Path $agentsDir 'agent-one.agent.md') -Encoding UTF8 -Value @'
---
name: Agent One
---

Activate `skill-one` and `skill-two` as needed.
'@

        # References its skill by explicit path.
        Set-Content -LiteralPath (Join-Path $agentsDir 'agent-two.agent.md') -Encoding UTF8 -Value @'
---
name: Agent Two
---

See .github/skills/beta/skill-three/SKILL.md for details.
'@

        New-Item -ItemType Directory -Path (Join-Path $Root '.github') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $Root '.github/copilot-instructions.md') -Value 'Repo instructions.' -Encoding UTF8
    }
}

Describe 'Get-AgentSkillReference' -Tag 'Unit' {
    BeforeAll {
        $script:FixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        New-AgentFixture -Root $script:FixtureRoot
    }

    AfterAll {
        Remove-Item -LiteralPath $script:FixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Resolves skills referenced by backticked name' {
        $skills = @(Get-AgentSkillReference -RepoRoot $script:FixtureRoot -AgentFilePath '.github/agents/sample/agent-one.agent.md')
        $skills.Count | Should -Be 2
        $skills | Should -Contain '.github/skills/alpha/skill-one'
        $skills | Should -Contain '.github/skills/alpha/skill-two'
    }

    It 'Resolves skills referenced by explicit path' {
        $skills = @(Get-AgentSkillReference -RepoRoot $script:FixtureRoot -AgentFilePath '.github/agents/sample/agent-two.agent.md')
        $skills.Count | Should -Be 1
        $skills[0] | Should -Be '.github/skills/beta/skill-three'
    }

    It 'Does not resolve a backticked name that is not a real skill' {
        $agentPath = Join-Path $script:FixtureRoot '.github/agents/sample/agent-three.agent.md'
        Set-Content -LiteralPath $agentPath -Value "---`nname: Three`n---`n`nUse ``not-a-skill`` here." -Encoding UTF8
        try {
            @(Get-AgentSkillReference -RepoRoot $script:FixtureRoot -AgentFilePath '.github/agents/sample/agent-three.agent.md').Count | Should -Be 0
        }
        finally {
            Remove-Item -LiteralPath $agentPath -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Returns an empty set for a missing agent file' {
        @(Get-AgentSkillReference -RepoRoot $script:FixtureRoot -AgentFilePath '.github/agents/sample/absent.agent.md').Count | Should -Be 0
    }
}

Describe 'New-CustomizedEnvironment' -Tag 'Unit' {
    BeforeAll {
        $script:FixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        New-AgentFixture -Root $script:FixtureRoot
    }

    AfterAll {
        Remove-Item -LiteralPath $script:FixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Materializes only the skills the agent references' {
        $ws = Join-Path $script:FixtureRoot 'out/ws1'
        $sd = Join-Path $script:FixtureRoot 'out/sd1'
        $result = New-CustomizedEnvironment -RepoRoot $script:FixtureRoot -Agent 'agent-one' -WorkspacePath $ws -SkillDirPath $sd
        $materialized = @(Get-ChildItem -LiteralPath $sd -Directory | Select-Object -ExpandProperty Name)
        $materialized.Count | Should -Be 2
        $materialized | Should -Contain 'skill-one'
        $materialized | Should -Not -Contain 'skill-three'
        $result.Applied | Should -Contain '.github/agents/sample/agent-one.agent.md'
    }

    It 'Produces different environments for different agents' {
        # This is the property the whole comparison depends on. If two agents yield the
        # same customized environment, the suite cannot tell them apart and every
        # per-agent verdict is measuring the same thing.
        $wsOne = Join-Path $script:FixtureRoot 'out/wsA'
        $sdOne = Join-Path $script:FixtureRoot 'out/sdA'
        $wsTwo = Join-Path $script:FixtureRoot 'out/wsB'
        $sdTwo = Join-Path $script:FixtureRoot 'out/sdB'

        $one = New-CustomizedEnvironment -RepoRoot $script:FixtureRoot -Agent 'agent-one' -WorkspacePath $wsOne -SkillDirPath $sdOne
        $two = New-CustomizedEnvironment -RepoRoot $script:FixtureRoot -Agent 'agent-two' -WorkspacePath $wsTwo -SkillDirPath $sdTwo

        $skillsOne = @(Get-ChildItem -LiteralPath $sdOne -Directory | Select-Object -ExpandProperty Name) | Sort-Object
        $skillsTwo = @(Get-ChildItem -LiteralPath $sdTwo -Directory | Select-Object -ExpandProperty Name) | Sort-Object

        ($skillsOne -join ',') | Should -Not -Be ($skillsTwo -join ',')
        ($one.Applied -join ',') | Should -Not -Be ($two.Applied -join ',')
    }

    It 'Includes the agent file and repository instructions' {
        $ws = Join-Path $script:FixtureRoot 'out/ws2'
        $sd = Join-Path $script:FixtureRoot 'out/sd2'
        $result = New-CustomizedEnvironment -RepoRoot $script:FixtureRoot -Agent 'agent-two' -WorkspacePath $ws -SkillDirPath $sd
        $result.Applied | Should -Contain '.github/copilot-instructions.md'
        Test-Path -LiteralPath (Join-Path $ws '.github/agents/sample/agent-two.agent.md') | Should -BeTrue
    }

    It 'Reports a nonzero applied artifact count' {
        # The driver records this in variant metadata. Zero would mean no customization
        # was applied, which is the defect this function exists to prevent.
        $ws = Join-Path $script:FixtureRoot 'out/ws3'
        $sd = Join-Path $script:FixtureRoot 'out/sd3'
        $result = New-CustomizedEnvironment -RepoRoot $script:FixtureRoot -Agent 'agent-one' -WorkspacePath $ws -SkillDirPath $sd
        @($result.Applied).Count | Should -BeGreaterThan 0
    }

    It 'Clears stale content from a reused workspace' {
        $ws = Join-Path $script:FixtureRoot 'out/ws4'
        $sd = Join-Path $script:FixtureRoot 'out/sd4'
        New-CustomizedEnvironment -RepoRoot $script:FixtureRoot -Agent 'agent-one' -WorkspacePath $ws -SkillDirPath $sd | Out-Null
        New-CustomizedEnvironment -RepoRoot $script:FixtureRoot -Agent 'agent-two' -WorkspacePath $ws -SkillDirPath $sd | Out-Null
        $names = @(Get-ChildItem -LiteralPath $sd -Directory | Select-Object -ExpandProperty Name)
        $names | Should -Not -Contain 'skill-one'
        $names | Should -Contain 'skill-three'
    }

    It 'Throws for an agent that does not exist' {
        $ws = Join-Path $script:FixtureRoot 'out/ws5'
        $sd = Join-Path $script:FixtureRoot 'out/sd5'
        { New-CustomizedEnvironment -RepoRoot $script:FixtureRoot -Agent 'no-such-agent' -WorkspacePath $ws -SkillDirPath $sd } |
            Should -Throw -ExpectedMessage '*not found*'
    }
}

Describe 'Baseline cache' -Tag 'Unit' {
    BeforeAll {
        $script:CacheRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        $script:SourceRun = Join-Path $script:CacheRoot 'source-run'
        New-Item -ItemType Directory -Path $script:SourceRun -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:SourceRun 'results.jsonl') -Value '{"type":"trial-result"}' -Encoding UTF8
    }

    AfterAll {
        Remove-Item -LiteralPath $script:CacheRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Returns null when no baseline has been cached' {
        Get-BaselineCacheEntry -CacheRoot $script:CacheRoot -CacheKey 'model-a/0.10.0/abcdef123456' | Should -BeNullOrEmpty
    }

    It 'Round-trips a saved baseline' {
        $key = Get-BaselineCacheKey -Model 'gpt-5.6-luna' -VallyVersion '0.10.0' -StimulusHash ('a' * 64)
        Save-BaselineCacheEntry -CacheRoot $script:CacheRoot -CacheKey $key -RunDir $script:SourceRun `
            -Model 'gpt-5.6-luna' -VallyVersion '0.10.0' -StimulusHash ('a' * 64) | Out-Null
        $hit = Get-BaselineCacheEntry -CacheRoot $script:CacheRoot -CacheKey $key
        $hit | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $hit 'results.jsonl') | Should -BeTrue
    }

    It 'Does not reuse a baseline captured under a different model' {
        # Reusing across models would attribute a model change to the customization.
        $saved = Get-BaselineCacheKey -Model 'gpt-5.6-luna' -VallyVersion '0.10.0' -StimulusHash ('a' * 64)
        Save-BaselineCacheEntry -CacheRoot $script:CacheRoot -CacheKey $saved -RunDir $script:SourceRun `
            -Model 'gpt-5.6-luna' -VallyVersion '0.10.0' -StimulusHash ('a' * 64) | Out-Null
        $other = Get-BaselineCacheKey -Model 'claude-haiku-4.5' -VallyVersion '0.10.0' -StimulusHash ('a' * 64)
        Get-BaselineCacheEntry -CacheRoot $script:CacheRoot -CacheKey $other | Should -BeNullOrEmpty
    }

    It 'Does not reuse a baseline captured under a different Vally version' {
        $saved = Get-BaselineCacheKey -Model 'gpt-5.6-luna' -VallyVersion '0.10.0' -StimulusHash ('b' * 64)
        Save-BaselineCacheEntry -CacheRoot $script:CacheRoot -CacheKey $saved -RunDir $script:SourceRun `
            -Model 'gpt-5.6-luna' -VallyVersion '0.10.0' -StimulusHash ('b' * 64) | Out-Null
        $other = Get-BaselineCacheKey -Model 'gpt-5.6-luna' -VallyVersion '0.11.0' -StimulusHash ('b' * 64)
        Get-BaselineCacheEntry -CacheRoot $script:CacheRoot -CacheKey $other | Should -BeNullOrEmpty
    }

    It 'Does not reuse a baseline when the stimulus content changed' {
        # Editing a prompt must invalidate, or new questions would be compared against
        # answers captured for the old ones.
        $saved = Get-BaselineCacheKey -Model 'gpt-5.6-luna' -VallyVersion '0.10.0' -StimulusHash ('c' * 64)
        Save-BaselineCacheEntry -CacheRoot $script:CacheRoot -CacheKey $saved -RunDir $script:SourceRun `
            -Model 'gpt-5.6-luna' -VallyVersion '0.10.0' -StimulusHash ('c' * 64) | Out-Null
        $other = Get-BaselineCacheKey -Model 'gpt-5.6-luna' -VallyVersion '0.10.0' -StimulusHash ('d' * 64)
        Get-BaselineCacheEntry -CacheRoot $script:CacheRoot -CacheKey $other | Should -BeNullOrEmpty
    }

    It 'Rejects a cache entry whose run directory has no results' {
        $key = Get-BaselineCacheKey -Model 'gpt-5.6-luna' -VallyVersion '0.10.0' -StimulusHash ('e' * 64)
        $emptyRun = Join-Path $script:CacheRoot 'empty-run'
        New-Item -ItemType Directory -Path $emptyRun -Force | Out-Null
        Save-BaselineCacheEntry -CacheRoot $script:CacheRoot -CacheKey $key -RunDir $emptyRun `
            -Model 'gpt-5.6-luna' -VallyVersion '0.10.0' -StimulusHash ('e' * 64) | Out-Null
        Get-BaselineCacheEntry -CacheRoot $script:CacheRoot -CacheKey $key | Should -BeNullOrEmpty
    }
}

Describe 'Get-StimulusContentHash' -Tag 'Unit' {
    It 'Returns a stable hash for identical content' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        Set-Content -LiteralPath $path -Value "line one`nline two" -Encoding UTF8
        try {
            $first = Get-StimulusContentHash -SpecPath $path
            $second = Get-StimulusContentHash -SpecPath $path
            $first | Should -Be $second
            $first.Length | Should -Be 64
        }
        finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Changes when content changes' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        try {
            Set-Content -LiteralPath $path -Value 'original' -Encoding UTF8
            $before = Get-StimulusContentHash -SpecPath $path
            Set-Content -LiteralPath $path -Value 'edited' -Encoding UTF8
            Get-StimulusContentHash -SpecPath $path | Should -Not -Be $before
        }
        finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Reports missing for an absent spec' {
        Get-StimulusContentHash -SpecPath (Join-Path ([System.IO.Path]::GetTempPath()) 'absent-spec.yaml') | Should -Be 'missing'
    }
}

Describe 'Repository agents' -Tag 'Unit' {
    It 'Resolves distinct skill sets for two real agents' {
        $rpi = @(Get-AgentSkillReference -RepoRoot $script:RepoRoot -AgentFilePath '.github/agents/hve-core/rpi-agent.agent.md')
        $doc = @(Get-AgentSkillReference -RepoRoot $script:RepoRoot -AgentFilePath '.github/agents/hve-core/documentation.agent.md')
        $rpi.Count | Should -BeGreaterThan 0
        $doc.Count | Should -BeGreaterThan 0
        ($rpi -join ',') | Should -Not -Be ($doc -join ',')
    }
}
