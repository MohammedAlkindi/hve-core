#Requires -Modules Pester
# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT

BeforeAll {
    . $PSScriptRoot/../../plugins/Generate-Plugins.ps1
    # Re-import CollectionHelpers after dot-sourcing because PluginHelpers internally
    # imports CollectionHelpers with -Force, removing it from the caller's scope.
    Import-Module (Join-Path $PSScriptRoot '../../collections/Modules/CollectionHelpers.psm1') -Force

    # Materialization copies only git-tracked paths, so every fixture that runs
    # a real generation must be a git working tree with its sources staged.
    function Initialize-FixtureRepo {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Path
        )

        Push-Location $Path
        try {
            git init --quiet 2>$null
            git config user.email 'test@test.com'
            git config user.name 'Test'
            git add -A 2>$null
        }
        finally {
            Pop-Location
        }
    }
}

Describe 'Get-AllowedCollectionMaturities' {
    It 'Returns only stable for Stable channel' {
        $result = Get-AllowedCollectionMaturities -Channel 'Stable'
        $result | Should -Be @('stable')
    }

    It 'Returns stable, preview, and experimental for PreRelease channel' {
        $result = Get-AllowedCollectionMaturities -Channel 'PreRelease'
        $result | Should -Contain 'stable'
        $result | Should -Contain 'preview'
        $result | Should -Contain 'experimental'
    }

    It 'Does not include deprecated for either channel' {
        $stable = Get-AllowedCollectionMaturities -Channel 'Stable'
        $preRelease = Get-AllowedCollectionMaturities -Channel 'PreRelease'
        $stable | Should -Not -Contain 'deprecated'
        $preRelease | Should -Not -Contain 'deprecated'
    }

    It 'Does not include removed for either channel' {
        $stable = Get-AllowedCollectionMaturities -Channel 'Stable'
        $preRelease = Get-AllowedCollectionMaturities -Channel 'PreRelease'
        $stable | Should -Not -Contain 'removed'
        $preRelease | Should -Not -Contain 'removed'
    }
}

Describe 'Select-CollectionItemsByChannel' {
    It 'Includes stable items on Stable channel' {
        $collection = @{
            id    = 'test'
            items = @(
                @{ kind = 'agent'; path = '.github/agents/a.agent.md'; maturity = 'stable' }
            )
        }
        $result = Select-CollectionItemsByChannel -Collection $collection -Channel 'Stable'
        $result.items.Count | Should -Be 1
    }

    It 'Excludes preview items on Stable channel' {
        $collection = @{
            id    = 'test'
            items = @(
                @{ kind = 'agent'; path = '.github/agents/a.agent.md'; maturity = 'stable' },
                @{ kind = 'agent'; path = '.github/agents/b.agent.md'; maturity = 'preview' }
            )
        }
        $result = Select-CollectionItemsByChannel -Collection $collection -Channel 'Stable'
        $result.items.Count | Should -Be 1
    }

    It 'Includes preview and experimental items on PreRelease channel' {
        $collection = @{
            id    = 'test'
            items = @(
                @{ kind = 'agent'; path = '.github/agents/a.agent.md'; maturity = 'stable' },
                @{ kind = 'prompt'; path = '.github/prompts/b.prompt.md'; maturity = 'preview' },
                @{ kind = 'instruction'; path = '.github/instructions/c.instructions.md'; maturity = 'experimental' }
            )
        }
        $result = Select-CollectionItemsByChannel -Collection $collection -Channel 'PreRelease'
        $result.items.Count | Should -Be 3
    }

    It 'Excludes deprecated items on PreRelease channel' {
        $collection = @{
            id    = 'test'
            items = @(
                @{ kind = 'agent'; path = '.github/agents/a.agent.md'; maturity = 'stable' },
                @{ kind = 'agent'; path = '.github/agents/old.agent.md'; maturity = 'deprecated' }
            )
        }
        $result = Select-CollectionItemsByChannel -Collection $collection -Channel 'PreRelease'
        $result.items.Count | Should -Be 1
    }

    It 'Excludes removed items on Stable channel' {
        $collection = @{
            id    = 'test'
            items = @(
                @{ kind = 'agent'; path = '.github/agents/a.agent.md'; maturity = 'stable' },
                @{ kind = 'agent'; path = '.github/agents/gone.agent.md'; maturity = 'removed' }
            )
        }
        $result = Select-CollectionItemsByChannel -Collection $collection -Channel 'Stable'
        $result.items.Count | Should -Be 1
    }

    It 'Excludes removed items on PreRelease channel' {
        $collection = @{
            id    = 'test'
            items = @(
                @{ kind = 'agent'; path = '.github/agents/a.agent.md'; maturity = 'stable' },
                @{ kind = 'agent'; path = '.github/agents/gone.agent.md'; maturity = 'removed' }
            )
        }
        $result = Select-CollectionItemsByChannel -Collection $collection -Channel 'PreRelease'
        $result.items.Count | Should -Be 1
    }

    It 'Defaults to stable when maturity is null' {
        $collection = @{
            id    = 'test'
            items = @(
                @{ kind = 'agent'; path = '.github/agents/a.agent.md'; maturity = $null }
            )
        }
        $result = Select-CollectionItemsByChannel -Collection $collection -Channel 'Stable'
        $result.items.Count | Should -Be 1
    }

    It 'Preserves non-items keys from collection' {
        $collection = @{
            id          = 'test'
            name        = 'Test Collection'
            description = 'desc'
            items       = @(
                @{ kind = 'agent'; path = '.github/agents/a.agent.md'; maturity = 'stable' }
            )
        }
        $result = Select-CollectionItemsByChannel -Collection $collection -Channel 'Stable'
        $result.id | Should -Be 'test'
        $result.name | Should -Be 'Test Collection'
        $result.description | Should -Be 'desc'
    }
}

