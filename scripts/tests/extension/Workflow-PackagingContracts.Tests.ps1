#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

BeforeAll {
    # MarketplaceHelpers reloads its nested ArtifactHelpers dependency, so shared
    # modules load before the scripts whose own imports settle the session state.
    Import-Module (Join-Path $PSScriptRoot '../../lib/Modules/MarketplaceHelpers.psm1') -Force
    . (Join-Path $PSScriptRoot '../../extension/Get-MarketplacePackageMatrix.ps1')
    . (Join-Path $PSScriptRoot '../../extension/Package-Extension.ps1')

    $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
    $script:WorkflowDirectory = Join-Path $script:RepositoryRoot '.github/workflows'
    $script:CatalogPath = Join-Path $script:RepositoryRoot '.github/plugin/marketplace.json'
    $script:RootManifest = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'package.json') -Raw -Encoding utf8 | ConvertFrom-Json

    function Get-WorkflowText {
        <#
        .SYNOPSIS
        Reads raw workflow text.
        .PARAMETER Name
        Workflow file name.
        .OUTPUTS
        [string] Raw workflow content.
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory = $true)]
            [string]$Name
        )

        return Get-Content -LiteralPath (Join-Path $script:WorkflowDirectory $Name) -Raw -Encoding utf8
    }

    function Get-WorkflowDocument {
        <#
        .SYNOPSIS
        Parses one workflow file.
        .PARAMETER Name
        Workflow file name.
        .OUTPUTS
        [System.Collections.IDictionary] Parsed workflow.
        #>
        [CmdletBinding()]
        [OutputType([System.Collections.IDictionary])]
        param(
            [Parameter(Mandatory = $true)]
            [string]$Name
        )

        return (Get-WorkflowText -Name $Name | ConvertFrom-Yaml)
    }

    function Get-JobStepText {
        <#
        .SYNOPSIS
        Returns the run and uses text of every step in a job, in declaration order.
        .PARAMETER Document
        Parsed workflow.
        .PARAMETER JobName
        Job identifier.
        .OUTPUTS
        [string[]] Step text in order.
        #>
        [CmdletBinding()]
        [OutputType([string[]])]
        param(
            [Parameter(Mandatory = $true)]
            [System.Collections.IDictionary]$Document,

            [Parameter(Mandatory = $true)]
            [string]$JobName
        )

        $steps = @($Document['jobs'][$JobName]['steps'])
        return [string[]]@($steps | ForEach-Object {
                $run = if ($_.Contains('run')) { [string]$_['run'] } else { '' }
                $uses = if ($_.Contains('uses')) { [string]$_['uses'] } else { '' }
                "$uses`n$run"
            })
    }

    function Get-ScriptArrayLiteral {
        <#
        .SYNOPSIS
        Extracts string array literals declared inside a named function.
        .PARAMETER ScriptPath
        Script to parse.
        .PARAMETER FunctionName
        Function to inspect.
        .OUTPUTS
        [string[]] Literal string elements.
        #>
        [CmdletBinding()]
        [OutputType([string[]])]
        param(
            [Parameter(Mandatory = $true)]
            [string]$ScriptPath,

            [Parameter(Mandatory = $true)]
            [string]$FunctionName
        )

        $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
        $function = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
                Where-Object { $_.Name -eq $FunctionName })
        $literals = @($function[0].FindAll({ $args[0] -is [System.Management.Automation.Language.ArrayLiteralAst] }, $true) |
                Where-Object { @($_.Elements | Where-Object { $_ -isnot [System.Management.Automation.Language.StringConstantExpressionAst] }).Count -eq 0 })
        return [string[]]@($literals | ForEach-Object { $_.Elements.Value })
    }
}

