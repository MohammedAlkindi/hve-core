#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../lib/Modules/MarketplaceHelpers.psm1') -Force

    # Expected values are authored here independently of the module under test.
    $script:ExpectedFields = @('agents', 'commands', 'rules', 'skills', 'hooks')
    $script:ExpectedKinds = @('agent', 'prompt', 'instruction', 'skill', 'hook')
    $script:ExpectedMetadataKeys = @('displayName', 'maturity', 'componentMaturity', 'documentation', 'profiles')
}

Describe 'Get-MarketplaceComponentFieldMap' -Tag 'Unit' {
    BeforeAll {
        $script:FieldMap = Get-MarketplaceComponentFieldMap
    }

    It 'Declares exactly five component fields' {
        $script:FieldMap.Count | Should -Be 5
    }

    It 'Preserves the canonical field order' {
        ($script:FieldMap.Keys -join '|') | Should -BeExactly 'agents|commands|rules|skills|hooks'
    }

    It 'Preserves the canonical kind order' {
        ($script:FieldMap.Values -join '|') | Should -BeExactly 'agent|prompt|instruction|skill|hook'
    }

    It 'Maps field <Field> to kind <Kind>' -ForEach @(
        @{ Field = 'agents'; Kind = 'agent' }
        @{ Field = 'commands'; Kind = 'prompt' }
        @{ Field = 'rules'; Kind = 'instruction' }
        @{ Field = 'skills'; Kind = 'skill' }
        @{ Field = 'hooks'; Kind = 'hook' }
    ) {
        $script:FieldMap[$Field] | Should -BeExactly $Kind
    }

    It 'Returns an ordered dictionary' {
        $script:FieldMap | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
    }
}

Describe 'Get-MarketplaceMetadataKey' -Tag 'Unit' {
    BeforeAll {
        $script:MetadataKeys = Get-MarketplaceMetadataKey
    }

    It 'Returns a flat collection of five keys' {
        $script:MetadataKeys.Count | Should -Be 5
        $script:MetadataKeys[0] | Should -BeOfType [string]
    }

    It 'Returns the closed metadata key set in declaration order' {
        ($script:MetadataKeys -join '|') | Should -BeExactly 'displayName|maturity|componentMaturity|documentation|profiles'
    }

    It 'Includes metadata key <Key>' -ForEach @(
        @{ Key = 'displayName' }
        @{ Key = 'maturity' }
        @{ Key = 'componentMaturity' }
        @{ Key = 'documentation' }
        @{ Key = 'profiles' }
    ) {
        $script:MetadataKeys | Should -Contain $Key
    }

    It 'Keeps metadata keys disjoint from component field <Field>' -ForEach @(
        @{ Field = 'agents' }
        @{ Field = 'commands' }
        @{ Field = 'rules' }
        @{ Field = 'skills' }
        @{ Field = 'hooks' }
    ) {
        $script:MetadataKeys | Should -Not -Contain $Field
    }

    It 'Keeps component fields disjoint from the metadata key set' {
        foreach ($metadataKey in $script:ExpectedMetadataKeys) {
            $script:ExpectedFields | Should -Not -Contain $metadataKey
        }
    }
}