Describe 'Invoke-PluginGeneration - collection-level maturity' {
    BeforeAll {
        $script:maturityDir = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:maturityDir -Force | Out-Null

        # Create package.json
        @{
            name        = 'hve-core'
            version     = '1.0.0'
            description = 'test'
            author      = 'test-author'
        } | ConvertTo-Json | Set-Content -Path (Join-Path $script:maturityDir 'package.json')

        # Create collections directory
        $collectionsDir = Join-Path $script:maturityDir 'collections'
        New-Item -ItemType Directory -Path $collectionsDir -Force | Out-Null

        # Create .github structure with a test artifact
        $ghDir = Join-Path $script:maturityDir '.github'
        $agentsDir = Join-Path $ghDir 'agents/col'
        New-Item -ItemType Directory -Path $agentsDir -Force | Out-Null
        @'
---
description: "Test agent"
---
'@ | Set-Content -Path (Join-Path $agentsDir 'test.agent.md')

        # Create shared directories with tracked content for materialization
        New-Item -ItemType Directory -Path (Join-Path $script:maturityDir 'docs/templates') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:maturityDir 'scripts/lib') -Force | Out-Null
        Set-Content -Path (Join-Path $script:maturityDir 'docs/templates/sample.md') -Value 'template'
        Set-Content -Path (Join-Path $script:maturityDir 'scripts/lib/sample.sh') -Value 'echo lib'

        # Create plugins directory
        New-Item -ItemType Directory -Path (Join-Path $script:maturityDir 'plugins') -Force | Out-Null

        # Create .github/plugin directory
        New-Item -ItemType Directory -Path (Join-Path $script:maturityDir '.github/plugin') -Force | Out-Null

        # hve-core-all collection (required by Update-HveCoreAllCollection)
        @"
id: hve-core-all
name: hve-core
description: All artifacts
tags: []
items:
  - path: .github/agents/col/test.agent.md
    kind: agent
display: {}
"@ | Set-Content -Path (Join-Path $collectionsDir 'hve-core-all.collection.yml')

        # Deprecated collection
        @"
id: deprecated-col
name: Deprecated Collection
description: A deprecated collection
maturity: deprecated
items:
  - path: .github/agents/col/test.agent.md
    kind: agent
"@ | Set-Content -Path (Join-Path $collectionsDir 'deprecated-col.collection.yml')

        # Experimental collection
        @"
id: experimental-col
name: Experimental Collection
description: An experimental collection
maturity: experimental
items:
  - path: .github/agents/col/test.agent.md
    kind: agent
"@ | Set-Content -Path (Join-Path $collectionsDir 'experimental-col.collection.yml')

        Initialize-FixtureRepo -Path $script:maturityDir
    }

    AfterAll {
        Remove-Item -Path $script:maturityDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Skips deprecated collection during generation' {
        Invoke-PluginGeneration -RepoRoot $script:maturityDir -CollectionIds @('deprecated-col') -Refresh -Channel 'PreRelease' | Out-Null
        $pluginDir = Join-Path $script:maturityDir 'plugins/deprecated-col'
        Test-Path $pluginDir | Should -BeFalse
    }

    It 'Generates experimental collection on PreRelease channel' {
        Invoke-PluginGeneration -RepoRoot $script:maturityDir -CollectionIds @('experimental-col') -Refresh -Channel 'PreRelease' | Out-Null
        $pluginDir = Join-Path $script:maturityDir 'plugins/experimental-col'
        Test-Path $pluginDir | Should -BeTrue
    }
}