Describe 'Package discovery parity' -Tag 'Unit' {
    BeforeAll {
        $script:DiscoveryWorkflows = @(
            @{ Workflow = 'extension-package.yml'; Job = 'discover-packages' }
            @{ Workflow = 'extension-provenance.yml'; Job = 'discover-packages' }
            @{ Workflow = 'release-marketplace-stable.yml'; Job = 'discover' }
            @{ Workflow = 'plugin-package.yml'; Job = 'discover-packages' }
        )
    }

    It 'Discovers packages through the shared script in <Workflow>' -ForEach @(
        @{ Workflow = 'extension-package.yml'; Job = 'discover-packages' }
        @{ Workflow = 'extension-provenance.yml'; Job = 'discover-packages' }
        @{ Workflow = 'release-marketplace-stable.yml'; Job = 'discover' }
        @{ Workflow = 'plugin-package.yml'; Job = 'discover-packages' }
    ) {
        $steps = Get-JobStepText -Document (Get-WorkflowDocument -Name $Workflow) -JobName $Job
        @($steps | Where-Object { $_ -match 'scripts/extension/Get-MarketplacePackageMatrix\.ps1' }) |
            Should -HaveCount 1 -Because "$Workflow job '$Job' must use the single discovery script"
        @($steps | Where-Object { $_ -match '\./\.github/actions/setup-ps-modules' }) |
            Should -HaveCount 1 -Because "$Workflow job '$Job' runs PowerShell that needs pinned modules"
    }

    It 'Runs plugin discovery on the PreRelease policy' {
        $steps = Get-JobStepText -Document (Get-WorkflowDocument -Name 'plugin-package.yml') -JobName 'discover-packages'
        @($steps | Where-Object { $_ -match "Get-MarketplacePackageMatrix\.ps1 -Channel 'PreRelease'" }) | Should -HaveCount 1
    }

    It 'Keeps no duplicated maturity filtering in plugin discovery' {
        $steps = Get-JobStepText -Document (Get-WorkflowDocument -Name 'plugin-package.yml') -JobName 'discover-packages'
        @($steps | Where-Object { $_ -match 'jq ' }) | Should -HaveCount 0
        (Get-WorkflowText -Name 'plugin-package.yml') | Should -Not -Match 'x-hve'
    }

    It 'Consumes the shared names output for generated root verification' {
        $document = Get-WorkflowDocument -Name 'plugin-package.yml'
        [string]$document['jobs']['discover-packages']['outputs']['names'] | Should -BeExactly '${{ steps.discover.outputs.names }}'
        (Get-WorkflowText -Name 'plugin-package.yml') | Should -Match 'needs\.discover-packages\.outputs\.names'
    }

    It 'Produces the same PreRelease package set the plugin policy requires' {
        $catalog = Get-Content -LiteralPath $script:CatalogPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
        $pluginPolicy = foreach ($entry in $catalog['plugins']) {
            $overlay = if ($entry.Contains('x-hve')) { $entry['x-hve'] } else { @{} }
            $maturity = if ($overlay.Contains('maturity')) { [string]$overlay['maturity'] } else { 'stable' }
            if ($maturity -in @('deprecated', 'removed')) { continue }
            [string]$entry['name']
        }
        $expected = [string[]]@($pluginPolicy)
        [array]::Sort($expected, [System.StringComparer]::Ordinal)
        @($expected).Count | Should -BeGreaterThan 0
        @((Get-MarketplacePackageMatrixCore -Channel PreRelease -CatalogPath $script:CatalogPath).Names) | Should -Be $expected
    }

    It 'Restricts the Stable extension policy to a subset of the plugin policy' {
        $stable = @((Get-MarketplacePackageMatrixCore -Channel Stable -CatalogPath $script:CatalogPath).Names)
        $preRelease = @((Get-MarketplacePackageMatrixCore -Channel PreRelease -CatalogPath $script:CatalogPath).Names)
        @($stable).Count | Should -BeGreaterThan 0
        foreach ($name in $stable) { $preRelease | Should -Contain $name }
    }
}

Describe 'Packaging workflow arguments' -Tag 'Unit' {
    It 'Passes the matrix package ID into both packaging scripts in <Workflow>' -ForEach @(
        @{ Workflow = 'extension-package.yml'; Job = 'package' }
        @{ Workflow = 'extension-provenance.yml'; Job = 'build-attest' }
    ) {
        $steps = Get-JobStepText -Document (Get-WorkflowDocument -Name $Workflow) -JobName $Job
        @($steps | Where-Object { $_ -match 'Prepare-Extension\.ps1 .*-PackageId \$packageId' }) | Should -HaveCount 1
        @($steps | Where-Object { $_ -match "\`$packageId = ""(\`${{ matrix\.id }}|\`$env:PACKAGE_ID)""" }) | Should -HaveCount 2
        @($steps | Where-Object { $_ -match "PackageId\s+=\s+\`$packageId" }) | Should -HaveCount 1
    }

    It 'Selects the release VSIX by package ID during publish' {
        $steps = Get-JobStepText -Document (Get-WorkflowDocument -Name 'extension-marketplace-publish.yml') -JobName 'publish'
        @($steps | Where-Object { $_ -match 'Select-PackageVsix\.ps1 -AssetDirectory \$env:ASSET_DIRECTORY -PackageId \$env:PACKAGE_ID' }) | Should -HaveCount 1
    }

    It 'Resolves the extension identity from the shared module during publish' {
        $steps = Get-JobStepText -Document (Get-WorkflowDocument -Name 'extension-marketplace-publish.yml') -JobName 'publish'
        @($steps | Where-Object { $_ -match 'scripts/extension/Modules/ExtensionIdentity\.psm1' }) | Should -HaveCount 1
        @($steps | Where-Object { $_ -match 'EXTENSION_NAME=\$identity' }) | Should -HaveCount 1
    }

    It 'Downloads release assets with an identity-scoped glob' {
        $text = Get-WorkflowText -Name 'extension-marketplace-publish.yml'
        $text | Should -Match 'gh release download .* --pattern "\$env:VSIX_ASSET_GLOB"'
        $text | Should -Not -Match '--pattern "\*\$env:PACKAGE_ID\*\.vsix"'
    }

    It 'Publishes only from the marketplace publish workflow' {
        foreach ($workflow in @('extension-package.yml', 'extension-provenance.yml', 'plugin-package.yml')) {
            (Get-WorkflowText -Name $workflow) | Should -Not -Match 'vsce publish'
        }
        (Get-WorkflowText -Name 'extension-marketplace-publish.yml') | Should -Match 'vsce publish'
    }
}