Describe 'Get-MarketplaceComponentSourceRoot' -Tag 'Unit' {
    BeforeAll {
        $script:SourceRoots = Get-MarketplaceComponentSourceRoot
    }

    It 'Describes exactly the five component fields in order' {
        $script:SourceRoots.Count | Should -Be 5
        ($script:SourceRoots.Keys -join '|') | Should -BeExactly 'agents|commands|rules|skills|hooks'
    }

    It 'Describes <Field> as <Kind> rooted at <SourceRoot>' -ForEach @(
        @{ Field = 'agents'; Kind = 'agent'; SourceRoot = '.github/agents'; SourceSuffix = '.agent.md'; PackageSuffix = '.md' }
        @{ Field = 'commands'; Kind = 'prompt'; SourceRoot = '.github/prompts'; SourceSuffix = '.prompt.md'; PackageSuffix = '.md' }
        @{ Field = 'rules'; Kind = 'instruction'; SourceRoot = '.github/instructions'; SourceSuffix = '.instructions.md'; PackageSuffix = '.instructions.md' }
        @{ Field = 'skills'; Kind = 'skill'; SourceRoot = '.github/skills'; SourceSuffix = ''; PackageSuffix = '' }
        @{ Field = 'hooks'; Kind = 'hook'; SourceRoot = '.github/hooks'; SourceSuffix = '.json'; PackageSuffix = '.json' }
    ) {
        $descriptor = $script:SourceRoots[$Field]
        $descriptor.Kind | Should -BeExactly $Kind
        $descriptor.SourceRoot | Should -BeExactly $SourceRoot
        $descriptor.SourceSuffix | Should -BeExactly $SourceSuffix
        $descriptor.PackageSuffix | Should -BeExactly $PackageSuffix
    }

    It 'Declares no catalog root for field <Field>' -ForEach @(
        @{ Field = 'agents' }
        @{ Field = 'commands' }
        @{ Field = 'rules' }
        @{ Field = 'skills' }
        @{ Field = 'hooks' }
    ) {
        $script:SourceRoots[$Field].ContainsKey('CatalogRoot') | Should -BeFalse
    }
}

Describe 'Get-PluginSubdirectory and Get-MarketplaceComponentField' -Tag 'Unit' {
    It 'Places kind <Kind> in package directory <Field>' -ForEach @(
        @{ Kind = 'agent'; Field = 'agents' }
        @{ Kind = 'prompt'; Field = 'commands' }
        @{ Kind = 'instruction'; Field = 'rules' }
        @{ Kind = 'skill'; Field = 'skills' }
        @{ Kind = 'hook'; Field = 'hooks' }
    ) {
        Get-PluginSubdirectory -Kind $Kind | Should -BeExactly $Field
        Get-MarketplaceComponentField -Kind $Kind | Should -BeExactly $Field
    }

    It 'Rejects an unsupported kind' {
        { Get-PluginSubdirectory -Kind 'workflow' } | Should -Throw -ExpectedMessage '*does not belong to the set*'
    }
}