Describe 'Invoke-PluginGeneration' {
    BeforeAll {
        $script:tempDir = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:tempDir -Force | Out-Null

        # Create package.json
        @{
            name        = 'hve-core'
            version     = '1.0.0'
            description = 'test'
            author      = 'test-author'
        } | ConvertTo-Json | Set-Content -Path (Join-Path $script:tempDir 'package.json')

        # Create collections directory with manifests
        $collectionsDir = Join-Path $script:tempDir 'collections'
        New-Item -ItemType Directory -Path $collectionsDir -Force | Out-Null

        # Create .github structure with artifacts
        $ghDir = Join-Path $script:tempDir '.github'
        $agentsDir = Join-Path $ghDir 'agents'
        $promptsDir = Join-Path $ghDir 'prompts'
        $instrDir = Join-Path $ghDir 'instructions'
        $skillsDir = Join-Path $ghDir 'skills/test-skill'
        New-Item -ItemType Directory -Path $agentsDir -Force | Out-Null
        New-Item -ItemType Directory -Path $promptsDir -Force | Out-Null
        New-Item -ItemType Directory -Path $instrDir -Force | Out-Null
        New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null

        @'
---
description: "Test agent"
---
'@ | Set-Content -Path (Join-Path $agentsDir 'test.agent.md')

        @'
---
description: "Test prompt"
---
'@ | Set-Content -Path (Join-Path $promptsDir 'test.prompt.md')

        @'
---
description: "Test instruction"
applyTo: "**/*.ps1"
---
'@ | Set-Content -Path (Join-Path $instrDir 'test.instructions.md')

        @'
---
name: test-skill
description: "Test skill"
---
'@ | Set-Content -Path (Join-Path $skillsDir 'SKILL.md')

        # Tracked nested skill content proves directory reconstruction
        New-Item -ItemType Directory -Path (Join-Path $skillsDir 'references/nested') -Force | Out-Null
        Set-Content -Path (Join-Path $skillsDir 'references/nested/deep.md') -Value 'deep tracked fixture'

        # Create docs/templates and scripts directories with tracked content
        New-Item -ItemType Directory -Path (Join-Path $script:tempDir 'docs/templates') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:tempDir 'scripts/lib') -Force | Out-Null
        Set-Content -Path (Join-Path $script:tempDir 'docs/templates/sample.md') -Value 'template'
        Set-Content -Path (Join-Path $script:tempDir 'scripts/lib/sample.sh') -Value 'echo lib'

        # Create plugins directory
        New-Item -ItemType Directory -Path (Join-Path $script:tempDir 'plugins') -Force | Out-Null

        # Create .github/plugin directory for marketplace manifest
        New-Item -ItemType Directory -Path (Join-Path $script:tempDir '.github/plugin') -Force | Out-Null

        # hve-core-all collection
        @"
id: hve-core-all
name: hve-core
description: All artifacts
tags:
  - copilot
items:
  - path: .github/agents/test.agent.md
    kind: agent
  - path: .github/prompts/test.prompt.md
    kind: prompt
  - path: .github/instructions/test.instructions.md
    kind: instruction
  - path: .github/skills/test-skill
    kind: skill
display:
  color: blue
"@ | Set-Content -Path (Join-Path $collectionsDir 'hve-core-all.collection.yml')

        Initialize-FixtureRepo -Path $script:tempDir
    }

    AfterAll {
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Generates plugins successfully' {
        $result = Invoke-PluginGeneration -RepoRoot $script:tempDir -Refresh -Channel 'PreRelease'
        $result.Success | Should -BeTrue
        $result.PluginCount | Should -BeGreaterOrEqual 1
    }

    It 'Creates plugin directory' {
        $pluginDir = Join-Path $script:tempDir 'plugins/hve-core-all'
        Test-Path $pluginDir | Should -BeTrue
    }

    It 'Generates plugin.json manifest' {
        $manifestPath = Join-Path $script:tempDir 'plugins/hve-core-all/.github/plugin/plugin.json'
        Test-Path $manifestPath | Should -BeTrue
        $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
        $manifest.name | Should -Be 'hve-core-all'
    }

    It 'Generates README.md' {
        $readmePath = Join-Path $script:tempDir 'plugins/hve-core-all/README.md'
        Test-Path $readmePath | Should -BeTrue
    }

    It 'Writes one Included Artifacts heading to collection markdown' {
        $headingRepo = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $headingRepo -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $headingRepo 'collections') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $headingRepo '.github/agents') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $headingRepo '.github/plugin') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $headingRepo 'plugins') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $headingRepo 'docs/templates') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $headingRepo 'scripts/lib') -Force | Out-Null
        Set-Content -Path (Join-Path $headingRepo 'docs/templates/sample.md') -Value 'template' -Encoding utf8NoBOM
        Set-Content -Path (Join-Path $headingRepo 'scripts/lib/sample.sh') -Value 'echo lib' -Encoding utf8NoBOM

        @{ name = 'hve-core'; version = '1.0.0'; description = 'test'; author = 'test-author' } |
            ConvertTo-Json | Set-Content -Path (Join-Path $headingRepo 'package.json') -Encoding utf8NoBOM

        @'
---
description: "Test agent"
---
'@ | Set-Content -Path (Join-Path $headingRepo '.github/agents/test.agent.md') -Encoding utf8NoBOM

        @'