Describe 'Packages matrix wiring' -Tag 'Unit' {
    It 'Publishes a packages-matrix output from <Workflow>' -ForEach @(
        @{ Workflow = 'extension-package.yml'; Job = 'discover-packages' }
        @{ Workflow = 'extension-provenance.yml'; Job = 'discover-packages' }
        @{ Workflow = 'plugin-package.yml'; Job = 'discover-packages' }
    ) {
        $document = Get-WorkflowDocument -Name $Workflow
        $outputs = $document['on']['workflow_call']['outputs']
        $outputs.Contains('packages-matrix') | Should -BeTrue
        [string]$outputs['packages-matrix']['value'] | Should -BeExactly "`${{ jobs.$Job.outputs.matrix }}"
    }

    It 'Feeds the discovered matrix into the publish workflow from <Workflow>' -ForEach @(
        @{ Workflow = 'release-marketplace-stable.yml'; Expression = '${{ needs.discover.outputs.matrix }}' }
        @{ Workflow = 'release-marketplace-prerelease.yml'; Expression = '${{ needs.package.outputs.packages-matrix }}' }
    ) {
        $document = Get-WorkflowDocument -Name $Workflow
        $publish = $document['jobs']['publish']
        [string]$publish['uses'] | Should -BeExactly './.github/workflows/extension-marketplace-publish.yml'
        [string]$publish['with']['packages-matrix'] | Should -BeExactly $Expression
    }

    It 'Requires the packages-matrix input in the publish workflow' {
        $document = Get-WorkflowDocument -Name 'extension-marketplace-publish.yml'
        $matrixInput = $document['on']['workflow_call']['inputs']['packages-matrix']
        $matrixInput['required'] | Should -BeTrue
        [string]$matrixInput['type'] | Should -BeExactly 'string'
    }
}

Describe 'Release artifact naming' -Tag 'Unit' {
    BeforeAll {
        # This script enables strict mode, so it is scoped to this block only.
        . (Join-Path $PSScriptRoot '../../linting/Test-ExtensionArtifactNaming.ps1')
    }

    It 'Passes the extension VSIX artifact naming contract' {
        $result = Test-ExtensionArtifactNaming -RepoRoot $script:RepositoryRoot
        @($result.Issues) | Should -HaveCount 0
        $result.Passed | Should -BeTrue
        @($result.Producers).Count | Should -BeGreaterThan 0
        @($result.Consumers).Count | Should -BeGreaterThan 0
    }

    It 'Names every VSIX artifact after the matrix package ID' {
        foreach ($workflow in @('extension-package.yml', 'extension-provenance.yml', 'extension-marketplace-publish.yml', 'release-prerelease.yml')) {
            $text = Get-WorkflowText -Name $workflow
            $names = @([regex]::Matches($text, '(?m)name: (extension-vsix-[^\r\n]+)') |
                    ForEach-Object { $_.Groups[1].Value.Trim() } | Sort-Object -Unique)
            @($names).Count | Should -BeGreaterThan 0 -Because "$workflow handles VSIX artifacts"
            $names | Should -Be @('extension-vsix-${{ matrix.id }}')
        }
    }

    It 'Names every per-package SBOM artifact after the matrix package ID' {
        (Get-WorkflowText -Name 'extension-provenance.yml') | Should -Match 'artifact-name: sbom-\$\{\{ matrix\.id \}\}'
        (Get-WorkflowText -Name 'release-prerelease.yml') | Should -Match 'artifact-name: sbom-\$\{\{ matrix\.id \}\}'
        (Get-WorkflowText -Name 'release-stable.yml') | Should -Match 'artifact-name: sbom-plugin-\$\{\{ matrix\.id \}\}'
    }

    It 'Matches the plugin archive producer and consumer names' {
        (Get-WorkflowText -Name 'plugin-package.yml') | Should -Match 'name: plugin-package-\$\{\{ matrix\.id \}\}'
        (Get-WorkflowText -Name 'release-stable.yml') | Should -Match 'name: plugin-package-\$\{\{ matrix\.id \}\}'
    }

    It 'Wires the artifact naming check into the local validation aggregate' {
        [string]$script:RootManifest.scripts.'lint:extension-artifact-naming' |
            Should -BeExactly 'pwsh -NoProfile -File scripts/linting/Test-ExtensionArtifactNaming.ps1'
        [string]$script:RootManifest.scripts.'validate:local' | Should -Match 'npm run lint:extension-artifact-naming'
    }
}