Describe 'Resolve-MarketplaceComponentPath' -Tag 'Unit' {
    Context 'when the path is acceptable' {
        It 'Returns the reference unchanged and reports no error' {
            $resolved = Resolve-MarketplaceComponentPath -Path '../../.github/agents/coding-standards/code-review.agent.md'
            $resolved.Path | Should -BeExactly '../../.github/agents/coding-standards/code-review.agent.md'
            $resolved.Error | Should -BeExactly ''
        }

        It 'Trims surrounding whitespace' {
            $resolved = Resolve-MarketplaceComponentPath -Path '   ../../.github/agents/demo/first.agent.md   '
            $resolved.Path | Should -BeExactly '../../.github/agents/demo/first.agent.md'
            $resolved.Error | Should -BeExactly ''
        }

        It 'Trims a trailing slash from a directory component' {
            $resolved = Resolve-MarketplaceComponentPath -Path '../../.github/skills/rpi/rpi-plan/'
            $resolved.Path | Should -BeExactly '../../.github/skills/rpi/rpi-plan'
            $resolved.Error | Should -BeExactly ''
        }

        It 'Normalizes a repository-relative metadata path unchanged' {
            $resolved = Resolve-MarketplaceComponentPath -Path 'docs/plugins/rpi.md'
            $resolved.Path | Should -BeExactly 'docs/plugins/rpi.md'
            $resolved.Error | Should -BeExactly ''
        }
    }

    Context 'when the path is rejected' {
        It 'Rejects <Description>' -ForEach @(
            @{ Description = 'an empty path'; Path = ''; Expected = 'component path must be a non-empty string' }
            @{ Description = 'a whitespace-only path'; Path = '    '; Expected = 'component path must be a non-empty string' }
            @{ Description = 'a backslash separator'; Path = '..\..\.github\agents\demo\first.agent.md'; Expected = "component path '..\..\.github\agents\demo\first.agent.md' must use forward slashes" }
            @{ Description = 'a rooted POSIX path'; Path = '/agents/demo/first.agent.md'; Expected = "component path '/agents/demo/first.agent.md' must be relative to the package root" }
            @{ Description = 'a Windows drive path'; Path = 'C:/agents/demo/first.agent.md'; Expected = "component path 'C:/agents/demo/first.agent.md' must be relative to the package root" }
            @{ Description = 'an empty path segment'; Path = '../../.github/agents//first.agent.md'; Expected = "component path '../../.github/agents//first.agent.md' must not contain empty path segments" }
            @{ Description = 'a further parent traversal segment'; Path = '../../.github/agents/../../secrets.md'; Expected = "component path '../../.github/agents/../../secrets.md' must not traverse beyond the repository root" }
            @{ Description = 'a current-directory segment'; Path = '../../.github/agents/./first.agent.md'; Expected = "component path '../../.github/agents/./first.agent.md' must not contain relative path segments" }
            @{ Description = 'a bare package-root traversal'; Path = '../../'; Expected = "component path '../../' must name a canonical source below '../../'" }
        ) {
            $resolved = Resolve-MarketplaceComponentPath -Path $Path
            $resolved.Error | Should -BeExactly $Expected
            $resolved.Path | Should -BeExactly ''
        }

        It 'Rejects an embedded control character' {
            $candidate = "../../.github/agents/demo/$([char]9)first.agent.md"
            $resolved = Resolve-MarketplaceComponentPath -Path $candidate
            $resolved.Error | Should -BeExactly "component path '$candidate' must not contain control characters"
            $resolved.Path | Should -BeExactly ''
        }

        It 'Rejects a null path' {
            $resolved = Resolve-MarketplaceComponentPath -Path $null
            $resolved.Error | Should -BeExactly 'component path must be a non-empty string'
        }
    }
}

