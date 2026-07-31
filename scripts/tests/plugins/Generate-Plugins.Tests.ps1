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

    # The marketplace catalog is the only package-definition input, so fixtures
    # declare packages here rather than through retiring collection YAML.
    function New-FixtureCatalog {
        param(
            [Parameter(Mandatory = $true)]
            [string]$RepoRoot,

            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [array]$Plugins
        )

        $normalizedPlugins = foreach ($plugin in $Plugins) {
            $normalized = [ordered]@{}
            foreach ($key in $plugin.Keys) {
                $normalized[$key] = $plugin[$key]
            }
            $normalized['source'] = [ordered]@{
                source = 'github'
                repo   = 'microsoft/hve-core'
                path   = "plugins/$($plugin['name'])"
                ref    = "plugins-v$($plugin['version'])"
            }
            $normalized
        }

        $catalog = [ordered]@{
            name     = 'hve-core'
            metadata = [ordered]@{ description = 'test'; version = '1.0.0'; pluginRoot = './plugins' }
            owner    = [ordered]@{ name = 'test-author' }
            plugins  = @($normalizedPlugins)
        }

        $pluginDir = Join-Path $RepoRoot '.github/plugin'
        New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null
        $catalog | ConvertTo-Json -Depth 12 |
            Set-Content -Path (Join-Path $pluginDir 'marketplace.json') -Encoding utf8NoBOM
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

Describe 'Get-MarketplacePackageRecipe' {
    It 'Includes stable components on Stable channel' {
        $entry = @{ name = 'test'; agents = @('agents/team/a.md') }
        $result = @(Get-MarketplacePackageRecipe -Entry $entry -Channel 'Stable')
        $result.Count | Should -Be 1
        $result[0].SourcePath | Should -Be '.github/agents/team/a.agent.md'
    }

    It 'Excludes preview components on Stable channel' {
        $entry = @{
            name    = 'test'
            agents  = @('agents/team/a.md', 'agents/team/b.md')
            'x-hve' = @{ componentMaturity = @{ 'agents/team/b.md' = 'preview' } }
        }
        $result = @(Get-MarketplacePackageRecipe -Entry $entry -Channel 'Stable')
        $result.Count | Should -Be 1
    }

    It 'Includes preview and experimental components on PreRelease channel' {
        $entry = @{
            name     = 'test'
            agents   = @('agents/team/a.md')
            commands = @('commands/team/b.md')
            rules    = @('rules/team/c.instructions.md')
            'x-hve'  = @{
                componentMaturity = @{
                    'commands/team/b.md'            = 'preview'
                    'rules/team/c.instructions.md' = 'experimental'
                }
            }
        }
        $result = @(Get-MarketplacePackageRecipe -Entry $entry -Channel 'PreRelease')
        $result.Count | Should -Be 3
    }

    It 'Excludes deprecated components on PreRelease channel' {
        $entry = @{
            name    = 'test'
            agents  = @('agents/team/a.md', 'agents/team/old.md')
            'x-hve' = @{ componentMaturity = @{ 'agents/team/old.md' = 'deprecated' } }
        }
        $result = @(Get-MarketplacePackageRecipe -Entry $entry -Channel 'PreRelease')
        $result.Count | Should -Be 1
    }

    It 'Excludes removed tombstones on both channels' {
        $entry = @{
            name    = 'test'
            agents  = @('agents/team/a.md', 'agents/team/gone.md')
            'x-hve' = @{ componentMaturity = @{ 'agents/team/gone.md' = 'removed' } }
        }
        @(Get-MarketplacePackageRecipe -Entry $entry -Channel 'Stable').Count | Should -Be 1
        @(Get-MarketplacePackageRecipe -Entry $entry -Channel 'PreRelease').Count | Should -Be 1
    }

    It 'Defaults to stable when no component maturity is declared' {
        $entry = @{ name = 'test'; agents = @('agents/team/a.md') }
        $result = @(Get-MarketplacePackageRecipe -Entry $entry -Channel 'Stable')
        $result[0].Maturity | Should -Be 'stable'
    }

    It 'Maps every component kind to its canonical repository source' {
        $entry = @{
            name     = 'test'
            agents   = @('agents/team/a.md')
            commands = @('commands/team/b.md')
            rules    = @('rules/team/c.instructions.md')
            skills   = @('skills/team/demo')
            hooks    = @('hooks/team/h.json')
        }
        $result = @(Get-MarketplacePackageRecipe -Entry $entry -Channel 'PreRelease')
        ($result | Where-Object { $_.Kind -eq 'agent' }).SourcePath | Should -Be '.github/agents/team/a.agent.md'
        ($result | Where-Object { $_.Kind -eq 'prompt' }).SourcePath | Should -Be '.github/prompts/team/b.prompt.md'
        ($result | Where-Object { $_.Kind -eq 'instruction' }).SourcePath | Should -Be '.github/instructions/team/c.instructions.md'
        ($result | Where-Object { $_.Kind -eq 'skill' }).SourcePath | Should -Be '.github/skills/team/demo'
        ($result | Where-Object { $_.Kind -eq 'hook' }).SourcePath | Should -Be '.github/hooks/team/h.json'
    }
}

Describe 'Invoke-PluginGeneration - package-level maturity' {
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

        New-FixtureCatalog -RepoRoot $script:maturityDir -Plugins @(
            [ordered]@{
                name        = 'deprecated-col'
                description = 'A deprecated package'
                version     = '1.0.0'
                agents      = @('agents/col/test.md')
                'x-hve'     = [ordered]@{ maturity = 'deprecated' }
            },
            [ordered]@{
                name        = 'experimental-col'
                description = 'An experimental package'
                version     = '1.0.0'
                agents      = @('agents/col/test.md')
                'x-hve'     = [ordered]@{ maturity = 'experimental' }
            }
        )

        Initialize-FixtureRepo -Path $script:maturityDir
    }

    AfterAll {
        Remove-Item -Path $script:maturityDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Skips deprecated package during generation' {
        Invoke-PluginGeneration -RepoRoot $script:maturityDir -PackageNames @('deprecated-col') -Refresh -Channel 'PreRelease' | Out-Null
        $pluginDir = Join-Path $script:maturityDir 'plugins/deprecated-col'
        Test-Path $pluginDir | Should -BeFalse
    }

    It 'Generates experimental package on PreRelease channel' {
        Invoke-PluginGeneration -RepoRoot $script:maturityDir -PackageNames @('experimental-col') -Refresh -Channel 'PreRelease' | Out-Null
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

        # Create .github structure with artifacts
        $ghDir = Join-Path $script:tempDir '.github'
        $agentsDir = Join-Path $ghDir 'agents/team'
        $promptsDir = Join-Path $ghDir 'prompts/team'
        $instrDir = Join-Path $ghDir 'instructions/team'
        $skillsDir = Join-Path $ghDir 'skills/team/test-skill'
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

        New-FixtureCatalog -RepoRoot $script:tempDir -Plugins @(
            [ordered]@{
                name        = 'hve-core-all'
                description = 'All artifacts'
                version     = '1.0.0'
                keywords    = @('copilot')
                agents      = @('agents/team/test.md')
                commands    = @('commands/team/test.md')
                rules       = @('rules/team/test.instructions.md')
                skills      = @('skills/team/test-skill')
                'x-hve'     = [ordered]@{ aggregate = $true }
            },
            [ordered]@{
                name        = 'mixed'
                description = 'Mixed maturity test'
                version     = '1.0.0'
                agents      = @('agents/team/test.md')
                commands    = @('commands/team/test.md')
                'x-hve'     = [ordered]@{
                    componentMaturity = [ordered]@{ 'commands/team/test.md' = 'experimental' }
                }
            }
        )

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

    It 'Generates exactly one root plugin.json manifest' {
        $manifestPath = Join-Path $script:tempDir 'plugins/hve-core-all/plugin.json'
        Test-Path $manifestPath | Should -BeTrue
        $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
        $manifest.name | Should -Be 'hve-core-all'

        $manifests = @(Get-ChildItem -Path (Join-Path $script:tempDir 'plugins/hve-core-all') -Filter 'plugin.json' -Recurse -File)
        $manifests.Count | Should -Be 1
    }

    It 'Does not emit the legacy manifest location' {
        Test-Path (Join-Path $script:tempDir 'plugins/hve-core-all/.github/plugin/plugin.json') | Should -BeFalse
    }

    It 'Never leaks the x-hve overlay into a root manifest' {
        $manifestText = Get-Content -Path (Join-Path $script:tempDir 'plugins/hve-core-all/plugin.json') -Raw
        $manifestText | Should -Not -Match 'x-hve'
    }

    It 'Materializes instructions under the standard rules directory' {
        Test-Path (Join-Path $script:tempDir 'plugins/hve-core-all/rules/team/test.instructions.md') | Should -BeTrue
        Test-Path (Join-Path $script:tempDir 'plugins/hve-core-all/instructions') | Should -BeFalse
        $manifest = Get-Content -Path (Join-Path $script:tempDir 'plugins/hve-core-all/plugin.json') -Raw | ConvertFrom-Json
        $manifest.rules | Should -Contain 'rules/team/'
    }

    It 'Generates README.md' {
        $readmePath = Join-Path $script:tempDir 'plugins/hve-core-all/README.md'
        Test-Path $readmePath | Should -BeTrue
    }

    It 'Writes one Included Artifacts heading to the durable package document' {
        $headingRepo = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $headingRepo -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $headingRepo '.github/agents/team') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $headingRepo 'plugins') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $headingRepo 'docs/plugins') -Force | Out-Null
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
'@ | Set-Content -Path (Join-Path $headingRepo '.github/agents/team/test.agent.md') -Encoding utf8NoBOM

        New-FixtureCatalog -RepoRoot $headingRepo -Plugins @(
            [ordered]@{
                name        = 'heading-test'
                description = 'Heading writeback test'
                version     = '1.0.0'
                agents      = @('agents/team/test.md')
                'x-hve'     = [ordered]@{ documentation = 'docs/plugins/heading-test.md' }
            }
        )

        $documentPath = Join-Path $headingRepo 'docs/plugins/heading-test.md'
        @"