Describe 'Plugin validation lane' -Tag 'Unit' {
    BeforeAll {
        $script:PluginValidationSteps = Get-JobStepText -Document (Get-WorkflowDocument -Name 'plugin-validation.yml') -JobName 'validate'
        $script:StepIndex = @{}
        for ($index = 0; $index -lt $script:PluginValidationSteps.Count; $index++) {
            foreach ($command in @('lint:plugin-output', 'lint:marketplace', 'lint:hooks', 'plugin:generate', 'plugin:evidence')) {
                if ($script:PluginValidationSteps[$index] -match "npm run $([regex]::Escape($command))") {
                    $script:StepIndex[$command] = $index
                }
            }
        }
    }

    It 'Runs every required validation command' {
        @($script:StepIndex.Keys | Sort-Object) | Should -Be @('lint:hooks', 'lint:marketplace', 'lint:plugin-output', 'plugin:evidence', 'plugin:generate')
    }

    It 'Guards tracked plugin output before regenerating plugins' {
        $script:StepIndex['lint:plugin-output'] | Should -BeLessThan $script:StepIndex['plugin:generate']
    }

    It 'Records release evidence after regeneration' {
        $script:StepIndex['plugin:evidence'] | Should -BeGreaterThan $script:StepIndex['plugin:generate']
    }

    It 'Runs no removed collection lint' {
        (Get-WorkflowText -Name 'plugin-validation.yml') | Should -Not -Match 'lint:collections'
        [string]$script:RootManifest.scripts.'validate:local' | Should -Not -Match 'lint:collections'
        $script:RootManifest.scripts.PSObject.Properties.Name | Should -Not -Contain 'lint:collections'
    }
}

Describe 'Removed collection inputs' -Tag 'Unit' {
    It 'References no collections path from any source workflow' {
        $offenders = @(
            Get-ChildItem -LiteralPath $script:WorkflowDirectory -File -Filter '*.yml' |
                Where-Object { $_.Name -notlike '*.lock.yml' } |
                Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'collections/' } |
                ForEach-Object { $_.Name }
        )
        @($offenders).Count | Should -Be 0 -Because "collections/ no longer exists: $($offenders -join ', ')"
    }

    It 'References no collections path from the root manifest or lockfile' {
        (Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'package.json') -Raw) | Should -Not -Match 'collections/'
        (Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'package-lock.json') -Raw) | Should -Not -Match '"collections/'
    }

    It 'Watches only documentation and workflow inputs for Docusaurus changes' {
        $steps = Get-JobStepText -Document (Get-WorkflowDocument -Name 'docusaurus-tests.yml') -JobName 'detect-changes'
        $detect = @($steps | Where-Object { $_ -match 'git diff --name-only' })
        $detect | Should -HaveCount 1
        $detect[0] | Should -Not -Match 'collections'
        $detect[0] | Should -Match '(?m)^\s*docs\s*`?\s*$'
        $detect[0] | Should -Match '\.github/workflows/docusaurus-tests\.yml'
        $detect[0] | Should -Match '\.github/workflows/deploy-docs\.yml'
    }
}