Describe 'Marketplace source and manifest reference round-trip' -Tag 'Unit' {
    It 'Projects <SourcePath> to <PackagePath>' -ForEach @(
        @{ Kind = 'agent'; Field = 'agents'; SourcePath = '.github/agents/rpi/rpi-agent.agent.md'; PackagePath = '../../.github/agents/rpi/rpi-agent.agent.md' }
        @{ Kind = 'prompt'; Field = 'commands'; SourcePath = '.github/prompts/ado/create-pull-request.prompt.md'; PackagePath = '../../.github/prompts/ado/create-pull-request.prompt.md' }
        @{ Kind = 'instruction'; Field = 'rules'; SourcePath = '.github/instructions/hve-core/markdown.instructions.md'; PackagePath = '../../.github/instructions/hve-core/markdown.instructions.md' }
        @{ Kind = 'skill'; Field = 'skills'; SourcePath = '.github/skills/rpi/rpi-plan'; PackagePath = '../../.github/skills/rpi/rpi-plan' }
        @{ Kind = 'hook'; Field = 'hooks'; SourcePath = '.github/hooks/hve-core/hooks.json'; PackagePath = '../../.github/hooks/hve-core/hooks.json' }
    ) {
        Get-MarketplacePackagePath -SourcePath $SourcePath -Kind $Kind | Should -BeExactly $PackagePath

        $component = Resolve-MarketplaceComponentSource -PackagePath $PackagePath -Field $Field
        $component.SourcePath | Should -BeExactly $SourcePath
        $component.PackagePath | Should -BeExactly $PackagePath
        $component.Kind | Should -BeExactly $Kind
        $component.ContainsKey('CatalogPath') | Should -BeFalse
    }

    It 'Rejects copied-runtime form <PackagePath> in field <Field>' -ForEach @(
        @{ Field = 'commands'; PackagePath = 'commands/ado/create-pull-request.md' }
        @{ Field = 'rules'; PackagePath = 'rules/hve-core/markdown.instructions.md' }
    ) {
        { Resolve-MarketplaceComponentSource -PackagePath $PackagePath -Field $Field } |
            Should -Throw -ExpectedMessage "Component path '$PackagePath' must address its canonical source through the '../../' package-root traversal."
    }

    It 'Projects a root-level source without inventing a subdirectory' {
        Get-MarketplacePackagePath -SourcePath '.github/agents/code-review.agent.md' -Kind 'agent' |
            Should -BeExactly '../../.github/agents/code-review.agent.md'
    }

    It 'Normalizes backslash separators in the source path' {
        Get-MarketplacePackagePath -SourcePath '.github\agents\rpi\rpi-agent.agent.md' -Kind 'agent' |
            Should -BeExactly '../../.github/agents/rpi/rpi-agent.agent.md'
    }

    It 'Rejects a source path outside the canonical root' {
        { Get-MarketplacePackagePath -SourcePath 'docs/agents/rpi-agent.agent.md' -Kind 'agent' } |
            Should -Throw -ExpectedMessage "Source path 'docs/agents/rpi-agent.agent.md' is not under the canonical '.github/agents' root for kind 'agent'."
    }

    It 'Rejects a reference that addresses another canonical root' {
        { Resolve-MarketplaceComponentSource -PackagePath '../../.github/prompts/demo/first.prompt.md' -Field 'agents' } |
            Should -Throw -ExpectedMessage "Component path '../../.github/prompts/demo/first.prompt.md' must address the canonical '.github/agents' root for the 'agents' field."
    }

    It 'Rejects a reference with the wrong extension' {
        { Resolve-MarketplaceComponentSource -PackagePath '../../.github/agents/demo/first.txt' -Field 'agents' } |
            Should -Throw -ExpectedMessage "Component path '../../.github/agents/demo/first.txt' must end with '.agent.md'."
    }

    It 'Rejects a rules reference that does not carry the instruction suffix' {
        { Resolve-MarketplaceComponentSource -PackagePath '../../.github/instructions/demo/style.md' -Field 'rules' } |
            Should -Throw -ExpectedMessage "Component path '../../.github/instructions/demo/style.md' must end with '.instructions.md'."
    }

    It 'Surfaces path validation failures with the field name' {
        { Resolve-MarketplaceComponentSource -PackagePath '..\..\.github\agents\demo\first.agent.md' -Field 'agents' } |
            Should -Throw -ExpectedMessage "Component field 'agents': component path '..\..\.github\agents\demo\first.agent.md' must use forward slashes"
    }
}