---
title: Heading Test
description: Heading writeback test
---

Intro text.

## Included Artifacts

<!-- BEGIN AUTO-GENERATED ARTIFACTS -->

Old content.

<!-- END AUTO-GENERATED ARTIFACTS -->
"@ | Set-Content -Path $documentPath -Encoding utf8NoBOM

        Initialize-FixtureRepo -Path $headingRepo

        $result = Invoke-PluginGeneration -RepoRoot $headingRepo -PackageNames @('heading-test') -Refresh -Channel 'PreRelease'

        $result.Success | Should -BeTrue
        $documentContent = Get-Content -Path $documentPath -Raw
        ([regex]::Matches($documentContent, '(?m)^## Included Artifacts$')).Count | Should -Be 1
        $documentContent | Should -Not -Match 'Old content'
        $documentContent | Should -Match '### Chat Agents'

        # The README title comes from the package document frontmatter.
        $readme = Get-Content -Path (Join-Path $headingRepo 'plugins/heading-test/README.md') -Raw
        $readme | Should -Match '(?m)^# Heading Test$'
    }

    It 'Filters to specific package names when provided' {
        $result = Invoke-PluginGeneration -RepoRoot $script:tempDir -PackageNames @('hve-core-all') -Refresh -Channel 'PreRelease'
        $result.PluginCount | Should -Be 1
    }

    It 'Warns for non-existent package names' {
        $result = Invoke-PluginGeneration -RepoRoot $script:tempDir -PackageNames @('nonexistent') -Refresh -Channel 'PreRelease' 3>&1
        $warnings = @($result | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $warnings.Count | Should -BeGreaterOrEqual 1
    }

    It 'Supports DryRun mode' {
        $result = Invoke-PluginGeneration -RepoRoot $script:tempDir -PackageNames @('hve-core-all') -DryRun -Channel 'PreRelease'
        $result.Success | Should -BeTrue
    }

    It 'Returns zero plugins when the catalog declares none' {
        $emptyRoot = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path (Join-Path $emptyRoot 'plugins') -Force | Out-Null
        @{ name = 'test'; version = '1.0.0'; description = 'test'; author = 'test' } |
            ConvertTo-Json | Set-Content -Path (Join-Path $emptyRoot 'package.json')

        New-FixtureCatalog -RepoRoot $emptyRoot -Plugins @()

        $result = Invoke-PluginGeneration -RepoRoot $emptyRoot -PackageNames @('missing-id') -Channel 'PreRelease' 3>&1
        $hashtableResult = $result | Where-Object { $_ -is [hashtable] }
        if ($hashtableResult) {
            $hashtableResult.PluginCount | Should -Be 0
        }
    }

    It 'Applies channel filtering to components' {
        $result = Invoke-PluginGeneration -RepoRoot $script:tempDir -PackageNames @('mixed') -Refresh -Channel 'Stable'
        $result.Success | Should -BeTrue
        Test-Path (Join-Path $script:tempDir 'plugins/mixed/agents/team/test.md') | Should -BeTrue
        Test-Path (Join-Path $script:tempDir 'plugins/mixed/commands/team/test.md') | Should -BeFalse
    }

    It 'Removes orphan files on Refresh' {
        # Create a stale file in plugin dir
        $staleDir = Join-Path $script:tempDir 'plugins/hve-core-all/stale'
        New-Item -ItemType Directory -Path $staleDir -Force | Out-Null
        'stale' | Set-Content -Path (Join-Path $staleDir 'file.txt')

        $result = Invoke-PluginGeneration -RepoRoot $script:tempDir -PackageNames @('hve-core-all') -Refresh -Channel 'PreRelease'
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
            -PackageNames @('hve-core-all') `
            -Refresh -DryRun -Channel 'PreRelease' 6>&1

        $dryRunMessages = @($output | Where-Object { "$_" -match 'DRY RUN.*Would remove orphan' })
        $dryRunMessages.Count | Should -BeGreaterOrEqual 1
    }

    It 'Warns when the catalog declares no packages' {
        $emptyRoot = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path (Join-Path $emptyRoot 'plugins') -Force | Out-Null
        @{ name = 'test'; version = '1.0.0'; description = 'test'; author = 'test' } |
            ConvertTo-Json | Set-Content -Path (Join-Path $emptyRoot 'package.json')

        New-FixtureCatalog -RepoRoot $emptyRoot -Plugins @()

        $result = Invoke-PluginGeneration -RepoRoot $emptyRoot -Channel 'PreRelease' 3>&1
        $warnings = @($result | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $warnings.Count | Should -BeGreaterOrEqual 1
        $warnings[0].Message | Should -Match 'No packages declared'
    }

    It 'Fails when the catalog is absent' {
        $noCatalogRoot = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path (Join-Path $noCatalogRoot 'plugins') -Force | Out-Null
        @{ name = 'test'; version = '1.0.0'; description = 'test'; author = 'test' } |
            ConvertTo-Json | Set-Content -Path (Join-Path $noCatalogRoot 'package.json')

        { Invoke-PluginGeneration -RepoRoot $noCatalogRoot -Channel 'PreRelease' } |
            Should -Throw '*Marketplace catalog not found*'
    }

    Context 'Orphan Cleanup' {
        It 'Removes orphan files after overwrite-in-place' {
            $staleDir = Join-Path $script:tempDir 'plugins/hve-core-all/orphan-test'
            New-Item -ItemType Directory -Path $staleDir -Force | Out-Null
            'stale' | Set-Content -Path (Join-Path $staleDir 'leftover.txt')

            $result = Invoke-PluginGeneration -RepoRoot $script:tempDir -PackageNames @('hve-core-all') -Refresh -Channel 'PreRelease'
            $result.Success | Should -BeTrue
            Test-Path (Join-Path $staleDir 'leftover.txt') | Should -BeFalse
            Test-Path (Join-Path $script:tempDir 'plugins/hve-core-all/README.md') | Should -BeTrue
        }

        It 'Preserves generated files during cleanup' {
            # Run a fresh Refresh to get clean state
            Invoke-PluginGeneration -RepoRoot $script:tempDir -PackageNames @('hve-core-all') -Refresh -Channel 'PreRelease' | Out-Null

            $pluginDir = Join-Path $script:tempDir 'plugins/hve-core-all'
            Test-Path (Join-Path $pluginDir 'README.md') | Should -BeTrue
            Test-Path (Join-Path $pluginDir 'plugin.json') | Should -BeTrue
            Test-Path (Join-Path $pluginDir 'docs/templates') | Should -BeTrue
            Test-Path (Join-Path $pluginDir 'scripts/lib') | Should -BeTrue
        }

        It 'Removes empty directories after orphan cleanup' {
            $nestedOrphan = Join-Path $script:tempDir 'plugins/hve-core-all/stale-dir/nested'
            New-Item -ItemType Directory -Path $nestedOrphan -Force | Out-Null
            'leftover' | Set-Content -Path (Join-Path $nestedOrphan 'leftover.txt')

            $result = Invoke-PluginGeneration -RepoRoot $script:tempDir -PackageNames @('hve-core-all') -Refresh -Channel 'PreRelease'
            $result.Success | Should -BeTrue
            Test-Path (Join-Path $script:tempDir 'plugins/hve-core-all/stale-dir') | Should -BeFalse
        }

        It 'DryRun logs orphan files without removing them' {
            $orphanDir = Join-Path $script:tempDir 'plugins/hve-core-all/dry-orphan'
            New-Item -ItemType Directory -Path $orphanDir -Force | Out-Null
            'keep-me' | Set-Content -Path (Join-Path $orphanDir 'persist.txt')

            $output = Invoke-PluginGeneration -RepoRoot $script:tempDir `
                -PackageNames @('hve-core-all') `
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
            (Join-Path $script:matRepo 'plugins')
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

        New-FixtureCatalog -RepoRoot $script:matRepo -Plugins @(
            [ordered]@{
                name        = 'mat-test'
                description = 'Materialization fixture'
                version     = '1.0.0'
                agents      = @('agents/team/example.md')
                commands    = @('commands/team/example.md')
                rules       = @('rules/team/example.instructions.md')
                skills      = @('skills/team/demo')
            }
        )

        Initialize-FixtureRepo -Path $script:matRepo

        # Untracked residue written after staging so it is never in the index.
        Set-Content -Path (Join-Path $script:matSkillSource 'untracked-sentinel.md') -Value 'sentinel'
        New-Item -ItemType Directory -Path (Join-Path $script:matSkillSource '.venv') -Force | Out-Null
        Set-Content -Path (Join-Path $script:matSkillSource '.venv/pyvenv.cfg') -Value 'home = /usr'

        Invoke-PluginGeneration -RepoRoot $script:matRepo -PackageNames @('mat-test') -Refresh -Channel 'PreRelease' | Out-Null
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

        Invoke-PluginGeneration -RepoRoot $script:matRepo -PackageNames @('mat-test') -Refresh -Channel 'PreRelease' | Out-Null

        $after = @(Get-ChildItem -LiteralPath $script:matPluginDir -Recurse -File -Force |
                Sort-Object FullName |
                ForEach-Object { "$($_.FullName)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" })

        $before.Count | Should -BeGreaterThan 0
        $after | Should -Be $before
    }

    It 'Detects a file placed manually inside a materialized directory' {
        $intruder = Join-Path $script:matPluginDir 'skills/team/demo/references/nested/intruder.md'
        Set-Content -Path $intruder -Value 'manual'

        Invoke-PluginGeneration -RepoRoot $script:matRepo -PackageNames @('mat-test') -Refresh -Channel 'PreRelease' | Out-Null

        Test-Path $intruder | Should -BeFalse
        Test-Path (Join-Path $script:matPluginDir 'skills/team/demo/references/nested/deep.md') | Should -BeTrue
    }

    It 'Removes generated output for a component dropped from the catalog' {
        Test-Path (Join-Path $script:matPluginDir 'commands/team/example.md') | Should -BeTrue

        New-FixtureCatalog -RepoRoot $script:matRepo -Plugins @(
            [ordered]@{
                name        = 'mat-test'
                description = 'Materialization fixture'
                version     = '1.0.0'
                agents      = @('agents/team/example.md')
                skills      = @('skills/team/demo')
            }
        )

        Invoke-PluginGeneration -RepoRoot $script:matRepo -PackageNames @('mat-test') -Refresh -Channel 'PreRelease' | Out-Null

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
        New-Item -ItemType Directory -Path (Join-Path $script:ceilingRepo 'plugins') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:ceilingRepo '.github/skills/team/bulky') -Force | Out-Null
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
'@ | Set-Content -Path (Join-Path $script:ceilingRepo '.github/skills/team/bulky/SKILL.md')

        [System.IO.File]::WriteAllBytes(
            (Join-Path $script:ceilingRepo '.github/skills/team/bulky/payload.bin'),
            [byte[]]::new(2MB)
        )

        New-FixtureCatalog -RepoRoot $script:ceilingRepo -Plugins @(
            [ordered]@{
                name        = 'bulky-col'
                description = 'Oversize generation fixture'
                version     = '1.0.0'
                skills      = @('skills/team/bulky')
            }
        )

        Initialize-FixtureRepo -Path $script:ceilingRepo
    }

    It 'Fails generation when materialized output exceeds the ceiling' {
        {
            Invoke-PluginGeneration -RepoRoot $script:ceilingRepo -PackageNames @('bulky-col') `
                -Refresh -Channel 'PreRelease' -MaxTotalSizeMB 1
        } | Should -Throw '*bulky-col*'
    }

    It 'Succeeds under the default ceiling' {
        $result = Invoke-PluginGeneration -RepoRoot $script:ceilingRepo -PackageNames @('bulky-col') `
            -Refresh -Channel 'PreRelease'
        $result.Success | Should -BeTrue
    }
}

Describe 'Invoke-PluginGeneration - frozen collection inputs' {
    BeforeAll {
        $script:freezeRepo = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path (Join-Path $script:freezeRepo 'plugins') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:freezeRepo 'collections') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:freezeRepo '.github/agents/team') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:freezeRepo 'docs/templates') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:freezeRepo 'scripts/lib') -Force | Out-Null
        Set-Content -Path (Join-Path $script:freezeRepo 'docs/templates/sample.md') -Value 'template'
        Set-Content -Path (Join-Path $script:freezeRepo 'scripts/lib/sample.sh') -Value 'echo lib'

        @{ name = 'hve-core'; version = '1.0.0'; description = 'test'; author = 'test-author' } |
            ConvertTo-Json | Set-Content -Path (Join-Path $script:freezeRepo 'package.json')

        Set-Content -Path (Join-Path $script:freezeRepo '.github/agents/team/example.agent.md') `
            -Value "---`ndescription: `"Example agent`"`n---"

        Set-Content -Path (Join-Path $script:freezeRepo 'collections/frozen.collection.yml') -Value "id: frozen`n"
        Set-Content -Path (Join-Path $script:freezeRepo 'collections/frozen.collection.md') -Value "# Frozen`n"

        New-FixtureCatalog -RepoRoot $script:freezeRepo -Plugins @(
            [ordered]@{
                name        = 'frozen'
                description = 'Freeze fixture'
                version     = '1.0.0'
                agents      = @('agents/team/example.md')
            }
        )

        Initialize-FixtureRepo -Path $script:freezeRepo
    }

    It 'Leaves collection YAML and Markdown untouched during generation' {
        $before = Get-CollectionFreezeSnapshot -RepoRoot $script:freezeRepo
        $before.Keys.Count | Should -Be 2

        Invoke-PluginGeneration -RepoRoot $script:freezeRepo -PackageNames @('frozen') -Refresh -Channel 'PreRelease' | Out-Null

        Assert-CollectionFreeze -RepoRoot $script:freezeRepo -Snapshot $before | Should -BeTrue
    }

    It 'Fails when a frozen collection input is modified' {
        $before = Get-CollectionFreezeSnapshot -RepoRoot $script:freezeRepo
        Set-Content -Path (Join-Path $script:freezeRepo 'collections/frozen.collection.md') -Value "# Frozen edited`n"

        { Assert-CollectionFreeze -RepoRoot $script:freezeRepo -Snapshot $before } |
            Should -Throw '*frozen.collection.md*'
    }
}