Describe 'Extension packaging configuration' -Tag 'Unit' {
    BeforeAll {
        $script:IgnoreLines = @(Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'extension/.vscodeignore'))
        $script:AllowEntries = [string[]]@($script:IgnoreLines | Where-Object { $_ -like '!*' })

        $catalog = Get-MarketplaceCatalog -Path $script:CatalogPath
        $agentIndex = Get-MarketplaceAgentIndex -Catalog $catalog -RepoRoot $script:RepositoryRoot
        $contributionKinds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $script:HookKindSeen = $false
        foreach ($entry in @($catalog['plugins'])) {
            if (-not (Test-MarketplaceEntryEligible -Entry $entry -Channel 'PreRelease')) { continue }
            foreach ($item in Get-MarketplaceResolvedPackageRecipe -Entry $entry -Channel 'PreRelease' -AgentIndex $agentIndex) {
                if ($item.Kind -eq 'hook') { $script:HookKindSeen = $true; continue }
                [void]$contributionKinds.Add([string]$item.Kind)
            }
        }
        $sourceRootMap = Get-MarketplaceComponentSourceRoot
        $script:ContributionRoots = [string[]]@($contributionKinds | ForEach-Object {
                $sourceRootMap[(Get-MarketplaceComponentField -Kind $_)].SourceRoot
            } | Sort-Object -Unique)
        $script:HookRoot = $sourceRootMap[(Get-MarketplaceComponentField -Kind 'hook')].SourceRoot
        $script:SharedRoots = @(Get-ScriptArrayLiteral -ScriptPath (Join-Path $script:RepositoryRoot 'scripts/extension/Package-Extension.ps1') -FunctionName 'Copy-PreparedArtifacts')

        $expected = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($root in $script:ContributionRoots) { [void]$expected.Add("!$root/**") }
        foreach ($root in $script:SharedRoots) {
            $absolute = Join-Path $script:RepositoryRoot $root
            if (Test-Path -LiteralPath $absolute -PathType Container) { [void]$expected.Add("!$root/**") }
            else { [void]$expected.Add("!$root") }
        }
        foreach ($baseFile in @('icon.png', 'package.json', 'README.md', 'LICENSE', 'CHANGELOG.md')) {
            [void]$expected.Add("!$baseFile")
        }
        $script:ExpectedAllowEntries = [string[]]@($expected)
    }

    It 'Derives a non-empty staging root set from the shared projection' {
        @($script:ContributionRoots).Count | Should -BeGreaterThan 0
        $script:ContributionRoots | Should -Be @('.github/agents', '.github/instructions', '.github/prompts', '.github/skills')
        @($script:SharedRoots) | Should -Be @('scripts/lib/Modules/CIHelpers.psm1', 'docs/templates')
    }

    It 'Allow-lists exactly the staging roots plus the base extension files' {
        $actual = [string[]]@($script:AllowEntries)
        $expected = [string[]]@($script:ExpectedAllowEntries)
        [array]::Sort($actual, [System.StringComparer]::Ordinal)
        [array]::Sort($expected, [System.StringComparer]::Ordinal)
        $actual | Should -Be $expected
    }

    It 'Never allow-lists the plugin-only hook root' {
        $script:HookKindSeen | Should -BeTrue
        $script:AllowEntries | Should -Not -Contain "!$script:HookRoot/**"
    }

    It 'Excludes package-specific generated files from the shipped VSIX' {
        $script:IgnoreLines | Should -Contain 'README.*.md'
        $script:IgnoreLines | Should -Contain 'package.*.json'
    }

    It 'Excludes Python and dependency caches from shipped skills' {
        foreach ($pattern in @('**/.venv/**', '**/.ruff_cache/**', '**/.pytest_cache/**', '**/__pycache__/**', '**/*.pyc')) {
            $script:IgnoreLines | Should -Contain $pattern
        }
    }

    It 'Uses only existing script directories for Pester coverage' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:RepositoryRoot 'scripts/tests/pester.config.ps1'), [ref]$null, [ref]$null)
        $assignment = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true) |
                Where-Object { $_.Left.Extent.Text -eq '$coverageDirs' })
        $assignment | Should -HaveCount 1
        $coverageDirs = @($assignment[0].Right.FindAll({ $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) |
                ForEach-Object { $_.Value })
        @($coverageDirs).Count | Should -BeGreaterThan 0
        foreach ($directory in $coverageDirs) {
            Test-Path -LiteralPath (Join-Path $script:RepositoryRoot "scripts/$directory") -PathType Container |
                Should -BeTrue -Because "coverage directory scripts/$directory must exist"
        }
        $coverageDirs | Should -Contain 'extension'
        $coverageDirs | Should -Contain 'plugins'
        $coverageDirs | Should -Contain 'docs'
        $coverageDirs | Should -Not -Contain 'collections'
    }
}