Describe 'Test-MarketplaceEntryContract component membership' -Tag 'Unit' {
    Context 'when the entry is fully valid' {
        BeforeAll {
            $script:ValidEntry = @{
                name     = 'demo'
                agents   = @('../../.github/agents/demo/first.agent.md', '../../.github/agents/demo/second.agent.md')
                commands = @('../../.github/prompts/demo/run.prompt.md')
                rules    = @('../../.github/instructions/demo/style.instructions.md')
                skills   = @('../../.github/skills/demo/toolkit')
                hooks    = '../../.github/hooks/demo/hooks.json'
                author   = @{ name = 'Contoso'; url = 'https://example.invalid/contoso' }
                'x-hve'  = @{
                    displayName       = 'Demo Package'
                    maturity          = 'preview'
                    componentMaturity = @{ '../../.github/agents/demo/second.agent.md' = 'experimental' }
                    documentation     = 'docs/plugins/demo.md'
                    profiles          = @{ starter = @('../../.github/agents/demo/first.agent.md', '../../.github/skills/demo/toolkit') }
                }
            }
            $script:ValidErrors = @(Test-MarketplaceEntryContract -Entry $script:ValidEntry)
        }

        It 'Reports no contract errors' {
            $script:ValidErrors.Count | Should -Be 0
        }
    }

    Context 'when membership declarations are malformed' {
        It 'Rejects a null field value' {
            $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; agents = $null })
            $errors | Should -Contain "component field 'agents' must be a path string or an array of path strings"
        }

        It 'Rejects a non-string, non-collection field value' {
            $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; agents = 42 })
            $errors | Should -Contain "component field 'agents' must be a path string or an array of path strings"
        }

        It 'Rejects an empty array' {
            $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; skills = @() })
            $errors | Should -Contain "component field 'skills' must declare at least one path"
        }

        It 'Rejects a non-string element inside an array' {
            $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; agents = @('../../.github/agents/demo/first.agent.md', 42) })
            $errors | Should -Contain "component field 'agents' must contain only path strings"
        }

        It 'Rejects an invalid path and names the offending field' {
            $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; commands = @('../../.github/prompts/../escape.prompt.md') })
            $errors | Should -Contain "component field 'commands': component path '../../.github/prompts/../escape.prompt.md' must not traverse beyond the repository root"
        }

        It 'Rejects a copied-runtime membership path' {
            $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; commands = @('commands/demo/run.md') })
            $errors | Should -Contain "component field 'commands': Component path 'commands/demo/run.md' must address its canonical source through the '../../' package-root traversal."
        }

        It 'Rejects a membership path with the wrong canonical suffix' {
            $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; rules = @('../../.github/instructions/demo/style.md') })
            $errors | Should -Contain "component field 'rules': Component path '../../.github/instructions/demo/style.md' must end with '.instructions.md'."
        }

        It 'Rejects a duplicate path within one field' {
            $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; agents = @('../../.github/agents/demo/first.agent.md', '../../.github/agents/demo/first.agent.md') })
            $errors | Should -Contain "component field 'agents' declares duplicate path '../../.github/agents/demo/first.agent.md'"
        }

        It 'Treats paths that normalize to the same value as duplicates' {
            $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; skills = @('../../.github/skills/demo/toolkit', '../../.github/skills/demo/toolkit/') })
            $errors | Should -Contain "component field 'skills' declares duplicate path '../../.github/skills/demo/toolkit'"
        }

        It 'Rejects the same path declared across two fields' {
            $errors = @(Test-MarketplaceEntryContract -Entry @{
                    name     = 'demo'
                    agents   = @('../../.github/agents/demo/first.agent.md')
                    commands = @('../../.github/agents/demo/first.agent.md')
                })
            ($errors -join ' ') | Should -Match "must address the canonical '\.github/prompts' root for the 'commands' field"
        }

        It 'Accepts a single hooks path string' {
            $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; hooks = '../../.github/hooks/demo/hooks.json' })
            $errors.Count | Should -Be 0
        }

        It 'Rejects a hooks array' {
            $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; hooks = @('../../.github/hooks/demo/hooks.json') })
            $errors | Should -Contain "component field 'hooks' must be a single path string"
        }

        It 'Accepts an entry that declares no component membership' {
            $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo' })
            $errors.Count | Should -Be 0
        }
    }
}