Describe 'Invoke-PluginGeneration - JSON-only inputs' {
    BeforeAll {
        $script:jsonOnlyRepo = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path (Join-Path $script:jsonOnlyRepo 'plugins') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:jsonOnlyRepo '.github/agents/team') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:jsonOnlyRepo '.github/prompts/team') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:jsonOnlyRepo '.github/instructions/team') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:jsonOnlyRepo '.github/skills/team/demo') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:jsonOnlyRepo 'docs/templates') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:jsonOnlyRepo 'scripts/lib') -Force | Out-Null
        Set-Content -Path (Join-Path $script:jsonOnlyRepo 'docs/templates/sample.md') -Value 'template'
        Set-Content -Path (Join-Path $script:jsonOnlyRepo 'scripts/lib/sample.sh') -Value 'echo lib'

        @{ name = 'hve-core'; version = '1.0.0'; description = 'test'; author = 'test-author' } |
            ConvertTo-Json | Set-Content -Path (Join-Path $script:jsonOnlyRepo 'package.json')

        Set-Content -Path (Join-Path $script:jsonOnlyRepo '.github/agents/team/a.agent.md') `
            -Value "---`ndescription: Agent A`n---"
        Set-Content -Path (Join-Path $script:jsonOnlyRepo '.github/prompts/team/p.prompt.md') `
            -Value "---`ndescription: Prompt P`n---"
        Set-Content -Path (Join-Path $script:jsonOnlyRepo '.github/instructions/team/i.instructions.md') `
            -Value "---`ndescription: Instruction I`napplyTo: `"**`"`n---"
        Set-Content -Path (Join-Path $script:jsonOnlyRepo '.github/skills/team/demo/SKILL.md') `
            -Value "---`nname: demo`ndescription: Demo skill`n---"

        New-FixtureCatalog -RepoRoot $script:jsonOnlyRepo -Plugins @(
            [ordered]@{
                name        = 'json-only'
                description = 'JSON-only generation fixture'
                version     = '1.0.0'
                author      = [ordered]@{ name = 'Microsoft'; url = 'https://www.microsoft.com' }
                homepage    = 'https://example.invalid'
                repository  = 'https://example.invalid'
                license     = 'MIT'
                keywords    = @('json', 'only')
                agents      = @('agents/team/a.md')
                commands    = @('commands/team/p.md')
                rules       = @('rules/team/i.instructions.md')
                skills      = @('skills/team/demo')
            }
        )

        Initialize-FixtureRepo -Path $script:jsonOnlyRepo

        $script:jsonOnlyResult = Invoke-PluginGeneration -RepoRoot $script:jsonOnlyRepo `
            -PackageNames @('json-only') -Refresh -Channel 'PreRelease'
        $script:jsonOnlyRoot = Join-Path $script:jsonOnlyRepo 'plugins/json-only'
    }

    It 'Generates with no collections directory present' {
        Test-Path (Join-Path $script:jsonOnlyRepo 'collections') | Should -BeFalse
        $script:jsonOnlyResult.Success | Should -BeTrue
        $script:jsonOnlyResult.PluginCount | Should -Be 1
    }

    It 'Materializes exactly the declared component inventory' {
        $expected = @(
            'agents/team/a.md',
            'commands/team/p.md',
            'docs/templates/sample.md',
            'plugin.json',
            'README.md',
            'rules/team/i.instructions.md',
            'scripts/lib/sample.sh',
            'skills/team/demo/SKILL.md'
        )
        $actual = @(Get-ChildItem -LiteralPath $script:jsonOnlyRoot -Recurse -File -Force |
                ForEach-Object { [System.IO.Path]::GetRelativePath($script:jsonOnlyRoot, $_.FullName) -replace '\\', '/' } |
                Sort-Object)
        $actual | Should -Be $expected
    }

    It 'Keeps every generated path inside the package root' {
        $escaping = @(Get-ChildItem -LiteralPath $script:jsonOnlyRoot -Recurse -File -Force |
                Where-Object { -not $_.FullName.StartsWith($script:jsonOnlyRoot) })
        $escaping.Count | Should -Be 0
    }

    It 'Mirrors catalog provenance in the root manifest' {
        $manifest = Get-Content -LiteralPath (Join-Path $script:jsonOnlyRoot 'plugin.json') -Raw | ConvertFrom-Json
        $manifest.author.name | Should -Be 'Microsoft'
        $manifest.author.url | Should -Be 'https://www.microsoft.com'
        $manifest.license | Should -Be 'MIT'
        $manifest.homepage | Should -Be 'https://example.invalid'
        $manifest.repository | Should -Be 'https://example.invalid'
        $manifest.keywords | Should -Be @('json', 'only')
        $manifest.agents | Should -Be @('agents/team/')
        $manifest.commands | Should -Be @('commands/team/')
        $manifest.rules | Should -Be @('rules/team/')
        $manifest.skills | Should -Be @('skills/team/demo/')
    }

    It 'Leaves the production catalog untouched by generation' {
        $catalogPath = Join-Path $script:jsonOnlyRepo '.github/plugin/marketplace.json'
        $before = (Get-FileHash -LiteralPath $catalogPath -Algorithm SHA256).Hash
        Invoke-PluginGeneration -RepoRoot $script:jsonOnlyRepo -PackageNames @('json-only') -Refresh -Channel 'PreRelease' | Out-Null
        (Get-FileHash -LiteralPath $catalogPath -Algorithm SHA256).Hash | Should -Be $before
    }

    It 'Produces byte-identical output across two consecutive refresh runs' {
        $digest = {
            @(Get-ChildItem -LiteralPath $script:jsonOnlyRoot -Recurse -File -Force |
                    Sort-Object FullName |
                    ForEach-Object { "$([System.IO.Path]::GetRelativePath($script:jsonOnlyRoot, $_.FullName))|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" }) -join "`n"
        }

        $first = & $digest
        Invoke-PluginGeneration -RepoRoot $script:jsonOnlyRepo -PackageNames @('json-only') -Refresh -Channel 'PreRelease' | Out-Null
        (& $digest) | Should -Be $first
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

    It 'Defaults to refresh when no PackageNames, Refresh, or DryRun provided' {
        Mock Get-Module { return @{ Name = 'PowerShell-Yaml' } } -ParameterFilter { $ListAvailable -and $Name -eq 'PowerShell-Yaml' }
        Mock Import-Module {}
        Mock Invoke-PluginGeneration { return @{ Success = $true; PluginCount = 1 } }

        $scriptPath = "$PSScriptRoot/../../plugins/Generate-Plugins.ps1"
        Start-PluginGeneration -ScriptPath $scriptPath -Channel 'PreRelease' | Out-Null

        Should -Invoke Invoke-PluginGeneration -Times 1 -ParameterFilter { $Refresh -eq $true }
    }

    It 'Does not force refresh when PackageNames are provided' {
        Mock Get-Module { return @{ Name = 'PowerShell-Yaml' } } -ParameterFilter { $ListAvailable -and $Name -eq 'PowerShell-Yaml' }
        Mock Import-Module {}
        Mock Invoke-PluginGeneration { return @{ Success = $true; PluginCount = 1 } }

        $scriptPath = "$PSScriptRoot/../../plugins/Generate-Plugins.ps1"
        Start-PluginGeneration -ScriptPath $scriptPath -PackageNames @('test') -Channel 'PreRelease' | Out-Null

        Should -Invoke Invoke-PluginGeneration -Times 1 -ParameterFilter { $Refresh -eq $false }
    }
}
