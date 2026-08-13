#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../plugins/Modules/PluginHelpers.psm1') -Force
    Mock Write-Warning {} -ModuleName PluginHelpers
}

Describe 'New-PluginManifestContent' -Tag 'Unit' {
    Context 'when only required identity is supplied' {
        BeforeAll {
            $script:identityManifest = New-PluginManifestContent -PackageName 'rpi' -Description 'RPI workflow' -Version '9.9.9'
        }

        It 'Emits identity keys in a fixed order' {
            @($script:identityManifest.Keys) | Should -Be @('name', 'description', 'version')
        }

        It 'Mirrors the supplied identity values' {
            $script:identityManifest['name'] | Should -BeExactly 'rpi'
            $script:identityManifest['description'] | Should -BeExactly 'RPI workflow'
            $script:identityManifest['version'] | Should -BeExactly '9.9.9'
        }

        It 'Omits every component key when no component is declared' {
            foreach ($componentKey in @('agents', 'commands', 'rules', 'skills', 'hooks')) {
                $script:identityManifest.Contains($componentKey) | Should -BeFalse
            }
        }

        It 'Omits provenance keys that were not supplied' {
            foreach ($provenanceKey in @('author', 'homepage', 'repository', 'license', 'keywords')) {
                $script:identityManifest.Contains($provenanceKey) | Should -BeFalse
            }
        }
    }

    Context 'when empty component collections are supplied' {
        BeforeAll {
            $script:emptyManifest = New-PluginManifestContent -PackageName 'rpi' -Description 'RPI workflow' -Version '9.9.9' `
                -AgentPaths @() -CommandPaths @() -RulePaths @() -SkillPaths @() -HookPaths @() -Keywords @()
        }

        It 'Emits identity keys only' {
            @($script:emptyManifest.Keys) | Should -Be @('name', 'description', 'version')
        }
    }

    Context 'when every provenance and component value is supplied' {
        BeforeAll {
            $script:fullManifest = New-PluginManifestContent -PackageName 'rpi' -Description 'RPI workflow' -Version '9.9.9' `
                -Author ([ordered]@{ name = 'Contoso'; url = 'https://contoso.example' }) `
                -Homepage 'https://contoso.example/hve' `
                -Repository 'https://github.com/contoso/contoso-hve' `
                -License 'MIT' `
                -Keywords @('rpi', 'workflow') `
                -AgentPaths @('../../.github/agents/rpi/rpi-agent.agent.md', '../../.github/agents/hve-core/hve-agent.agent.md') `
                -CommandPaths @('../../.github/prompts/rpi/rpi.prompt.md') `
                -RulePaths @('../../.github/instructions/shared/hve-core-location.instructions.md') `
                -SkillPaths @('../../.github/skills/rpi/rpi-plan', '../../.github/skills/rpi/rpi-research') `
                -HookPaths @('../../.github/hooks/rpi/telemetry.json')
        }

        It 'Emits every key in a fixed order' {
            @($script:fullManifest.Keys) | Should -Be @(
                'name', 'description', 'version', 'author', 'homepage',
                'repository', 'license', 'keywords', 'agents', 'commands',
                'rules', 'skills', 'hooks'
            )
        }

        It 'Mirrors provenance verbatim' {
            $script:fullManifest['author']['name'] | Should -BeExactly 'Contoso'
            $script:fullManifest['author']['url'] | Should -BeExactly 'https://contoso.example'
            $script:fullManifest['homepage'] | Should -BeExactly 'https://contoso.example/hve'
            $script:fullManifest['repository'] | Should -BeExactly 'https://github.com/contoso/contoso-hve'
            $script:fullManifest['license'] | Should -BeExactly 'MIT'
            @($script:fullManifest['keywords']) | Should -Be @('rpi', 'workflow')
        }

        It 'Sorts declared component references' {
            @($script:fullManifest['agents']) | Should -Be @('../../.github/agents/hve-core/hve-agent.agent.md', '../../.github/agents/rpi/rpi-agent.agent.md')
            @($script:fullManifest['skills']) | Should -Be @('../../.github/skills/rpi/rpi-plan', '../../.github/skills/rpi/rpi-research')
        }

        It 'Emits hooks as a single path string rather than an array' {
            $script:fullManifest['hooks'] | Should -BeOfType [string]
            $script:fullManifest['hooks'] | Should -BeExactly '../../.github/hooks/rpi/telemetry.json'
        }
    }

    Context 'when component input order varies' {
        It 'Produces byte-identical serialized manifests' {
            $firstOrder = New-PluginManifestContent -PackageName 'rpi' -Description 'RPI workflow' -Version '9.9.9' `
                -AgentPaths @('../../.github/agents/zulu/z.agent.md', '../../.github/agents/alpha/a.agent.md') -SkillPaths @('../../.github/skills/b/b', '../../.github/skills/a/a') -Keywords @('one', 'two')
            $secondOrder = New-PluginManifestContent -PackageName 'rpi' -Description 'RPI workflow' -Version '9.9.9' `
                -AgentPaths @('../../.github/agents/alpha/a.agent.md', '../../.github/agents/zulu/z.agent.md') -SkillPaths @('../../.github/skills/a/a', '../../.github/skills/b/b') -Keywords @('one', 'two')

            ($firstOrder | ConvertTo-Json -Depth 10) | Should -BeExactly ($secondOrder | ConvertTo-Json -Depth 10)
        }
    }

    Context 'when more than one hook manifest is declared' {
        BeforeAll {
            $script:multiHookManifest = New-PluginManifestContent -PackageName 'rpi' -Description 'RPI workflow' -Version '9.9.9' `
                -HookPaths @('../../.github/hooks/zulu/late.json', '../../.github/hooks/alpha/early.json')
        }

        It 'Selects the first path in sorted order' {
            $script:multiHookManifest['hooks'] | Should -BeExactly '../../.github/hooks/alpha/early.json'
        }

        It 'Warns that only one hook manifest is referenced' {
            Should -Invoke Write-Warning -ModuleName PluginHelpers -Scope Context -Times 1 -Exactly -ParameterFilter {
                $Message -match 'declares 2 hook manifests' -and $Message -match 'hooks/alpha/early\.json'
            }
        }
    }

    Context 'when the author has no usable name' {
        It 'Omits the author key for a whitespace name' {
            $manifest = New-PluginManifestContent -PackageName 'rpi' -Description 'RPI workflow' -Version '9.9.9' `
                -Author ([ordered]@{ name = '   ' })
            $manifest.Contains('author') | Should -BeFalse
        }

        It 'Omits the author key for a dictionary without a name' {
            $manifest = New-PluginManifestContent -PackageName 'rpi' -Description 'RPI workflow' -Version '9.9.9' `
                -Author ([ordered]@{ url = 'https://contoso.example' })
            $manifest.Contains('author') | Should -BeFalse
        }
    }

    Context 'when catalog-only metadata could leak' {
        BeforeAll {
            $script:leakManifest = New-PluginManifestContent -PackageName 'rpi' -Description 'RPI workflow' -Version '9.9.9' `
                -Author ([ordered]@{ name = 'Contoso' }) -AgentPaths @('../../.github/agents/rpi/rpi-agent.agent.md') -HookPaths @('../../.github/hooks/rpi/telemetry.json')
            $script:leakJson = $script:leakManifest | ConvertTo-Json -Depth 10
        }

        It 'Declares no catalog overlay key' {
            @($script:leakManifest.Keys) | Should -Not -Contain 'x-hve'
            @($script:leakManifest.Keys) | Should -Not -Contain 'metadata'
        }

        It 'Serializes without the catalog overlay or metadata token' {
            $script:leakJson | Should -Not -Match 'x-hve'
            $script:leakJson | Should -Not -Match '"metadata"'
        }
    }
}

AfterAll {
    Remove-Module PluginHelpers -Force -ErrorAction SilentlyContinue
}