Describe 'Test-MarketplaceEntryContract membership hygiene' -Tag 'Unit' {
    Context 'when a root-level repository artifact is declared' {
        It 'Rejects root-level <PackagePath> in field <Field>' -ForEach @(
            @{ Field = 'agents'; PackagePath = '../../.github/agents/first.agent.md' }
            @{ Field = 'commands'; PackagePath = '../../.github/prompts/run.prompt.md' }
            @{ Field = 'rules'; PackagePath = '../../.github/instructions/style.instructions.md' }
            @{ Field = 'skills'; PackagePath = '../../.github/skills/toolkit' }
        ) {
            $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; $Field = @($PackagePath) })
            $errors | Should -Contain "component path '$PackagePath' is a root-level repository artifact and must not be declared"
        }

        It 'Rejects a root-level hooks manifest' {
            $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; hooks = '../../.github/hooks/hooks.json' })
            $errors | Should -Contain "component path '../../.github/hooks/hooks.json' is a root-level repository artifact and must not be declared"
        }

        It 'Accepts a namespaced artifact' {
            $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; agents = @('../../.github/agents/demo/first.agent.md') })
            $errors.Count | Should -Be 0
        }
    }

    Context 'when an experimental namespace is declared' {
        It 'Rejects <PackagePath> when no componentMaturity is declared' -ForEach @(
            @{ Field = 'agents'; PackagePath = '../../.github/agents/experimental/first.agent.md' }
            @{ Field = 'commands'; PackagePath = '../../.github/prompts/experimental/run.prompt.md' }
            @{ Field = 'rules'; PackagePath = '../../.github/instructions/experimental/style.instructions.md' }
            @{ Field = 'skills'; PackagePath = '../../.github/skills/experimental/toolkit' }
        ) {
            $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; $Field = @($PackagePath) })
            $errors | Should -Contain "component path '$PackagePath' is under an experimental namespace and must declare a non-stable x-hve.componentMaturity"
        }

        It 'Rejects an explicit stable label under an experimental namespace' {
            $errors = @(Test-MarketplaceEntryContract -Entry @{
                    name    = 'demo'
                    agents  = @('../../.github/agents/experimental/first.agent.md')
                    'x-hve' = @{ componentMaturity = @{ '../../.github/agents/experimental/first.agent.md' = 'stable' } }
                })
            $errors | Should -Contain "component path '../../.github/agents/experimental/first.agent.md' is under an experimental namespace and must declare a non-stable x-hve.componentMaturity"
        }

        It 'Accepts non-stable label <Maturity> under an experimental namespace' -ForEach @(
            @{ Maturity = 'preview' }
            @{ Maturity = 'experimental' }
            @{ Maturity = 'deprecated' }
            @{ Maturity = 'removed' }
        ) {
            $errors = @(Test-MarketplaceEntryContract -Entry @{
                    name    = 'demo'
                    agents  = @('../../.github/agents/experimental/first.agent.md')
                    'x-hve' = @{ componentMaturity = @{ '../../.github/agents/experimental/first.agent.md' = $Maturity } }
                })
            $errors.Count | Should -Be 0
        }

        It 'Leaves components outside an experimental namespace on the stable default' {
            $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; agents = @('../../.github/agents/demo/experimental.agent.md') })
            $errors.Count | Should -Be 0
        }
    }
}