id: hve-core-all
name: hve-core
description: All artifacts
tags: []
items: []
display: {}
'@ | Set-Content -Path (Join-Path $headingRepo 'collections/hve-core-all.collection.yml') -Encoding utf8NoBOM

        $collectionYmlPath = Join-Path $headingRepo 'collections/heading-test.collection.yml'
        @"
id: heading-test
name: Heading Test
description: Heading writeback test
items:
  - path: .github/agents/test.agent.md
    kind: agent
"@ | Set-Content -Path $collectionYmlPath -Encoding utf8NoBOM

        $collectionMdPath = Join-Path $headingRepo 'collections/heading-test.collection.md'
        @"
# Heading Test

Intro text.

## Included Artifacts

<!-- BEGIN AUTO-GENERATED ARTIFACTS -->

Old content.

<!-- END AUTO-GENERATED ARTIFACTS -->
"@ | Set-Content -Path $collectionMdPath -Encoding utf8NoBOM

        Initialize-FixtureRepo -Path $headingRepo

    $result = Invoke-PluginGeneration -RepoRoot $headingRepo -CollectionIds @('heading-test') -Refresh -Channel 'PreRelease'

        $result.Success | Should -BeTrue
        $collectionContent = Get-Content -Path $collectionMdPath -Raw
        ([regex]::Matches($collectionContent, '(?m)^## Included Artifacts$')).Count | Should -Be 1
        $collectionContent | Should -Not -Match 'Old content'
        $collectionContent | Should -Match '### Chat Agents'
    }

    It 'Filters to specific collection IDs when provided' {
        $result = Invoke-PluginGeneration -RepoRoot $script:tempDir -CollectionIds @('hve-core-all') -Refresh -Channel 'PreRelease'
        $result.PluginCount | Should -Be 1
    }

    It 'Warns for non-existent collection IDs' {
        $result = Invoke-PluginGeneration -RepoRoot $script:tempDir -CollectionIds @('nonexistent') -Refresh -Channel 'PreRelease' 3>&1
        $warnings = @($result | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $warnings.Count | Should -BeGreaterOrEqual 1
    }

    It 'Supports DryRun mode' {
        $result = Invoke-PluginGeneration -RepoRoot $script:tempDir -CollectionIds @('hve-core-all') -DryRun -Channel 'PreRelease'
        $result.Success | Should -BeTrue
    }

    It 'Returns zero plugins when no collections found' {
        $emptyRoot = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path (Join-Path $emptyRoot 'collections') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $emptyRoot 'plugins') -Force | Out-Null
        @{ name = 'test'; version = '1.0.0'; description = 'test'; author = 'test' } |
            ConvertTo-Json | Set-Content -Path (Join-Path $emptyRoot 'package.json')

        # Create minimal .github structure for auto-update
        New-Item -ItemType Directory -Path (Join-Path $emptyRoot '.github/agents') -Force | Out-Null
        @"
id: hve-core-all
name: hve-core
description: test
tags: []
items: []
display: {}
"@ | Set-Content -Path (Join-Path $emptyRoot 'collections/hve-core-all.collection.yml')

        $result = Invoke-PluginGeneration -RepoRoot $emptyRoot -CollectionIds @('missing-id') -Channel 'PreRelease' 3>&1
        $hashtableResult = $result | Where-Object { $_ -is [hashtable] }
        if ($hashtableResult) {
            $hashtableResult.PluginCount | Should -Be 0
        }
    }

    It 'Applies channel filtering to items' {
        # Add a collection with mixed maturities
        $mixedPath = Join-Path (Join-Path $script:tempDir 'collections') 'mixed.collection.yml'
        @"
id: mixed
name: Mixed Collection
description: Mixed maturity test
items:
  - path: .github/agents/test.agent.md
    kind: agent
    maturity: stable
  - path: .github/prompts/test.prompt.md
    kind: prompt
    maturity: experimental
"@ | Set-Content -Path $mixedPath

        $result = Invoke-PluginGeneration -RepoRoot $script:tempDir -CollectionIds @('mixed') -Refresh -Channel 'Stable'
        $result.Success | Should -BeTrue
    }

    It 'Removes orphan files on Refresh' {
        # Create a stale file in plugin dir
        $staleDir = Join-Path $script:tempDir 'plugins/hve-core-all/stale'
        New-Item -ItemType Directory -Path $staleDir -Force | Out-Null
        'stale' | Set-Content -Path (Join-Path $staleDir 'file.txt')

        $result = Invoke-PluginGeneration -RepoRoot $script:tempDir -CollectionIds @('hve-core-all') -Refresh -Channel 'PreRelease'
        $result.Success | Should -BeTrue
        # Orphan file and its now-empty parent directory are removed
        Test-Path (Join-Path $staleDir 'file.txt') | Should -BeFalse
        Test-Path $staleDir | Should -BeFalse
        # Plugin directory itself still exists with generated files
        $pluginDir = Join-Path $script:tempDir 'plugins/hve-core-all'
        Test-Path $pluginDir | Should -BeTrue
        Test-Path (Join-Path $pluginDir 'README.md') | Should -BeTrue
    }

    It 'Logs DryRun message when refreshing existing plugin' {
        # Create orphan file so DryRun has something to report
        $pluginDir = Join-Path $script:tempDir 'plugins/hve-core-all'
        $orphanDir = Join-Path $pluginDir 'stale-dry'
        New-Item -ItemType Directory -Path $orphanDir -Force | Out-Null
        'stale' | Set-Content -Path (Join-Path $orphanDir 'file.txt')

        $output = Invoke-PluginGeneration -RepoRoot $script:tempDir `
            -CollectionIds @('hve-core-all') `
            -Refresh -DryRun -Channel 'PreRelease' 6>&1

        $dryRunMessages = @($output | Where-Object { "$_" -match 'DRY RUN.*Would remove orphan' })
        $dryRunMessages.Count | Should -BeGreaterOrEqual 1
    }

    It 'Warns when collections directory has no matching YAML files' {
        $emptyRoot = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        $emptyCollDir = Join-Path $emptyRoot 'collections'
        New-Item -ItemType Directory -Path $emptyCollDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $emptyRoot 'plugins') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $emptyRoot '.github/agents') -Force | Out-Null
        @{ name = 'test'; version = '1.0.0'; description = 'test'; author = 'test' } |
            ConvertTo-Json | Set-Content -Path (Join-Path $emptyRoot 'package.json')

        # Mock Update-HveCoreAllCollection to avoid file-not-found errors
        Mock Update-HveCoreAllCollection { return @{ ItemCount = 0; AddedCount = 0; RemovedCount = 0 } }

        $result = Invoke-PluginGeneration -RepoRoot $emptyRoot -Channel 'PreRelease' 3>&1
        $warnings = @($result | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $warnings.Count | Should -BeGreaterOrEqual 1
        $warnings[0].Message | Should -Match 'No collection manifests found'
    }

    Context 'Orphan Cleanup' {
        It 'Removes orphan files after overwrite-in-place' {
            $staleDir = Join-Path $script:tempDir 'plugins/hve-core-all/orphan-test'
            New-Item -ItemType Directory -Path $staleDir -Force | Out-Null
            'stale' | Set-Content -Path (Join-Path $staleDir 'leftover.txt')

            $result = Invoke-PluginGeneration -RepoRoot $script:tempDir -CollectionIds @('hve-core-all') -Refresh -Channel 'PreRelease'
            $result.Success | Should -BeTrue
            Test-Path (Join-Path $staleDir 'leftover.txt') | Should -BeFalse
            Test-Path (Join-Path $script:tempDir 'plugins/hve-core-all/README.md') | Should -BeTrue
        }

        It 'Preserves generated files during cleanup' {
            # Run a fresh Refresh to get clean state
            Invoke-PluginGeneration -RepoRoot $script:tempDir -CollectionIds @('hve-core-all') -Refresh -Channel 'PreRelease' | Out-Null

            $pluginDir = Join-Path $script:tempDir 'plugins/hve-core-all'
            Test-Path (Join-Path $pluginDir 'README.md') | Should -BeTrue
            Test-Path (Join-Path $pluginDir '.github/plugin/plugin.json') | Should -BeTrue
            Test-Path (Join-Path $pluginDir 'docs/templates') | Should -BeTrue
            Test-Path (Join-Path $pluginDir 'scripts/lib') | Should -BeTrue
        }

        It 'Removes empty directories after orphan cleanup' {
            $nestedOrphan = Join-Path $script:tempDir 'plugins/hve-core-all/stale-dir/nested'
            New-Item -ItemType Directory -Path $nestedOrphan -Force | Out-Null
            'leftover' | Set-Content -Path (Join-Path $nestedOrphan 'leftover.txt')

            $result = Invoke-PluginGeneration -RepoRoot $script:tempDir -CollectionIds @('hve-core-all') -Refresh -Channel 'PreRelease'
            $result.Success | Should -BeTrue
            Test-Path (Join-Path $script:tempDir 'plugins/hve-core-all/stale-dir') | Should -BeFalse
        }

        It 'DryRun logs orphan files without removing them' {
            $orphanDir = Join-Path $script:tempDir 'plugins/hve-core-all/dry-orphan'
            New-Item -ItemType Directory -Path $orphanDir -Force | Out-Null
            'keep-me' | Set-Content -Path (Join-Path $orphanDir 'persist.txt')

            $output = Invoke-PluginGeneration -RepoRoot $script:tempDir `
                -CollectionIds @('hve-core-all') `
                -Refresh -DryRun -Channel 'PreRelease' 6>&1

            $dryRunMessages = @($output | Where-Object { "$_" -match 'DRY RUN.*Would remove orphan' })
            $dryRunMessages.Count | Should -BeGreaterOrEqual 1
            # File still exists after DryRun
            Test-Path (Join-Path $orphanDir 'persist.txt') | Should -BeTrue
        }
    }
}