Describe 'Test-MarketplaceEntryContract x-hve overlay' -Tag 'Unit' {
    It 'Rejects a non-object overlay' {
        $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; 'x-hve' = 'preview' })
        $errors | Should -Contain 'x-hve must be an object'
    }

    It 'Rejects an unsupported overlay key' {
        $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; 'x-hve' = @{ channel = 'beta' } })
        $errors | Should -Contain "x-hve contains unsupported key 'channel'"
    }

    It 'Accepts every key in the closed metadata set' {
        $errors = @(Test-MarketplaceEntryContract -Entry @{
                name    = 'demo'
                agents  = @('../../.github/agents/demo/first.agent.md')
                'x-hve' = @{
                    displayName       = 'Demo'
                    maturity          = 'stable'
                    componentMaturity = @{ '../../.github/agents/demo/first.agent.md' = 'preview' }
                    documentation     = 'docs/plugins/demo.md'
                    profiles          = @{ starter = @('../../.github/agents/demo/first.agent.md') }
                }
            })
        $errors.Count | Should -Be 0
    }

    It 'Rejects an empty display name' {
        $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; 'x-hve' = @{ displayName = '' } })
        $errors | Should -Contain 'x-hve.displayName must be a non-empty string'
    }

    It 'Accepts package maturity <Value>' -ForEach @(
        @{ Value = 'stable' }
        @{ Value = 'preview' }
        @{ Value = 'experimental' }
        @{ Value = 'deprecated' }
        @{ Value = 'removed' }
    ) {
        $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; 'x-hve' = @{ maturity = $Value } })
        $errors.Count | Should -Be 0
    }

    It 'Rejects package maturity outside the vocabulary' {
        $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; 'x-hve' = @{ maturity = 'beta' } })
        $errors | Should -Contain "x-hve.maturity 'beta' must be one of: stable, preview, experimental, deprecated, removed"
    }

    It 'Rejects a non-object componentMaturity' {
        $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; 'x-hve' = @{ componentMaturity = 'preview' } })
        $errors | Should -Contain 'x-hve.componentMaturity must be an object keyed by component path'
    }

    It 'Rejects a componentMaturity key that is not normalized' {
        $errors = @(Test-MarketplaceEntryContract -Entry @{
                name    = 'demo'
                'x-hve' = @{ componentMaturity = @{ '../../.github/skills/demo/toolkit/' = 'preview' } }
            })
        $errors | Should -Contain "x-hve.componentMaturity key '../../.github/skills/demo/toolkit/' must be a normalized component path"
    }

    It 'Rejects a componentMaturity key that fails path validation' {
        $errors = @(Test-MarketplaceEntryContract -Entry @{
                name    = 'demo'
                'x-hve' = @{ componentMaturity = @{ '..\..\.github\agents\demo\first.agent.md' = 'preview' } }
            })
        $errors | Should -Contain "x-hve.componentMaturity: component path '..\..\.github\agents\demo\first.agent.md' must use forward slashes"
    }

    It 'Rejects a componentMaturity key outside the canonical component roots' {
        $errors = @(Test-MarketplaceEntryContract -Entry @{
                name    = 'demo'
                'x-hve' = @{ componentMaturity = @{ '../../docs/demo/first.md' = 'preview' } }
            })
        $errors | Should -Contain "x-hve.componentMaturity key '../../docs/demo/first.md' must use a package component directory"
    }

    It 'Rejects a componentMaturity value outside the vocabulary' {
        $errors = @(Test-MarketplaceEntryContract -Entry @{
                name    = 'demo'
                'x-hve' = @{ componentMaturity = @{ '../../.github/agents/demo/first.agent.md' = 'beta' } }
            })
        $errors | Should -Contain "x-hve.componentMaturity['../../.github/agents/demo/first.agent.md'] value 'beta' must be one of: stable, preview, experimental, deprecated, removed"
    }

    It 'Accepts a removed componentMaturity tombstone without membership' {
        $errors = @(Test-MarketplaceEntryContract -Entry @{
                name    = 'demo'
                'x-hve' = @{ componentMaturity = @{ '../../.github/skills/demo/retired' = 'removed' } }
            })
        $errors.Count | Should -Be 0
    }

    It 'Rejects a non-string documentation value' {
        $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; 'x-hve' = @{ documentation = 42 } })
        $errors | Should -Contain 'x-hve.documentation must be a repository-relative path string'
    }

    It 'Rejects a documentation path that is not normalized' {
        $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; 'x-hve' = @{ documentation = 'docs/plugins/demo.md/' } })
        $errors | Should -Contain "x-hve.documentation 'docs/plugins/demo.md/' must be a normalized repository-relative path"
    }

    It 'Rejects a documentation path that escapes the repository root' {
        $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; 'x-hve' = @{ documentation = '../secrets.md' } })
        $errors | Should -Contain "x-hve.documentation: component path '../secrets.md' must not traverse beyond the repository root"
    }

    It 'Rejects a non-object profiles overlay' {
        $errors = @(Test-MarketplaceEntryContract -Entry @{ name = 'demo'; 'x-hve' = @{ profiles = 'starter' } })
        $errors | Should -Contain 'x-hve.profiles must be an object keyed by profile name'
    }

    It 'Rejects a profile name outside the identifier vocabulary' {
        $errors = @(Test-MarketplaceEntryContract -Entry @{
                name    = 'demo'
                agents  = @('../../.github/agents/demo/first.agent.md')
                'x-hve' = @{ profiles = @{ 'Starter Profile' = @('../../.github/agents/demo/first.agent.md') } }
            })
        $errors | Should -Contain "x-hve.profiles name 'Starter Profile' must contain only lowercase letters, digits, and hyphens"
    }

    It 'Rejects a profile that is not an array of paths' {
        $errors = @(Test-MarketplaceEntryContract -Entry @{
                name    = 'demo'
                agents  = @('../../.github/agents/demo/first.agent.md')
                'x-hve' = @{ profiles = @{ starter = '../../.github/agents/demo/first.agent.md' } }
            })
        $errors | Should -Contain "x-hve.profiles['starter'] must be an array of component paths"
    }

    It 'Rejects an empty profile' {
        $errors = @(Test-MarketplaceEntryContract -Entry @{
                name    = 'demo'
                agents  = @('../../.github/agents/demo/first.agent.md')
                'x-hve' = @{ profiles = @{ starter = @() } }
            })
        $errors | Should -Contain "x-hve.profiles['starter'] must declare at least one component path"
    }

    It 'Rejects a duplicate profile member' {
        $errors = @(Test-MarketplaceEntryContract -Entry @{
                name    = 'demo'
                agents  = @('../../.github/agents/demo/first.agent.md')
                'x-hve' = @{ profiles = @{ starter = @('../../.github/agents/demo/first.agent.md', '../../.github/agents/demo/first.agent.md') } }
            })
        $errors | Should -Contain "x-hve.profiles['starter'] declares duplicate path '../../.github/agents/demo/first.agent.md'"
    }

    It 'Rejects a profile member that fails path validation' {
        $errors = @(Test-MarketplaceEntryContract -Entry @{
                name    = 'demo'
                agents  = @('../../.github/agents/demo/first.agent.md')
                'x-hve' = @{ profiles = @{ starter = @('../../.github/agents/../escape.agent.md') } }
            })
        $errors | Should -Contain "x-hve.profiles['starter']: component path '../../.github/agents/../escape.agent.md' must not traverse beyond the repository root"
    }

    It 'Rejects a profile member that is not declared component membership' {
        $errors = @(Test-MarketplaceEntryContract -Entry @{
                name    = 'demo'
                agents  = @('../../.github/agents/demo/first.agent.md')
                'x-hve' = @{ profiles = @{ starter = @('../../.github/agents/demo/absent.agent.md') } }
            })
        $errors | Should -Contain "x-hve.profiles['starter'] references '../../.github/agents/demo/absent.agent.md', which is not declared component membership"
    }

    It 'Rejects a profile member from a non-installable field' {
        $errors = @(Test-MarketplaceEntryContract -Entry @{
                name    = 'demo'
                agents  = @('../../.github/agents/demo/first.agent.md')
                hooks   = '../../.github/hooks/demo/hooks.json'
                'x-hve' = @{ profiles = @{ starter = @('../../.github/agents/demo/first.agent.md', '../../.github/hooks/demo/hooks.json') } }
            })
        $errors | Should -Contain "x-hve.profiles['starter'] references '../../.github/hooks/demo/hooks.json' from non-installable field 'hooks'; profiles support only: agents, commands, rules, skills"
    }

    It 'Accepts a profile that selects a subset of declared membership' {
        $errors = @(Test-MarketplaceEntryContract -Entry @{
                name    = 'demo'
                agents  = @('../../.github/agents/demo/first.agent.md', '../../.github/agents/demo/second.agent.md')
                skills  = @('../../.github/skills/demo/toolkit')
                'x-hve' = @{ profiles = @{ starter = @('../../.github/agents/demo/first.agent.md', '../../.github/skills/demo/toolkit') } }
            })
        $errors.Count | Should -Be 0
    }

    It 'Reports membership errors alongside overlay errors' {
        $errors = @(Test-MarketplaceEntryContract -Entry @{
                name    = 'demo'
                agents  = @('../../.github/agents/demo/first.agent.md', '../../.github/agents/demo/first.agent.md')
                'x-hve' = @{ displayName = '' }
            })
        $errors.Count | Should -Be 2
        $errors | Should -Contain "component field 'agents' declares duplicate path '../../.github/agents/demo/first.agent.md'"
        $errors | Should -Contain 'x-hve.displayName must be a non-empty string'
    }
}

AfterAll {
    Remove-Module MarketplaceHelpers -Force -ErrorAction SilentlyContinue
}