Describe 'Invoke-PluginGeneration - materialization' {
    BeforeAll {
        $script:matRepo = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        $script:matSkillSource = Join-Path $script:matRepo '.github/skills/team/demo'
        $script:matPluginDir = Join-Path $script:matRepo 'plugins/mat-test'

        New-Item -ItemType Directory -Force -Path @(
            (Join-Path $script:matRepo 'collections')
            (Join-Path $script:matRepo 'plugins')
            (Join-Path $script:matRepo '.github/plugin')
            (Join-Path $script:matRepo '.github/agents/team')
            (Join-Path $script:matRepo '.github/prompts/team')
            (Join-Path $script:matRepo '.github/instructions/team')
            (Join-Path $script:matSkillSource 'references/nested')
            (Join-Path $script:matRepo 'docs/templates')
            (Join-Path $script:matRepo 'scripts/lib')
        ) | Out-Null

        @{ name = 'hve-core'; version = '1.0.0'; description = 'test'; author = 'test-author' } |
            ConvertTo-Json | Set-Content -Path (Join-Path $script:matRepo 'package.json')

        Set-Content -Path (Join-Path $script:matRepo '.github/agents/team/example.agent.md') `
            -Value "---`ndescription: `"Example agent`"`n---"
        Set-Content -Path (Join-Path $script:matRepo '.github/prompts/team/example.prompt.md') `
            -Value "---`ndescription: `"Example prompt`"`n---"
        Set-Content -Path (Join-Path $script:matRepo '.github/instructions/team/example.instructions.md') `
            -Value "---`ndescription: `"Example instruction`"`napplyTo: `"**`"`n---"
        Set-Content -Path (Join-Path $script:matSkillSource 'SKILL.md') `
            -Value "---`nname: demo`ndescription: `"Demo skill`"`n---"
        Set-Content -Path (Join-Path $script:matSkillSource 'references/nested/deep.md') -Value 'deep tracked fixture'
        Set-Content -Path (Join-Path $script:matRepo 'docs/templates/sample.md') -Value 'template'
        Set-Content -Path (Join-Path $script:matRepo 'scripts/lib/sample.sh') -Value 'echo lib'

        @'
id: hve-core-all
name: hve-core
description: All artifacts
tags: []
items: []
display: {}
'@ | Set-Content -Path (Join-Path $script:matRepo 'collections/hve-core-all.collection.yml')

        @'
id: mat-test
name: Materialization Test
description: Materialization fixture
items:
  - path: .github/agents/team/example.agent.md
    kind: agent
  - path: .github/prompts/team/example.prompt.md
    kind: prompt
  - path: .github/instructions/team/example.instructions.md
    kind: instruction
  - path: .github/skills/team/demo
    kind: skill
'@ | Set-Content -Path (Join-Path $script:matRepo 'collections/mat-test.collection.yml')

        Initialize-FixtureRepo -Path $script:matRepo

        # Untracked residue written after staging so it is never in the index.
        Set-Content -Path (Join-Path $script:matSkillSource 'untracked-sentinel.md') -Value 'sentinel'
        New-Item -ItemType Directory -Path (Join-Path $script:matSkillSource '.venv') -Force | Out-Null
        Set-Content -Path (Join-Path $script:matSkillSource '.venv/pyvenv.cfg') -Value 'home = /usr'

        Invoke-PluginGeneration -RepoRoot $script:matRepo -CollectionIds @('mat-test') -Refresh -Channel 'PreRelease' | Out-Null
    }

    It 'Produces only regular files and real directories' {
        $links = @(Get-ChildItem -LiteralPath $script:matPluginDir -Recurse -Force | Where-Object { $_.LinkType })
        $links.Count | Should -Be 0
    }

    It 'Reconstructs a tracked nested skill subtree' {
        Test-Path (Join-Path $script:matPluginDir 'skills/team/demo/SKILL.md') | Should -BeTrue
        Test-Path (Join-Path $script:matPluginDir 'skills/team/demo/references/nested/deep.md') | Should -BeTrue
    }

    It 'Materializes the shared resource directories' {
        Test-Path (Join-Path $script:matPluginDir 'docs/templates/sample.md') | Should -BeTrue
        Test-Path (Join-Path $script:matPluginDir 'scripts/lib/sample.sh') | Should -BeTrue
    }

    It 'Excludes an untracked sentinel and development residue' {
        Test-Path (Join-Path $script:matPluginDir 'skills/team/demo/untracked-sentinel.md') | Should -BeFalse
        Test-Path (Join-Path $script:matPluginDir 'skills/team/demo/.venv') | Should -BeFalse
    }

    It 'Keeps materialized directory contents across a repeat Refresh' {
        $before = @(Get-ChildItem -LiteralPath $script:matPluginDir -Recurse -File -Force |
                Sort-Object FullName |
                ForEach-Object { "$($_.FullName)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" })

        Invoke-PluginGeneration -RepoRoot $script:matRepo -CollectionIds @('mat-test') -Refresh -Channel 'PreRelease' | Out-Null

        $after = @(Get-ChildItem -LiteralPath $script:matPluginDir -Recurse -File -Force |
                Sort-Object FullName |
                ForEach-Object { "$($_.FullName)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" })

        $before.Count | Should -BeGreaterThan 0
        $after | Should -Be $before
    }

    It 'Detects a file placed manually inside a materialized directory' {
        $intruder = Join-Path $script:matPluginDir 'skills/team/demo/references/nested/intruder.md'
        Set-Content -Path $intruder -Value 'manual'

        Invoke-PluginGeneration -RepoRoot $script:matRepo -CollectionIds @('mat-test') -Refresh -Channel 'PreRelease' | Out-Null

        Test-Path $intruder | Should -BeFalse
        Test-Path (Join-Path $script:matPluginDir 'skills/team/demo/references/nested/deep.md') | Should -BeTrue
    }

    It 'Removes generated output for an item dropped from the collection' {
        $collectionYml = Join-Path $script:matRepo 'collections/mat-test.collection.yml'
        Test-Path (Join-Path $script:matPluginDir 'commands/team/example.md') | Should -BeTrue

        @'
id: mat-test
name: Materialization Test
description: Materialization fixture
items:
  - path: .github/agents/team/example.agent.md
    kind: agent
  - path: .github/skills/team/demo
    kind: skill
'@ | Set-Content -Path $collectionYml

        Invoke-PluginGeneration -RepoRoot $script:matRepo -CollectionIds @('mat-test') -Refresh -Channel 'PreRelease' | Out-Null

        Test-Path (Join-Path $script:matPluginDir 'commands/team/example.md') | Should -BeFalse
        Test-Path (Join-Path $script:matPluginDir 'agents/team/example.md') | Should -BeTrue
        Test-Path (Join-Path $script:matPluginDir 'skills/team/demo/SKILL.md') | Should -BeTrue
    }
}

Describe 'Assert-PluginOutputSize' {
    BeforeAll {
        $script:sizeDir = Join-Path $TestDrive 'size-plugins'
        $script:bigPlugin = Join-Path $script:sizeDir 'oversize-plugin'
        $script:smallPlugin = Join-Path $script:sizeDir 'small-plugin'
        New-Item -ItemType Directory -Path $script:bigPlugin -Force | Out-Null
        New-Item -ItemType Directory -Path $script:smallPlugin -Force | Out-Null

        [System.IO.File]::WriteAllBytes(
            (Join-Path $script:bigPlugin 'payload.bin'),
            [byte[]]::new(3MB)
        )
        Set-Content -Path (Join-Path $script:smallPlugin 'README.md') -Value 'small'
    }

    It 'Returns the measured total when under the ceiling' {
        $report = Assert-PluginOutputSize -PluginsDir $script:sizeDir -MaxTotalSizeMB 40
        $report.TotalMB | Should -BeGreaterThan 2
        $report.TotalMB | Should -BeLessThan 40
    }

    It 'Throws and names the offending plugin when over the ceiling' {
        { Assert-PluginOutputSize -PluginsDir $script:sizeDir -MaxTotalSizeMB 1 } |
            Should -Throw '*oversize-plugin*'
    }

    It 'Reports zero for a missing plugins directory' {
        $report = Assert-PluginOutputSize -PluginsDir (Join-Path $TestDrive 'no-plugins-here') -MaxTotalSizeMB 40
        $report.TotalMB | Should -Be 0
    }
}

Describe 'Invoke-PluginGeneration - size ceiling' {
    BeforeAll {
        $script:ceilingRepo = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path (Join-Path $script:ceilingRepo 'collections') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:ceilingRepo 'plugins') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:ceilingRepo '.github/plugin') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:ceilingRepo '.github/skills/bulky') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:ceilingRepo '.github/agents') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:ceilingRepo 'docs/templates') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:ceilingRepo 'scripts/lib') -Force | Out-Null
        Set-Content -Path (Join-Path $script:ceilingRepo 'docs/templates/sample.md') -Value 'template'
        Set-Content -Path (Join-Path $script:ceilingRepo 'scripts/lib/sample.sh') -Value 'echo lib'

        @{ name = 'hve-core'; version = '1.0.0'; description = 'test'; author = 'test-author' } |
            ConvertTo-Json | Set-Content -Path (Join-Path $script:ceilingRepo 'package.json')

        @'
---
name: bulky
description: "Bulky skill"
---
'@ | Set-Content -Path (Join-Path $script:ceilingRepo '.github/skills/bulky/SKILL.md')

        [System.IO.File]::WriteAllBytes(
            (Join-Path $script:ceilingRepo '.github/skills/bulky/payload.bin'),
            [byte[]]::new(2MB)
        )

        @'
id: hve-core-all
name: hve-core
description: All artifacts
tags: []
items: []
display: {}
'@ | Set-Content -Path (Join-Path $script:ceilingRepo 'collections/hve-core-all.collection.yml')

        @'
id: bulky-col
name: Bulky Collection
description: Oversize generation fixture
items:
  - path: .github/skills/bulky
    kind: skill
'@ | Set-Content -Path (Join-Path $script:ceilingRepo 'collections/bulky-col.collection.yml')

        Initialize-FixtureRepo -Path $script:ceilingRepo
    }

    It 'Fails generation when materialized output exceeds the ceiling' {
        {
            Invoke-PluginGeneration -RepoRoot $script:ceilingRepo -CollectionIds @('bulky-col') `
                -Refresh -Channel 'PreRelease' -MaxTotalSizeMB 1
        } | Should -Throw '*bulky-col*'
    }

    It 'Succeeds under the default ceiling' {
        $result = Invoke-PluginGeneration -RepoRoot $script:ceilingRepo -CollectionIds @('bulky-col') `
            -Refresh -Channel 'PreRelease'
        $result.Success | Should -BeTrue
    }
}

Describe 'Start-PluginGeneration' {
    It 'Returns 0 on successful generation' {
        Mock Invoke-PluginGeneration { return @{ Success = $true; PluginCount = 2 } }
        Mock Get-Module { return @{ Name = 'PowerShell-Yaml' } } -ParameterFilter { $ListAvailable -and $Name -eq 'PowerShell-Yaml' }
        Mock Import-Module {}

        $scriptPath = "$PSScriptRoot/../../plugins/Generate-Plugins.ps1"
        $exitCode = Start-PluginGeneration -ScriptPath $scriptPath -Channel 'PreRelease'
        $exitCode | Should -Be 0
    }

    It 'Returns 1 when Invoke-PluginGeneration reports failure' {
        Mock Invoke-PluginGeneration { return @{ Success = $false; PluginCount = 0; ErrorMessage = 'Generation failed' } }
        Mock Get-Module { return @{ Name = 'PowerShell-Yaml' } } -ParameterFilter { $ListAvailable -and $Name -eq 'PowerShell-Yaml' }
        Mock Import-Module {}

        $scriptPath = "$PSScriptRoot/../../plugins/Generate-Plugins.ps1"
        $output = Start-PluginGeneration -ScriptPath $scriptPath -Channel 'PreRelease' -ErrorAction SilentlyContinue
        $exitCode = @($output) | Where-Object { $_ -is [int] } | Select-Object -Last 1
        $exitCode | Should -Be 1
    }

    It 'Returns 1 when PowerShell-Yaml module is missing' {
        Mock Get-Module { return $null } -ParameterFilter { $ListAvailable -and $Name -eq 'PowerShell-Yaml' }

        $scriptPath = "$PSScriptRoot/../../plugins/Generate-Plugins.ps1"
        $output = Start-PluginGeneration -ScriptPath $scriptPath -Channel 'PreRelease' -ErrorAction SilentlyContinue
        $exitCode = @($output) | Where-Object { $_ -is [int] } | Select-Object -Last 1
        $exitCode | Should -Be 1
    }

    It 'Defaults to refresh when no CollectionIds, Refresh, or DryRun provided' {
        Mock Get-Module { return @{ Name = 'PowerShell-Yaml' } } -ParameterFilter { $ListAvailable -and $Name -eq 'PowerShell-Yaml' }
        Mock Import-Module {}
        Mock Invoke-PluginGeneration { return @{ Success = $true; PluginCount = 1 } }

        $scriptPath = "$PSScriptRoot/../../plugins/Generate-Plugins.ps1"
        Start-PluginGeneration -ScriptPath $scriptPath -Channel 'PreRelease' | Out-Null

        Should -Invoke Invoke-PluginGeneration -Times 1 -ParameterFilter { $Refresh -eq $true }
    }

    It 'Does not force refresh when CollectionIds are provided' {
        Mock Get-Module { return @{ Name = 'PowerShell-Yaml' } } -ParameterFilter { $ListAvailable -and $Name -eq 'PowerShell-Yaml' }
        Mock Import-Module {}
        Mock Invoke-PluginGeneration { return @{ Success = $true; PluginCount = 1 } }

        $scriptPath = "$PSScriptRoot/../../plugins/Generate-Plugins.ps1"
        Start-PluginGeneration -ScriptPath $scriptPath -CollectionIds @('test') -Channel 'PreRelease' | Out-Null

        Should -Invoke Invoke-PluginGeneration -Times 1 -ParameterFilter { $Refresh -eq $false }
    }
}
