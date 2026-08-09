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

    function Get-NamedJobStep {
        <#
        .SYNOPSIS
        Returns the single step of a job carrying an exact display name.
        .PARAMETER Document
        Parsed workflow.
        .PARAMETER JobName
        Job identifier.
        .PARAMETER StepName
        Step display name.
        .OUTPUTS
        [System.Collections.IDictionary] Matching step.
        #>
        [CmdletBinding()]
        [OutputType([System.Collections.IDictionary])]
        param(
            [Parameter(Mandatory = $true)]
            [System.Collections.IDictionary]$Document,

            [Parameter(Mandatory = $true)]
            [string]$JobName,

            [Parameter(Mandatory = $true)]
            [string]$StepName
        )

        $found = @($Document['jobs'][$JobName]['steps'] | Where-Object { [string]$_['name'] -eq $StepName })
        if ($found.Count -ne 1) {
            throw "Job '$JobName' must declare exactly one step named '$StepName' but declared $($found.Count)"
        }
        return $found[0]
    }

    function Get-JobNeedsClosure {
        <#
        .SYNOPSIS
        Returns every job a named job depends on, directly or transitively.
        .PARAMETER Jobs
        Parsed jobs mapping.
        .PARAMETER JobName
        Job identifier.
        .OUTPUTS
        [string[]] Transitive needs closure.
        #>
        [CmdletBinding()]
        [OutputType([string[]])]
        param(
            [Parameter(Mandatory = $true)]
            [System.Collections.IDictionary]$Jobs,

            [Parameter(Mandatory = $true)]
            [string]$JobName
        )

        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $pending = [System.Collections.Generic.Queue[string]]::new()
        $pending.Enqueue($JobName)
        while ($pending.Count -gt 0) {
            $job = $Jobs[$pending.Dequeue()]
            if ($null -eq $job -or -not $job.Contains('needs')) {
                continue
            }
            foreach ($need in @($job['needs'])) {
                if ($seen.Add([string]$need)) {
                    $pending.Enqueue([string]$need)
                }
            }
        }
        return [string[]]@($seen)
    }

    function ConvertTo-SortedJson {
        <#
        .SYNOPSIS
        Renders parsed JSON as key-sorted canonical text so structures compare independently of key order.
        .PARAMETER InputObject
        Parsed JSON value.
        .OUTPUTS
        [string] Canonical JSON text.
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory = $false)]
            [AllowNull()]
            $InputObject
        )

        if ($InputObject -is [System.Collections.IDictionary]) {
            $keys = [string[]]@($InputObject.Keys)
            [array]::Sort($keys, [System.StringComparer]::Ordinal)
            $pairs = foreach ($key in $keys) {
                '{0}:{1}' -f (ConvertTo-Json -InputObject $key -Compress), (ConvertTo-SortedJson -InputObject $InputObject[$key])
            }
            return '{' + [string]::Join(',', @($pairs)) + '}'
        }
        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            $items = foreach ($item in $InputObject) { ConvertTo-SortedJson -InputObject $item }
            return '[' + [string]::Join(',', @($items)) + ']'
        }
        return (ConvertTo-Json -InputObject $InputObject -Compress)
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
        $verification = @($document['jobs']['package']['steps'] | Where-Object {
                $_.Contains('run') -and [string]$_['run'] -match 'Generated package roots do not match'
            })
        $verification | Should -HaveCount 1
        [string]$verification[0]['env']['DISCOVERED_NAMES'] | Should -BeExactly '${{ needs.discover-packages.outputs.names }}'
        $run = [string]$verification[0]['run']
        $run | Should -Match "jq -r '\.\[\]' \| sort"
        $run | Should -Match 'find "\$\{HVE_PLUGIN_STAGING_ROOT\}" -mindepth 1 -maxdepth 1 -type d'
        $run | Should -Match '\[ "\$expected" != "\$actual" \]'
        $run | Should -Not -Match '-eq 1\b|== 1\b'
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
# End release packaging contracts.
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

    It 'Publishes through Azure OIDC after verifying the attested release asset' {
        $document = Get-WorkflowDocument -Name 'extension-marketplace-publish.yml'
        $inputs = $document['on']['workflow_call']['inputs']
        foreach ($name in @('tag', 'attestation-signer-workflow')) {
            $inputs[$name]['required'] | Should -BeTrue
            [string]$inputs[$name]['type'] | Should -BeExactly 'string'
            $inputs[$name].Contains('default') | Should -BeFalse
        }
        $inputs.Contains('verify-attestation') | Should -BeFalse

        $gateJob = $document['jobs']['validate-inputs']
        $gateJob.Contains('environment') | Should -BeFalse
        [string]$gateJob['permissions']['contents'] | Should -BeExactly 'read'
        $gate = Get-NamedJobStep -Document $document -JobName 'validate-inputs' -StepName 'Validate publication inputs'
        [string]$gate['shell'] | Should -BeExactly 'bash'
        [string]$gate['env']['INPUT_PACKAGES_MATRIX'] | Should -BeExactly '${{ inputs.packages-matrix }}'
        [string]$gate['env']['INPUT_TAG'] | Should -BeExactly '${{ inputs.tag }}'
        [string]$gate['env']['INPUT_PRE_RELEASE'] | Should -BeExactly '${{ inputs.pre-release }}'
        [string]$gate['env']['INPUT_SIGNER_WORKFLOW'] | Should -BeExactly '${{ inputs.attestation-signer-workflow }}'
        $gateRun = [string]$gate['run']
        $gateRun | Should -Match 'set -euo pipefail'
        $gateRun | Should -Not -Match '\$\{\{\s*(?:github\.event|inputs\.)'

        # The caller-controlled matrix is rejected structurally, including every
        # package-ID token, before the publish job can activate its environment.
        foreach ($clause in @(
                'printf ''%s'' "$INPUT_PACKAGES_MATRIX" | jq -e'
                '(keys_unsorted | length) == 1'
                'has("include")'
                '(.include | type) == "array"'
                '(.include | length) > 0'
                '(.id | type) == "string"'
                '(.id | test("^[a-z0-9]+(?:-[a-z0-9]+)*$"))'
                '([.include[].id] | unique | length) == (.include | length)'
            )) {
            $gateRun | Should -Match ([regex]::Escape($clause))
        }
        $gateRun | Should -Match 'case "\$INPUT_PRE_RELEASE" in'
        $gateRun | Should -Match 'pre-release must be true or false'
        $gateRun | Should -Match '\^prerelease-v\[0-9\]\+\\\.\[0-9\]\+\\\.\[0-9\]\+\$'
        $gateRun | Should -Match '\^v\[0-9\]\+\\\.\[0-9\]\+\\\.\[0-9\]\+\$'
        $gateRun | Should -Match '\[\[ ! "\$INPUT_TAG" =~ \$expected_pattern \]\]'
        $gateRun | Should -Match '\[\[ "\$INPUT_SIGNER_WORKFLOW" != "\$expected_signer" \]\]'
        $gateRun | Should -Match ([regex]::Escape('.github/workflows/release-prerelease.yml'))
        $gateRun | Should -Match ([regex]::Escape('.github/workflows/extension-provenance.yml'))

        # Minor parity is derived from the already validated channel tag, so no
        # caller can publish an even minor as PreRelease or an odd minor as Stable.
        $gateRun | Should -Match 'expected_minor_parity=1'
        $gateRun | Should -Match 'expected_minor_parity=0'
        $gateRun | Should -Match ([regex]::Escape('TAG_VERSION="${INPUT_TAG#prerelease-v}"'))
        $gateRun | Should -Match ([regex]::Escape('(( TAG_MINOR % 2 != expected_minor_parity ))'))

        $job = $document['jobs']['publish']
        [string]$job['needs'] | Should -BeExactly 'validate-inputs'
        [string]$job['environment'] | Should -BeExactly 'marketplace'
        [string]$job['permissions']['id-token'] | Should -BeExactly 'write'
        [string]$job['permissions']['attestations'] | Should -BeExactly 'read'

        # Publication is best-effort: every matrix leg is attempted, so a partial
        # failure leaves the remaining packages reconcilable rather than skipped.
        $job['strategy']['fail-fast'] | Should -BeFalse

        # The publisher executes the tagged tree that verification later proves
        # it checked out.
        $checkout = Get-NamedJobStep -Document $document -JobName 'publish' -StepName 'Checkout code'
        [string]$checkout['with']['ref'] | Should -BeExactly 'refs/tags/${{ inputs.tag }}'
        $checkout['with']['persist-credentials'] | Should -BeFalse

        [string](Get-NamedJobStep -Document $document -JobName 'publish' -StepName 'Azure Login (OIDC)')['uses'] |
            Should -Match '^azure/login@[0-9a-f]{40}$'

        $download = Get-NamedJobStep -Document $document -JobName 'publish' -StepName 'Download attested VSIX from GitHub Release'
        $download.Contains('if') | Should -BeFalse
        $verify = Get-NamedJobStep -Document $document -JobName 'publish' -StepName 'Verify attested VSIX provenance'
        $verify.Contains('if') | Should -BeFalse
        [string]$verify['env']['RELEASE_TAG'] | Should -BeExactly '${{ inputs.tag }}'
        [string]$verify['env']['SIGNER_WORKFLOW'] |
            Should -BeExactly '${{ github.repository }}/${{ inputs.attestation-signer-workflow }}'
        [string]$verify['run'] | Should -Match 'gh attestation verify "\$VSIX_FILE" --repo "\$REPOSITORY"'
        [string]$verify['run'] | Should -Match '--signer-workflow "\$SIGNER_WORKFLOW"'
        # An annotated tag must dereference to its commit, and that commit must be
        # the checked-out HEAD, so verification covers the executed publisher tree.
        [string]$verify['run'] | Should -Match ([regex]::Escape('git rev-parse --verify --end-of-options "refs/tags/$RELEASE_TAG^{commit}"'))
        [string]$verify['run'] | Should -Match ([regex]::Escape('CHECKOUT_DIGEST=$(git rev-parse HEAD)'))
        [string]$verify['run'] | Should -Match ([regex]::Escape('[ "$SOURCE_DIGEST" != "$CHECKOUT_DIGEST" ]'))
        [string]$verify['run'] | Should -Not -Match 'commits/\$RELEASE_TAG'
        [string]$verify['run'] | Should -Match '--source-digest "\$SOURCE_DIGEST"'

        $text = Get-WorkflowText -Name 'extension-marketplace-publish.yml'
        $text | Should -Not -Match 'Download intra-run VSIX artifact|Resolve downloaded VSIX path|inputs\.tag ==|extension-vsix-'

        $names = [string[]]@($job['steps'] | ForEach-Object { [string]$_['name'] })
        [array]::IndexOf($names, 'Verify attested VSIX provenance') |
            Should -BeLessThan ([array]::IndexOf($names, 'Azure Login (OIDC)'))
        [array]::IndexOf($names, 'Verify attested VSIX provenance') |
            Should -BeLessThan ([array]::IndexOf($names, 'Setup Node.js'))
        [array]::IndexOf($names, 'Verify attested VSIX provenance') |
            Should -BeLessThan ([array]::IndexOf($names, 'Install dependencies'))
        # Publish credentials activate after the toolchain is installed and
        # immediately before the step that uses them.
        [array]::IndexOf($names, 'Install dependencies') |
            Should -BeLessThan ([array]::IndexOf($names, 'Azure Login (OIDC)'))
        [array]::IndexOf($names, 'Azure Login (OIDC)') |
            Should -BeLessThan ([array]::IndexOf($names, 'Publish to VS Code Marketplace'))
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
        @{ Workflow = 'release-marketplace-prerelease.yml'; Expression = '${{ needs.discover.outputs.matrix }}' }
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
        foreach ($workflow in @('extension-package.yml', 'extension-provenance.yml', 'release-prerelease.yml')) {
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
        (Get-WorkflowText -Name 'release-stable-publish.yml') | Should -Match 'artifact-name: sbom-plugin-\$\{\{ matrix\.id \}\}'
    }

    It 'Matches the plugin archive producer and consumer names' {
        (Get-WorkflowText -Name 'plugin-package.yml') | Should -Match 'name: plugin-package-\$\{\{ matrix\.id \}\}'
        (Get-WorkflowText -Name 'release-stable-publish.yml') | Should -Match 'name: plugin-package-\$\{\{ matrix\.id \}\}'
        (Get-WorkflowText -Name 'release-prerelease.yml') | Should -Match 'name: plugin-package-\$\{\{ matrix\.id \}\}'
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

    It 'Stages generated package work under runner temp in <Workflow> step <Step>' -ForEach @(
        @{ Workflow = 'plugin-validation.yml'; Job = 'validate'; Step = 'Regenerate plugins from source' }
        @{ Workflow = 'plugin-package.yml'; Job = 'package'; Step = 'Generate committed plugins' }
        @{ Workflow = 'plugin-package.yml'; Job = 'package'; Step = 'Verify generated roots match discovered packages' }
        @{ Workflow = 'plugin-package.yml'; Job = 'package'; Step = 'Package plugin directory' }
    ) {
        $document = Get-WorkflowDocument -Name $Workflow
        $step = Get-NamedJobStep -Document $document -JobName $Job -StepName $Step
        [string]$step['env']['HVE_PLUGIN_STAGING_ROOT'] |
            Should -BeExactly '${{ runner.temp }}/plugins'
    }

    # Canonical evidence is derived from declared git-tracked sources, so no
    # evidence producer may depend on a materialized package tree.
    It 'Records canonical evidence without a staging root in <Workflow> step <Step>' -ForEach @(
        @{ Workflow = 'plugin-validation.yml'; Job = 'validate'; Step = 'Record canonical release evidence' }
        @{ Workflow = 'plugin-package.yml'; Job = 'publish-evidence'; Step = 'Record canonical release evidence' }
        @{ Workflow = 'plugin-package.yml'; Job = 'publish-evidence'; Step = 'Verify recorded evidence reproduces' }
    ) {
        $document = Get-WorkflowDocument -Name $Workflow
        $step = Get-NamedJobStep -Document $document -JobName $Job -StepName $Step
        $environment = if ($step.Contains('env')) { $step['env'] } else { @{} }
        $environment.Contains('HVE_PLUGIN_STAGING_ROOT') | Should -BeFalse
    }

    It 'Preserves the plugins directory prefix inside signed ZIP archives' {
        $steps = Get-JobStepText -Document (Get-WorkflowDocument -Name 'plugin-package.yml') -JobName 'package'
        $package = @($steps | Where-Object { $_ -match 'zip -r' })
        $package | Should -HaveCount 1
        $package[0] | Should -Match '\(cd "\$\{RUNNER_TEMP\}"'
        $package[0] | Should -Match '"plugins/\$\{PACKAGE_ID\}"'
        $package[0] | Should -Match 'dist/plugins/\$\{PACKAGE_ID\}\.zip'
    }

    It 'References no repository-root generated plugin tree in retained callers' {
        foreach ($workflow in @('plugin-validation.yml', 'plugin-package.yml')) {
            $text = Get-WorkflowText -Name $workflow
            $text | Should -Not -Match 'find plugins -'
            $text | Should -Not -Match 'Get-ChildItem -LiteralPath plugins -Directory'
            $text | Should -Not -Match 'cp -R plugins '
        }
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

Describe 'Release source ownership' -Tag 'Unit' {
    BeforeAll {
        $script:WorkflowNames = [string[]]@(
            Get-ChildItem -LiteralPath $script:WorkflowDirectory -File -Filter '*.yml' |
                Where-Object { $_.Name -notlike '*.lock.yml' } |
                ForEach-Object { $_.Name }
        )
        # A tag write is any git reference creation under refs/tags.
        $script:TagCreators = [string[]]@(
            $script:WorkflowNames | Where-Object { (Get-WorkflowText -Name $_) -match 'ref=refs/tags/' }
        )
        $script:ReleaseCreators = [string[]]@(
            $script:WorkflowNames | Where-Object { (Get-WorkflowText -Name $_) -match 'gh release create ' }
        )
    }

    It 'Retired the pre-release PR workflow and its branch reset' {
        Test-Path -LiteralPath (Join-Path $script:WorkflowDirectory 'release-prerelease-pr.yml') | Should -BeFalse
        foreach ($workflow in $script:WorkflowNames) {
            (Get-WorkflowText -Name $workflow) | Should -Not -Match 'prerelease/next' -Because "$workflow must not reference the retired pre-release branch"
            (Get-WorkflowText -Name $workflow) | Should -Not -Match 'reset-prerelease' -Because "$workflow must not reference the retired branch reset"
        }
        $script:RootManifest.scripts.PSObject.Properties.Name | Should -Not -Contain 'reset-prerelease'
    }

    It 'Creates no immutable release tag or GitHub release outside release-please' {
        @($script:TagCreators) | Should -HaveCount 0 -Because "release-please owns every release tag: $($script:TagCreators -join ', ')"
        @($script:ReleaseCreators) | Should -HaveCount 0 -Because "release-please owns every GitHub release: $($script:ReleaseCreators -join ', ')"
        foreach ($workflow in @('release-prerelease.yml', 'release-stable-publish.yml')) {
            (Get-WorkflowText -Name $workflow) | Should -Match 'googleapis/release-please-action@'
        }
    }

    It 'Creates no tag or GitHub release during stable preparation on main' {
        $text = Get-WorkflowText -Name 'release-stable.yml'
        $text | Should -Not -Match 'ref=refs/tags/'
        # Reading the selected source release is permitted; only mutation is not.
        $text | Should -Not -Match 'gh release (create|edit|delete|upload)'
        $text | Should -Not -Match 'release_created'
    }

    It 'Configures release-please to create draft releases with release-please-owned tags' {
        foreach ($configName in @(
                'release-please-config.json'
                'release-please-prerelease-config.json'
            )) {
            $config = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot $configName) -Raw -Encoding utf8 | ConvertFrom-Json
            $package = $config.packages.'.'
            $package.PSObject.Properties.Name | Should -Not -Contain 'skip-github-release' -Because "$configName selects skip modes through action inputs"
            $package.draft | Should -BeTrue -Because "$configName keeps publication as the immutable boundary"
            $package.'force-tag-creation' | Should -BeTrue -Because "$configName must create the release tag before release-tag provenance checks"
        }
    }

    It 'Uses no source branch that a release workflow force-pushes' {
        foreach ($workflow in $script:WorkflowNames) {
            $text = Get-WorkflowText -Name $workflow
            $text | Should -Not -Match 'release/plugins' -Because "$workflow must never source or move the orphan snapshot branch"
            $text | Should -Not -Match 'push --force' -Because "$workflow must not force-push any reference"
        }
    }
}

Describe 'Release-please channel state' -Tag 'Unit' {
    BeforeAll {
        $script:ChannelConfigNames = @(
            'release-please-config.json'
            'release-please-prerelease-config.json'
        )
        $script:ChannelConfigs = @{}
        foreach ($name in $script:ChannelConfigNames) {
            $script:ChannelConfigs[$name] = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot $name) -Raw -Encoding utf8 |
                ConvertFrom-Json -AsHashtable
        }
        $script:StableChannelManifest = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.release-please-manifest.json') -Raw -Encoding utf8 |
            ConvertFrom-Json -AsHashtable
        $script:PreReleaseChannelManifest = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.release-please-prerelease-manifest.json') -Raw -Encoding utf8 |
            ConvertFrom-Json -AsHashtable
    }

    It 'Owns complete branch-local PreRelease release-please state' {
        $config = $script:ChannelConfigs['release-please-prerelease-config.json']
        $topKeys = [string[]]@($config.Keys)
        [array]::Sort($topKeys, [System.StringComparer]::Ordinal)
        $topKeys | Should -Be @('$schema', 'commit-search-depth', 'packages', 'release-search-depth')
        $config['release-search-depth'] | Should -Be 800
        $config['commit-search-depth'] | Should -Be 1000

        $package = $config['packages']['.']
        $packageKeys = [string[]]@($package.Keys)
        [array]::Sort($packageKeys, [System.StringComparer]::Ordinal)
        $packageKeys | Should -Be @(
            'bootstrap-sha'
            'bump-minor-pre-major'
            'bump-patch-for-minor-pre-major'
            'changelog-path'
            'changelog-sections'
            'component'
            'draft'
            'extra-files'
            'force-tag-creation'
            'include-component-in-tag'
            'package-name'
            'release-type'
            'versioning'
        )
        [string]$package['release-type'] | Should -BeExactly 'node'
        [string]$package['versioning'] | Should -BeExactly 'always-bump-patch'
        $package['force-tag-creation'] | Should -BeTrue
        [string]$package['changelog-path'] | Should -BeExactly 'CHANGELOG.md'
        @($package['extra-files']) | Should -HaveCount 3

        # component plus include-component-in-tag are what emit the
        # prerelease-v<version> namespace the Marketplace lane validates.
        [string]$package['package-name'] | Should -BeExactly 'hve-core'
        [string]$package['component'] | Should -BeExactly 'prerelease'
        $package['include-component-in-tag'] | Should -BeTrue

        foreach ($forbidden in @(
                'version-file'
                'skip-github-release'
                'skip-github-pull-request'
                'skip-changelog'
                'prerelease'
                'prerelease-type'
            )) {
            $package.Contains($forbidden) | Should -BeFalse -Because 'the PreRelease channel uses numeric node releases without action-mode config keys'
        }

        @($script:PreReleaseChannelManifest.Keys) | Should -Be @('.')
    }

    It 'Keeps each branch seed on its assigned numeric parity' {
        $stableVersion = [string]$script:StableChannelManifest['.']
        $preReleaseVersion = [string]$script:PreReleaseChannelManifest['.']
        $stableVersion | Should -Match '^\d+\.\d+\.\d+$'
        $preReleaseVersion | Should -Match '^\d+\.\d+\.\d+$'

        $stable = $stableVersion.Split('.')
        $preRelease = $preReleaseVersion.Split('.')
        ([int]$stable[1] % 2) | Should -Be 0 -Because 'Stable owns the even-minor baseline'
        ([int]$preRelease[1] % 2) | Should -Be 1 -Because 'PreRelease owns the odd-minor baseline'
    }

    It 'Uses one parity-safe package configuration that differs only by channel tag construction' {
        $stable = $script:ChannelConfigs['release-please-config.json']
        $preRelease = $script:ChannelConfigs['release-please-prerelease-config.json']
        [string]$stable['packages']['.']['versioning'] | Should -BeExactly 'always-bump-patch'
        [string]$preRelease['packages']['.']['versioning'] | Should -BeExactly 'always-bump-patch'

        # Stable emits v<version>; PreRelease emits prerelease-v<version>.
        $stable['packages']['.']['include-component-in-tag'] | Should -BeFalse
        $stable['packages']['.'].Contains('component') | Should -BeFalse
        $preRelease['packages']['.']['include-component-in-tag'] | Should -BeTrue
        [string]$preRelease['packages']['.']['component'] | Should -BeExactly 'prerelease'

        # Every other key is identical, so no other release behavior can drift.
        $normalized = @{}
        foreach ($name in $script:ChannelConfigNames) {
            $copy = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot $name) -Raw -Encoding utf8 |
                ConvertFrom-Json -AsHashtable
            $copy['packages']['.'].Remove('component')
            $copy['packages']['.'].Remove('include-component-in-tag')
            # bootstrap-sha is intentionally channel-specific and asserted separately.
            $copy['packages']['.'].Remove('bootstrap-sha')
            $normalized[$name] = $copy
        }
        (ConvertTo-SortedJson -InputObject $normalized['release-please-prerelease-config.json']) |
            Should -BeExactly (ConvertTo-SortedJson -InputObject $normalized['release-please-config.json'])
    }
}

Describe 'Pre-release preparation and publication' -Tag 'Unit' {
    BeforeAll {
        $script:PreReleaseDocument = Get-WorkflowDocument -Name 'release-prerelease.yml'
        $script:PreReleaseText = Get-WorkflowText -Name 'release-prerelease.yml'
    }

    It 'Runs PreRelease release-please only for the exact promotion and managed heads' {
        $triggers = [string[]]@($script:PreReleaseDocument['on'].Keys)
        [array]::Sort($triggers, [System.StringComparer]::Ordinal)
        $triggers | Should -Be @('pull_request')
        @($script:PreReleaseDocument['on']['pull_request']['types']) | Should -Be @('closed')
        @($script:PreReleaseDocument['on']['pull_request']['branches']) | Should -Be @('release/prerelease')

        $guard = [string]$script:PreReleaseDocument['jobs']['release-please']['if']
        $guard | Should -Match 'github\.event\.pull_request\.merged == true'
        $guard | Should -Match "github\.event\.pull_request\.base\.ref == 'release/prerelease'"
        $guard | Should -Match 'head\.repo\.full_name == github\.repository'
        $guard | Should -Match "head\.ref == 'release-promotion--main--to--release-prerelease'"
        $guard | Should -Match "head\.ref == 'release-please--branches--release/prerelease'"

        $release = Get-NamedJobStep -Document $script:PreReleaseDocument -JobName 'release-please' -StepName 'Run release-please'
        [string]$release['uses'] | Should -Match '^googleapis/release-please-action@[0-9a-f]{40}$'
        [string]$release['with']['config-file'] | Should -BeExactly 'release-please-prerelease-config.json'
        [string]$release['with']['manifest-file'] | Should -BeExactly '.release-please-prerelease-manifest.json'
        [string]$release['with']['target-branch'] | Should -BeExactly 'release/prerelease'
        [string]$release['with']['skip-github-release'] |
            Should -BeExactly "`${{ github.event.pull_request.head.ref != 'release-please--branches--release/prerelease' }}"
        [string]$release['with']['skip-github-pull-request'] |
            Should -BeExactly "`${{ github.event.pull_request.head.ref == 'release-please--branches--release/prerelease' }}"

        $outputCheck = Get-NamedJobStep -Document $script:PreReleaseDocument -JobName 'release-please' -StepName 'Validate release-please outputs'
        [string]$outputCheck['run'] | Should -Match 'prepared no release pull request'
        [string]$outputCheck['run'] | Should -Match 'changelog-visible commits'
        [string]$outputCheck['run'] | Should -Match 'pending release interlock'
    }

    It 'Proves the released commit is the merged commit contained in release/prerelease' {
        [string]$script:PreReleaseDocument['jobs']['validate-release']['if'] |
            Should -Match "needs\.release-please\.outputs\.release_created == 'true'"

        $identity = Get-NamedJobStep -Document $script:PreReleaseDocument -JobName 'validate-release' -StepName 'Verify trusted release identity'
        [string]$identity['env']['EVENT_SHA'] | Should -BeExactly '${{ github.sha }}'
        [string]$identity['env']['MERGE_SHA'] | Should -BeExactly '${{ github.event.pull_request.merge_commit_sha }}'
        [string]$identity['env']['RELEASE_SHA'] | Should -BeExactly '${{ needs.release-please.outputs.sha }}'
        $run = [string]$identity['run']
        $run | Should -Match '\[ "\$MERGE_SHA" != "\$EVENT_SHA" \]'
        $run | Should -Match '\[ "\$RELEASE_SHA" != "\$EVENT_SHA" \]'

        $checkout = Get-NamedJobStep -Document $script:PreReleaseDocument -JobName 'validate-release' -StepName 'Checkout release/prerelease history'
        [string]$checkout['with']['ref'] | Should -BeExactly 'release/prerelease'
        [string]$checkout['with']['fetch-depth'] | Should -BeExactly '0'
        $checkout['with']['persist-credentials'] | Should -BeFalse

        $steps = Get-JobStepText -Document $script:PreReleaseDocument -JobName 'validate-release'
        @($steps | Where-Object { $_ -match 'git merge-base --is-ancestor' }) | Should -HaveCount 1
        @($steps | Where-Object { $_ -match '\.release-please-prerelease-manifest\.json' }) | Should -HaveCount 1
    }

    It 'Validates an odd minor, tag namespace, and retired PreRelease intent' {
        $steps = Get-JobStepText -Document $script:PreReleaseDocument -JobName 'validate-release'
        $version = @($steps | Where-Object { $_ -match 'MINOR % 2 == 0' })
        $version | Should -HaveCount 1
        $version[0] | Should -Match '\^\[0-9\]\+\\\.\[0-9\]\+\\\.\[0-9\]\+\$'
        $version[0] | Should -Match 'prerelease-v\$RELEASE_VERSION'

        $script:PreReleaseText | Should -Not -Match 'PRE_MAJOR|PRE_MINOR'
        $committedState = @($steps | Where-Object { $_ -match 'STALE_INTENT' })
        $committedState | Should -HaveCount 1
        $committedState[0] | Should -Match 'release-please-prerelease-config\.json still carries release-as'

        # Parity cannot detect an always-bump-patch fallback, so exact intent
        # equality and its retirement carry the PreRelease release identity.
        $intent = Get-NamedJobStep -Document $script:PreReleaseDocument -JobName 'sync-release-pr' -StepName 'Update committed version fields and retire the promotion intent'
        $intentRun = [string]$intent['run']
        $intentRun | Should -Match ([regex]::Escape('CONFIG="$RELEASE_REPO/release-please-prerelease-config.json"'))
        $intentRun | Should -Match '\[ "\$INTENT" != "\$VERSION" \]'
        $intentRun | Should -Match 'but the managed release is \$VERSION'
        $intentRun | Should -Match ([regex]::Escape('del(.packages["."]["release-as"])'))
        $intentRun | Should -Match ([regex]::Escape('.release-please-prerelease-manifest.json'))
    }

    It 'Removed the explicit source resolution and custom draft creation path' {
        foreach ($job in @('resolve-source', 'create-prerelease')) {
            $script:PreReleaseDocument['jobs'].Contains($job) |
                Should -BeFalse -Because "release-please owns pre-release tag and release creation, so $job is retired"
        }
        $script:PreReleaseDocument['jobs']['release-please'] | Should -Not -BeNullOrEmpty
        $script:PreReleaseText | Should -Not -Match 'source-sha|source_sha'
        $script:PreReleaseText | Should -Not -Match 'needs\.resolve-source'
        $script:PreReleaseText | Should -Not -Match 'gh release create'
        $script:PreReleaseText | Should -Not -Match 'gh release view'
        $script:PreReleaseText | Should -Not -Match 'git/refs/tags/'
    }

    It 'Closes the pre-release milestone only after final publication' {
        @($script:PreReleaseDocument['jobs']['close-milestone']['needs']) | Should -Contain 'publish-release'
        @($script:PreReleaseDocument['jobs']['publish-release']['needs']) | Should -Contain 'upload-plugin-packages'
    }

    It 'Publishes the draft as a GitHub pre-release with the release App token' {
        $token = Get-NamedJobStep -Document $script:PreReleaseDocument -JobName 'publish-release' -StepName 'Generate GitHub App Token'
        [string]$token['id'] | Should -BeExactly 'app-token'
        [string]$token['uses'] | Should -Match '^actions/create-github-app-token@[0-9a-f]{40}$'

        # release-please cannot classify a numeric version as a pre-release, and
        # a github.token publish emits no event, so one App-token edit sets the
        # flag and drops the draft together.
        $publish = Get-NamedJobStep -Document $script:PreReleaseDocument -JobName 'publish-release' -StepName 'Publish GitHub Release'
        [string]$publish['env']['GH_TOKEN'] | Should -BeExactly '${{ steps.app-token.outputs.token }}'
        [string]$publish['run'] | Should -Match 'gh release edit "\$TAG" --prerelease --draft=false'
        @([regex]::Matches($script:PreReleaseText, 'gh release edit ')) | Should -HaveCount 1
    }

    It 'Packages the plugin and the VSIX from the validated release commit' {
        $jobs = $script:PreReleaseDocument['jobs']
        foreach ($job in @('extension-package-prerelease', 'plugin-package-prerelease')) {
            @($jobs[$job]['needs']) | Should -Contain 'validate-release'
            [string]$jobs[$job]['with']['source-ref'] | Should -BeExactly '${{ needs.validate-release.outputs.sha }}'
            [string]$jobs[$job]['with']['version'] | Should -BeExactly '${{ needs.validate-release.outputs.version }}'
        }
        [string]$jobs['extension-package-prerelease']['uses'] | Should -BeExactly './.github/workflows/extension-package.yml'
        [string]$jobs['plugin-package-prerelease']['uses'] | Should -BeExactly './.github/workflows/plugin-package.yml'
        [string]$jobs['plugin-package-prerelease']['with']['source-policy'] | Should -BeExactly 'release-tag'
        $jobs['plugin-package-prerelease']['with'].Contains('project-release-catalog') | Should -BeFalse

        $attest = Get-NamedJobStep -Document $script:PreReleaseDocument -JobName 'attest-and-upload' -StepName 'Attest build provenance'
        [string]$attest['uses'] | Should -Match '^actions/attest-build-provenance@[0-9a-f]{40}$'
        [string]$attest['with']['subject-path'] | Should -BeExactly '${{ steps.vsix.outputs.file }}'

        $upload = Get-NamedJobStep -Document $script:PreReleaseDocument -JobName 'attest-and-upload' -StepName 'Upload assets to GitHub Release'
        [string]$upload['env']['TAG'] | Should -BeExactly '${{ needs.validate-release.outputs.tag_name }}'
        [string]$upload['env']['BUNDLE_PATH'] | Should -BeExactly '${{ steps.attest.outputs.bundle-path }}'
        [string]$upload['run'] | Should -Match 'gh release upload "\$TAG"'
        [string]$upload['run'] | Should -Not -Match 'gh release (create|delete|edit)'

        @($jobs['attest-and-upload']['needs']) | Should -Contain 'extension-package-prerelease'
        @($jobs['publish-release']['needs']) | Should -Contain 'attest-and-upload'
    }
}

Describe 'Stable promotion and publication gate' -Tag 'Unit' {
    BeforeAll {
        $script:PrepareDocument = Get-WorkflowDocument -Name 'release-stable.yml'
        $script:PublishDocument = Get-WorkflowDocument -Name 'release-stable-publish.yml'
        $script:PublishText = Get-WorkflowText -Name 'release-stable-publish.yml'
    }

    It 'Opens a non-auto-merged release/prerelease to release/stable promotion pull request' {
        $steps = Get-JobStepText -Document $script:PrepareDocument -JobName 'open-promotion-pr'
        $promotion = @($steps | Where-Object { $_ -match 'gh pr create' })
        $promotion | Should -HaveCount 1
        $promotion[0] | Should -Match '--head "\$HEAD_BRANCH"'
        $promotion[0] | Should -Match '--base "\$BASE_BRANCH"'
        $job = $script:PrepareDocument['jobs']['open-promotion-pr']
        [string]$job['steps'][1]['env']['HEAD_BRANCH'] | Should -BeExactly '${{ needs.prepare-promotion.outputs.promotion-head }}'
        [string]$job['steps'][1]['env']['BASE_BRANCH'] | Should -BeExactly 'release/stable'
        [string]$job['steps'][1]['env']['SOURCE_BRANCH'] | Should -BeExactly 'release/prerelease'
        [string]$job['steps'][1]['env']['SOURCE_TAG'] | Should -BeExactly '${{ needs.prepare-promotion.outputs.source-tag }}'
        $promotion[0] | Should -Match 'EXPECTED_HEAD="\$PROMOTION_HEAD_PREFIX--\$SOURCE_TAG"'
        $promotion[0] | Should -Match '\[ "\$HEAD_BRANCH" != "\$EXPECTED_HEAD" \]'
        (Get-WorkflowText -Name 'release-stable.yml') | Should -Not -Match 'gh pr merge'
        (Get-WorkflowText -Name 'release-stable.yml') | Should -Not -Match '--auto'
    }

    It 'Promotes published PreRelease state without pre-validation jobs or release-please' {
        $prepare = $script:PrepareDocument['jobs']['prepare-promotion']
        $prepare.Contains('needs') | Should -BeFalse
        @($script:PrepareDocument['jobs']['open-promotion-pr']['needs']) | Should -Be @('prepare-promotion')
        $script:PrepareDocument['jobs'].Contains('release-please') | Should -BeFalse
        $stablePreparation = Get-WorkflowText -Name 'release-stable.yml'
        $stablePreparation | Should -Not -Match 'googleapis/release-please-action@'
        $stablePreparation | Should -Not -Match 'pester-tests'
        @($script:PrepareDocument['on']['release']['types']) | Should -Be @('published')
        [string]$script:PrepareDocument['env']['SOURCE_BRANCH'] | Should -BeExactly 'release/prerelease'
        [string]$script:PrepareDocument['env']['BASE_BRANCH'] | Should -BeExactly 'release/stable'
        [string]$script:PrepareDocument['env']['SOURCE_MANIFEST'] | Should -BeExactly '.release-please-prerelease-manifest.json'
        $dispatchTag = $script:PrepareDocument['on']['workflow_dispatch']['inputs']['prerelease-tag']
        $dispatchTag['required'] | Should -BeTrue
        [string]$dispatchTag['type'] | Should -BeExactly 'string'

        $state = Get-NamedJobStep -Document $script:PrepareDocument -JobName 'prepare-promotion' -StepName 'Resolve promotion state'
        foreach ($name in @('DISPATCH_TAG', 'EVENT_NAME', 'EVENT_TAG', 'GH_TOKEN', 'REPOSITORY')) {
            $state['env'].Contains($name) | Should -BeTrue
        }
        $stateRun = [string]$state['run']
        $stateRun | Should -Match 'release-please--'
        $stateRun | Should -Match 'release-promotion--'
        $stateRun | Should -Match '\$SOURCE_MANIFEST'
        $stateRun | Should -Match ([regex]::Escape('^prerelease-v[0-9]+\.[0-9]+\.[0-9]+$'))
        $stateRun | Should -Match '\[\[ .*SOURCE_TAG.*=~ \^prerelease-v'
        $stateRun | Should -Not -Match 'SOURCE_TAG.*\|\s*grep'
        [string]$prepare['outputs']['promotion-head'] | Should -BeExactly '${{ steps.state.outputs.promotion-head }}'
        $stateRun | Should -Match ([regex]::Escape('+refs/tags/$SOURCE_TAG:refs/tags/$SOURCE_TAG'))
        $stateRun | Should -Match ([regex]::Escape('refs/tags/$SOURCE_TAG^{commit}'))
        $stateRun | Should -Match ([regex]::Escape('git show "$SOURCE_SHA:$SOURCE_MANIFEST"'))
        $stateRun | Should -Match ([regex]::Escape('git merge-base --is-ancestor "$SOURCE_SHA" "refs/remotes/origin/$SOURCE_BRANCH"'))
        $stateRun | Should -Match ([regex]::Escape('gh release download "$SOURCE_TAG"'))
        $stateRun | Should -Match ([regex]::Escape('refs/remotes/origin/$BASE_BRANCH..$SOURCE_SHA'))
        $stateRun | Should -Not -Match 'SOURCE_SHA=\$\(git rev-parse "refs/remotes/origin/\$SOURCE_BRANCH"\)'

        # Commit classification and its release-class dispatch are gone: the
        # promoted source version alone selects the next even minor.
        @($script:PrepareDocument['jobs']['prepare-promotion']['steps'] |
                Where-Object { [string]$_['name'] -eq 'Classify promoted commits' }) | Should -HaveCount 0
        $stablePreparation | Should -Not -Match 'Classify promoted commits'
        $stablePreparation | Should -Not -Match 'release-class|release_class|release class'
        [string[]]@($script:PrepareDocument['on']['workflow_dispatch']['inputs'].Keys) | Should -Be @('prerelease-tag')
        $prepare['outputs'].Contains('release-class') | Should -BeFalse

        $resolver = Get-NamedJobStep -Document $script:PrepareDocument -JobName 'prepare-promotion' -StepName 'Resolve exact Stable version'
        foreach ($name in @('SOURCE_VERSION', 'STABLE_BASELINE')) {
            $resolver['env'].Contains($name) | Should -BeTrue
        }
        $resolverRun = [string]$resolver['run']
        $resolverRun | Should -Match 'Resolve-ReleasePromotionVersion\.ps1'
        $resolverRun | Should -Match '-Channel Stable'
        $resolverRun | Should -Match ([regex]::Escape('-PromotedSourceVersion "$SOURCE_VERSION"'))
        $resolverRun | Should -Match ([regex]::Escape('-CurrentStableVersion "$STABLE_BASELINE"'))
        $resolverRun | Should -Not -Match '-CurrentPreReleaseVersion|-ReleaseClass'
        # Canonical syntax still guards the resolved value, but the same-run
        # parity recheck is gone because the resolver owns that contract.
        $resolverRun | Should -Match ([regex]::Escape('^[0-9]+\.[0-9]+\.[0-9]+$'))
        $resolverRun | Should -Not -Match '% 2'
    }

    # release-please's json extra-files updater writes bare version values and
    # cannot express the catalog's exact release ref locator. Only the shared
    # updater running on the same preparation branch keeps the promoted commit
    # consistent; a downstream lint gate would just fail forever instead.
    It 'Runs release-please against release/stable and exposes validated release outputs' {
        $releaseJob = $script:PublishDocument['jobs']['release-please']
        $releaseJob | Should -Not -BeNullOrEmpty
        $releaseSteps = Get-JobStepText -Document $script:PublishDocument -JobName 'release-please'
        @($releaseSteps | Where-Object { $_ -match '\^release-please--' }) | Should -HaveCount 1

        $release = Get-NamedJobStep -Document $script:PublishDocument -JobName 'release-please' -StepName 'Run release-please'
        [string]$release['uses'] | Should -Match '^googleapis/release-please-action@[0-9a-f]{40}$'
        [string]$release['with']['target-branch'] | Should -BeExactly 'release/stable'
        [string]$release['with']['manifest-file'] | Should -BeExactly '.release-please-manifest.json'

        [string]$releaseJob['outputs']['release-pr-branch'] |
            Should -BeExactly '${{ steps.release-pr.outputs.branch }}'
        foreach ($output in @('release_created', 'tag_name', 'version', 'sha', 'body')) {
            $releaseJob['outputs'].Contains($output) | Should -BeTrue
        }
        $validation = @($releaseSteps | Where-Object { $_ -match 'release_created' -and $_ -match 'tag_name' -and $_ -match 'version' -and $_ -match 'sha' })
        $validation | Should -HaveCount 1
        $validation[0] | Should -Match ([regex]::Escape('"v$RELEASE_VERSION"'))
        $validation[0] | Should -Not -Match 'prerelease-v'
        $validation[0] | Should -Match 'prepared no release pull request'
        $validation[0] | Should -Match 'changelog-visible commits'
        # Release-please is the sole tag writer, so a managed merge without a
        # created release leaves the branch failed rather than silently passing.
        $validation[0] | Should -Match 'rerun tag-only creation'
    }

    It 'Prepares on the Stable promotion merge and tags only the managed release pull request' {
        $triggers = [string[]]@($script:PublishDocument['on'].Keys)
        $triggers | Should -Be @('pull_request')
        @($script:PublishDocument['on']['pull_request']['types']) | Should -Be @('closed')
        @($script:PublishDocument['on']['pull_request']['branches']) | Should -Be @('release/stable')

        $validationJob = $script:PublishDocument['jobs']['validate-trigger']
        $validationJob | Should -Not -BeNullOrEmpty
        [string]$validationJob['permissions']['contents'] | Should -BeExactly 'read'
        $guard = [string]$validationJob['if']
        $guard | Should -Match 'github\.event\.pull_request\.merged == true'
        $guard | Should -Match "github\.event\.pull_request\.base\.ref == 'release/stable'"
        $guard | Should -Match 'head\.repo\.full_name == github\.repository'
        $guard | Should -Match 'release-promotion--release-prerelease--to--release-stable--prerelease-v'
        $guard | Should -Match "head\.ref == 'release-please--branches--release/stable'"

        @($script:PublishDocument['jobs']['release-please']['needs']) | Should -Be @('validate-trigger')
        [string]$validationJob['outputs']['mode'] | Should -BeExactly '${{ steps.identity.outputs.mode }}'
        [string]$validationJob['outputs']['source-tag'] | Should -BeExactly '${{ steps.identity.outputs.source-tag }}'
        [string]$validationJob['outputs']['source-sha'] | Should -BeExactly '${{ steps.source.outputs.source-sha }}'
        $identity = Get-NamedJobStep -Document $script:PublishDocument -JobName 'validate-trigger' -StepName 'Validate merged head identity'
        [string]$identity['run'] | Should -Match 'release-promotion--release-prerelease--to--release-stable--\(prerelease-v\[0-9\]'
        [string]$identity['run'] | Should -Match '\[ "\$HEAD_REF" = "\$MANAGED_HEAD" \]'

        $configFile = [string](Get-NamedJobStep -Document $script:PublishDocument -JobName 'release-please' -StepName 'Run release-please')['with']['config-file']
        $configFile | Should -BeExactly 'release-please-config.json'

        $release = Get-NamedJobStep -Document $script:PublishDocument -JobName 'release-please' -StepName 'Run release-please'
        [string]$release['with']['skip-github-release'] |
            Should -BeExactly "`${{ needs.validate-trigger.outputs.mode != 'managed' }}"
        [string]$release['with']['skip-github-pull-request'] |
            Should -BeExactly "`${{ needs.validate-trigger.outputs.mode == 'managed' }}"

        [string]$script:PublishDocument['concurrency']['group'] | Should -BeExactly '${{ github.workflow }}-release/stable'
        $script:PublishDocument['concurrency']['cancel-in-progress'] | Should -BeFalse

        $sourceGate = Get-NamedJobStep -Document $script:PublishDocument -JobName 'validate-trigger' -StepName 'Validate selected promotion source and intent'
        $sourceGateRun = [string]$sourceGate['run']
        $sourceGateRun | Should -Match 'refs/pull/\$PR_NUMBER/head'
        $sourceGateRun | Should -Match 'refs/tags/\$SOURCE_TAG\^\{commit\}'
        $sourceGateRun | Should -Match 'git merge-base --is-ancestor "\$SOURCE_SHA" "refs/remotes/pull/\$PR_NUMBER/head"'
        $sourceGateRun | Should -Match 'plugin-release-evidence\.json'
        $sourceGateRun | Should -Match 'CANDIDATE=.*release-please-config\.json'

        $managedGate = Get-NamedJobStep -Document $script:PublishDocument -JobName 'validate-trigger' -StepName 'Validate managed release intent was consumed'
        [string]$managedGate['run'] | Should -Match 'release-as'
        [string]$managedGate['run'] | Should -Match '\[ -n "\$INTENT" \]'

        # Parity cannot detect an always-bump-patch fallback, so exact intent
        # equality and its retirement carry the Stable release identity.
        $intent = Get-NamedJobStep -Document $script:PublishDocument -JobName 'sync-release-pr' -StepName 'Update committed version fields and retire the promotion intent'
        $intentRun = [string]$intent['run']
        $intentRun | Should -Match ([regex]::Escape('CONFIG="$RELEASE_REPO/release-please-config.json"'))
        $intentRun | Should -Match '\[ "\$INTENT" != "\$VERSION" \]'
        $intentRun | Should -Match 'but the managed release is \$VERSION'
        $intentRun | Should -Match ([regex]::Escape('del(.packages["."]["release-as"])'))

        $publicationState = Get-NamedJobStep -Document $script:PublishDocument -JobName 'validate-release' -StepName 'Verify release version and committed state'
        [string]$publicationState['run'] | Should -Match 'release-please-config\.json still carries release-as'
    }

    It 'Scopes Stable promotion heads to the validated selected tag' {
        $prepare = $script:PrepareDocument['jobs']['prepare-promotion']
        $script:PrepareDocument['env'].Contains('PROMOTION_HEAD') | Should -BeFalse
        [string]$script:PrepareDocument['env']['PROMOTION_HEAD_PREFIX'] |
            Should -BeExactly 'release-promotion--release-prerelease--to--release-stable'
        [string]$prepare['outputs']['promotion-head'] | Should -BeExactly '${{ steps.state.outputs.promotion-head }}'

        $state = Get-NamedJobStep -Document $script:PrepareDocument -JobName 'prepare-promotion' -StepName 'Resolve promotion state'
        $stateRun = [string]$state['run']
        $stateRun | Should -Match 'PROMOTION_HEAD="\$PROMOTION_HEAD_PREFIX--\$SOURCE_TAG"'
        $stateRun | Should -Match 'jq -r --arg head "\$PROMOTION_HEAD"'
        $stateRun | Should -Match 'gh pr list .*--limit 100'
        $stateRun | Should -Match 'promotion-head=\$PROMOTION_HEAD'

        $refresh = Get-NamedJobStep -Document $script:PrepareDocument -JobName 'prepare-promotion' -StepName 'Refresh the promotion head'
        [string]$refresh['env']['PROMOTION_HEAD'] | Should -BeExactly '${{ steps.state.outputs.promotion-head }}'
        [string]$refresh['env']['SOURCE_TAG'] | Should -BeExactly '${{ steps.state.outputs.source-tag }}'
        [string]$refresh['run'] | Should -Match 'EXPECTED_HEAD="\$PROMOTION_HEAD_PREFIX--\$SOURCE_TAG"'
        [string]$refresh['run'] | Should -Match 'refs/heads/\$PROMOTION_HEAD'
    }

    It 'Proves the Stable release commit is the merged commit contained in release/stable' {
        [string]$script:PublishDocument['jobs']['validate-release']['if'] |
            Should -Match "needs\.release-please\.outputs\.release_created == 'true'"

        $identity = Get-NamedJobStep -Document $script:PublishDocument -JobName 'validate-release' -StepName 'Verify trusted release identity'
        [string]$identity['env']['EVENT_SHA'] | Should -BeExactly '${{ github.sha }}'
        [string]$identity['env']['MERGE_SHA'] | Should -BeExactly '${{ github.event.pull_request.merge_commit_sha }}'
        [string]$identity['env']['RELEASE_SHA'] | Should -BeExactly '${{ needs.release-please.outputs.sha }}'
        $run = [string]$identity['run']
        $run | Should -Match '\[ "\$MERGE_SHA" != "\$EVENT_SHA" \]'
        $run | Should -Match '\[ "\$RELEASE_SHA" != "\$EVENT_SHA" \]'

        $checkout = Get-NamedJobStep -Document $script:PublishDocument -JobName 'validate-release' -StepName 'Checkout release/stable history'
        [string]$checkout['with']['ref'] | Should -BeExactly 'release/stable'
        [string]$checkout['with']['fetch-depth'] | Should -BeExactly '0'
        $checkout['with']['persist-credentials'] | Should -BeFalse

        $steps = Get-JobStepText -Document $script:PublishDocument -JobName 'validate-release'
        @($steps | Where-Object { $_ -match 'git merge-base --is-ancestor' }) | Should -HaveCount 1
    }

    It 'Creates no Stable tag or GitHub release outside release-please' {
        $script:PublishDocument['jobs'].Contains('create-release') | Should -BeFalse
        $script:PublishText | Should -Not -Match 'ref=refs/tags/'
        $script:PublishText | Should -Not -Match 'gh release create '
        $script:PublishText | Should -Not -Match '--force'

        $token = Get-NamedJobStep -Document $script:PublishDocument -JobName 'publish-release' -StepName 'Generate GitHub App Token'
        [string]$token['id'] | Should -BeExactly 'app-token'
        [string]$token['uses'] | Should -Match '^actions/create-github-app-token@[0-9a-f]{40}$'
        $publish = Get-NamedJobStep -Document $script:PublishDocument -JobName 'publish-release' -StepName 'Publish GitHub Release'
        [string]$publish['env']['GH_TOKEN'] | Should -BeExactly '${{ steps.app-token.outputs.token }}'
        [string]$publish['run'] | Should -Match 'gh release edit "\$TAG" --draft=false'
    }

    It 'Packages every release asset from the validated release-please commit' {
        $jobs = $script:PublishDocument['jobs']
        foreach ($job in @('extension-provenance', 'plugin-package-release')) {
            [string]$jobs[$job]['with']['source-ref'] | Should -BeExactly '${{ needs.validate-release.outputs.sha }}'
            [string]$jobs[$job]['with']['version'] | Should -BeExactly '${{ needs.validate-release.outputs.version }}'
        }
    }

    It 'Validates a nonempty identical package set across both release channels' {
        $steps = @($script:PublishDocument['jobs']['validate-release']['steps'] | Where-Object {
                $_.Contains('run') -and [string]$_['run'] -match 'Get-MarketplacePackageMatrixCore'
            })
        $steps | Should -HaveCount 1
        $gate = [string]$steps[0]['run']
        $gate | Should -Match "@\('Stable', 'PreRelease'\)"
        $gate | Should -Match '\$names\.Count -eq 0'
        $gate | Should -Match '\[System\.StringComparer\]::Ordinal'
        $gate | Should -Match '-cne'
        $gate | Should -Match 'package sets differ'
        $gate | Should -Not -Match '-ne 1\b|exactly one'
        $script:PublishText | Should -Not -Match '(?i)one-package'
    }

    It 'Holds the cross-channel package-set invariant the Stable gate enforces' {
        $stable = [string[]]@((Get-MarketplacePackageMatrixCore -Channel Stable -CatalogPath $script:CatalogPath).Names)
        $preRelease = [string[]]@((Get-MarketplacePackageMatrixCore -Channel PreRelease -CatalogPath $script:CatalogPath).Names)
        @($stable).Count | Should -BeGreaterThan 0
        [array]::Sort($stable, [System.StringComparer]::Ordinal)
        [array]::Sort($preRelease, [System.StringComparer]::Ordinal)
        $stable | Should -Be $preRelease
    }
}

Describe 'Reusable packaging source contracts' -Tag 'Unit' {
    It 'Requires an explicit source ref and version in <Workflow>' -ForEach @(
        @{ Workflow = 'extension-package.yml' }
        @{ Workflow = 'extension-provenance.yml' }
        @{ Workflow = 'plugin-package.yml' }
    ) {
        $inputs = (Get-WorkflowDocument -Name $Workflow)['on']['workflow_call']['inputs']
        foreach ($name in @('source-ref', 'version')) {
            $inputs.Contains($name) | Should -BeTrue -Because "$Workflow must accept $name"
            $inputs[$name]['required'] | Should -BeTrue -Because "$Workflow must require $name"
            $inputs[$name].Contains('default') | Should -BeFalse -Because "$Workflow must not default $name"
        }
    }

    It 'Checks out the explicit source in every extension job of <Workflow>' -ForEach @(
        @{ Workflow = 'extension-package.yml' }
        @{ Workflow = 'extension-provenance.yml' }
    ) {
        $document = Get-WorkflowDocument -Name $Workflow
        $checkouts = 0
        foreach ($job in $document['jobs'].Values) {
            foreach ($step in @($job['steps'])) {
                if (-not $step.Contains('uses')) { continue }
                if ([string]$step['uses'] -notmatch '^actions/checkout@') { continue }
                $checkouts++
                [string]$step['with']['ref'] | Should -BeExactly '${{ inputs.source-ref }}'
                $step['with']['persist-credentials'] | Should -BeFalse
            }
        }
        $checkouts | Should -BeGreaterThan 0
    }

    It 'Requires an explicit provenance policy for plugin packaging' {
        $inputs = (Get-WorkflowDocument -Name 'plugin-package.yml')['on']['workflow_call']['inputs']
        $inputs.Contains('source-policy') | Should -BeTrue
        $inputs['source-policy']['required'] | Should -BeTrue
        [string]$inputs['source-policy']['type'] | Should -BeExactly 'string'
        $inputs['source-policy'].Contains('default') | Should -BeFalse
    }

    It 'Requires the exact channel release tag for plugin packaging' {
        $inputs = (Get-WorkflowDocument -Name 'plugin-package.yml')['on']['workflow_call']['inputs']
        $inputs.Contains('release-tag') | Should -BeTrue
        $inputs['release-tag']['required'] | Should -BeTrue
        [string]$inputs['release-tag']['type'] | Should -BeExactly 'string'
        $inputs['release-tag'].Contains('default') | Should -BeFalse

        # Each release lane hands the packaging call the tag release-please
        # actually created, so no lane can derive a different identity.
        foreach ($lane in @(
                @{ Workflow = 'release-prerelease.yml'; PackageJob = 'plugin-package-prerelease' },
                @{ Workflow = 'release-stable-publish.yml'; PackageJob = 'plugin-package-release' }
            )) {
            [string](Get-WorkflowDocument -Name $lane.Workflow)['jobs'][$lane.PackageJob]['with']['release-tag'] |
                Should -BeExactly '${{ needs.validate-release.outputs.tag_name }}'
        }
    }

    It 'Passes the exact Stable tag to extension provenance release upload' {
        $document = Get-WorkflowDocument -Name 'extension-provenance.yml'
        $inputs = $document['on']['workflow_call']['inputs']
        $inputs.Contains('release-tag') | Should -BeTrue
        [string]$inputs['release-tag']['type'] | Should -BeExactly 'string'
        [string]$inputs['release-tag']['default'] | Should -BeExactly ''

        $upload = Get-NamedJobStep -Document $document -JobName 'build-attest' -StepName 'Upload assets to GitHub Release'
        [string]$upload['env']['RELEASE_TAG'] | Should -BeExactly '${{ inputs.release-tag }}'
        [string]$upload['run'] | Should -Match 'gh release upload \$tag'
        [string]$upload['run'] | Should -Not -Match 'gh release (create|delete|edit)'

        [string](Get-WorkflowDocument -Name 'release-stable-publish.yml')['jobs']['extension-provenance']['with']['release-tag'] |
            Should -BeExactly '${{ needs.validate-release.outputs.tag_name }}'
    }

    It 'Verifies source provenance before target-tree execution in plugin job <Job>' -ForEach @(
        @{ Job = 'discover-packages' }
        @{ Job = 'package' }
    ) {
        $document = Get-WorkflowDocument -Name 'plugin-package.yml'
        $steps = @($document['jobs'][$Job]['steps'])
        $checkout = @($steps | Where-Object { $_.Contains('uses') -and [string]$_['uses'] -match '^actions/checkout@' })
        $checkout | Should -HaveCount 1
        $checkout[0]['with'].Contains('ref') | Should -BeFalse
        $checkout[0]['with']['persist-credentials'] | Should -BeFalse

        $proof = @($steps | Where-Object { $_.Contains('run') -and [string]$_['run'] -match 'SOURCE_POLICY' })
        $proof | Should -HaveCount 1
        $run = [string]$proof[0]['run']
        foreach ($pattern in @(
                '\^\[0-9a-f\]\{40\}\$',
                "'main-ancestor'",
                "'release-tag'",
                'refs/heads/main:refs/remotes/origin/main',
                'git merge-base --is-ancestor',
                'refs/tags/\$\{RELEASE_TAG\}',
                'rev-parse --verify --end-of-options',
                'git checkout --quiet --detach',
                'git rev-parse HEAD',
                'Unsupported source policy'
            )) {
            $run | Should -Match $pattern
        }

        $proofIndex = [array]::IndexOf($steps, $proof[0])
        $executionIndexes = @(0..($steps.Count - 1) | Where-Object {
                ([string]$steps[$_]['uses'] -match '^\./|^actions/setup-node@') -or
                ([string]$steps[$_]['run'] -match 'npm (ci|run)|\.ps1\b')
            })
        $executionIndexes.Count | Should -BeGreaterThan 0
        $proofIndex | Should -BeLessThan $executionIndexes[0]
    }

    It 'Wires each release lane to its matching plugin source policy' {
        $preRelease = Get-WorkflowDocument -Name 'release-prerelease.yml'
        [string]$preRelease['jobs']['plugin-package-prerelease']['with']['source-policy'] |
            Should -BeExactly 'release-tag'

        $stable = Get-WorkflowDocument -Name 'release-stable-publish.yml'
        [string]$stable['jobs']['plugin-package-release']['with']['source-policy'] |
            Should -BeExactly 'release-tag'
    }

    It 'Fails a blank source ref or version in <Workflow>' -ForEach @(
        @{ Workflow = 'extension-package.yml'; Job = 'discover-packages' }
        @{ Workflow = 'extension-provenance.yml'; Job = 'discover-packages' }
        @{ Workflow = 'plugin-package.yml'; Job = 'discover-packages' }
        @{ Workflow = 'plugin-package.yml'; Job = 'publish-evidence' }
    ) {
        $steps = Get-JobStepText -Document (Get-WorkflowDocument -Name $Workflow) -JobName $Job
        @($steps | Where-Object { $_ -match 'source-ref is required and must not be blank' }) | Should -HaveCount 1
        @($steps | Where-Object { $_ -match 'version is required and must not be blank' }) | Should -HaveCount 1
    }

    It 'Consumes the version input in the plugin lane' {
        $steps = Get-JobStepText -Document (Get-WorkflowDocument -Name 'plugin-package.yml') -JobName 'package'
        @($steps | Where-Object { $_ -match 'Assert-PluginReleaseEvidence\.ps1' }) | Should -HaveCount 0

        $evidence = @(Get-JobStepText -Document (Get-WorkflowDocument -Name 'plugin-package.yml') -JobName 'publish-evidence' |
                Where-Object { $_ -match 'Assert-PluginReleaseEvidence\.ps1' })
        $evidence | Should -HaveCount 2
        foreach ($step in $evidence) {
            $step | Should -Match '-SourceCommit \$env:INPUT_SOURCE_REF'
            $step | Should -Match '-Version \$env:INPUT_VERSION'
            $step | Should -Match '-ReleaseTag \$env:RELEASE_TAG'

            # The channel is derived locally from the validated release tag, so
            # no caller can hand the evidence producer a mismatched channel.
            $step | Should -Match ([regex]::Escape('$env:RELEASE_TAG.StartsWith(''prerelease-v'', [System.StringComparison]::Ordinal)'))
            $step | Should -Match ([regex]::Escape('$env:RELEASE_TAG.StartsWith(''v'', [System.StringComparison]::Ordinal)'))
            $step | Should -Match "'PreRelease'"
            $step | Should -Match "'Stable'"
            $step | Should -Match 'does not match a known channel grammar'
            $step | Should -Match ([regex]::Escape('-Channel $channel'))
            $step | Should -Not -Match '-EvidenceVersion'
        }
        $evidence[0] | Should -Match '-ExpectedPackageCount \$expectedCount'
        $evidence[0] | Should -Match '-OutputPath logs/plugin-release-evidence\.json'
        $evidence[1] | Should -Match '-ExpectedEvidencePath logs/plugin-release-evidence\.json'
    }

    It 'Removes projected release catalogs from reusable plugin packaging' {
        $plugin = Get-WorkflowDocument -Name 'plugin-package.yml'
        $plugin['on']['workflow_call']['inputs'].Contains('project-release-catalog') | Should -BeFalse

        $pluginText = Get-WorkflowText -Name 'plugin-package.yml'
        foreach ($forbidden in @(
                'project-release-catalog',
                'PROJECT_RELEASE_CATALOG',
                'projected-marketplace',
                '-MarketplaceOutputPath',
                'Generate-Plugins\.ps1'
            )) {
            $pluginText | Should -Not -Match $forbidden
        }

        foreach ($step in @(
                (Get-NamedJobStep -Document $plugin -JobName 'discover-packages' -StepName 'Verify version and committed catalog'),
                (Get-NamedJobStep -Document $plugin -JobName 'discover-packages' -StepName 'Discover marketplace packages'),
                (Get-NamedJobStep -Document $plugin -JobName 'package' -StepName 'Generate committed plugins')
            )) {
            $step.Contains('if') | Should -BeFalse
        }

        $preRelease = Get-WorkflowDocument -Name 'release-prerelease.yml'
        $preRelease['jobs']['plugin-package-prerelease']['with'].Contains('project-release-catalog') | Should -BeFalse
        $stable = Get-WorkflowDocument -Name 'release-stable-publish.yml'
        $stable['jobs']['plugin-package-release']['with'].Contains('project-release-catalog') | Should -BeFalse
    }

    It 'Binds recorded evidence to the discovered package set' {
        $document = Get-WorkflowDocument -Name 'plugin-package.yml'
        $record = Get-NamedJobStep -Document $document -JobName 'publish-evidence' -StepName 'Record canonical release evidence'
        [string]$record['env']['DISCOVERED_NAMES'] | Should -BeExactly '${{ needs.discover-packages.outputs.names }}'
        [string]$record['env']['INPUT_SOURCE_REF'] | Should -BeExactly '${{ inputs.source-ref }}'
        [string]$record['env']['INPUT_VERSION'] | Should -BeExactly '${{ inputs.version }}'

        $run = [string]$record['run']
        $run | Should -Match 'ConvertFrom-Json'
        $run | Should -Match 'Package discovery produced no package names'
        $run | Should -Match '-ExpectedPackageCount \$expectedCount'

        # Record, reproduce, then publish. A document that cannot be recomputed
        # from the same tracked sources never reaches the release.
        $names = [string[]]@($document['jobs']['publish-evidence']['steps'] | ForEach-Object { [string]$_['name'] })
        [array]::IndexOf($names, 'Record canonical release evidence') |
            Should -BeLessThan ([array]::IndexOf($names, 'Verify recorded evidence reproduces'))
        [array]::IndexOf($names, 'Verify recorded evidence reproduces') |
            Should -BeLessThan ([array]::IndexOf($names, 'Upload evidence to GitHub Release'))
    }

    # Historical release tags in both retired namespaces stay immutable and keep
    # resolving. Retirement is prospective only, so no workflow may create, move,
    # delete, or force-update either namespace again.
    It 'Creates, moves, deletes, or force-updates no retired release tag in any workflow' {
        $workflows = @(Get-ChildItem -LiteralPath $script:WorkflowDirectory -Filter '*.yml' -File)
        $workflows | Should -Not -BeNullOrEmpty
        foreach ($workflow in $workflows) {
            $text = Get-Content -LiteralPath $workflow.FullName -Raw -Encoding utf8
            foreach ($namespace in @('plugins-v', 'hve-core-v')) {
                foreach ($forbidden in @(
                        "refs/tags/$namespace",
                        "git tag[^\n]*$namespace",
                        "git push[^\n]*$namespace",
                        "gh release (create|delete|edit|upload|delete-asset)[^\n]*$namespace",
                        "-ReleaseTag\s+[`"']?$namespace",
                        "-Tag\s+[`"']?$namespace",
                        "-BaselineTag\s+[`"']?$namespace"
                    )) {
                    $text | Should -Not -Match $forbidden -Because "$($workflow.Name) must not write the retired $namespace namespace"
                }
            }
            foreach ($forbidden in @(
                    'push --force',
                    'push[^\n]*--force',
                    'push[^\n]*--delete',
                    'Assert-PluginSnapshotTarget'
                )) {
                $text | Should -Not -Match $forbidden -Because "$($workflow.Name) must not force-update, delete, or target a retired release snapshot"
            }
        }
    }

    It 'Retired the orphan snapshot publisher and every workflow reference to it' {
        Test-Path -LiteralPath (Join-Path $script:WorkflowDirectory 'plugin-snapshot-publish.yml') |
            Should -BeFalse -Because 'canonical release evidence replaces orphan snapshot publication'
        foreach ($workflow in @(Get-ChildItem -LiteralPath $script:WorkflowDirectory -Filter '*.yml' -File)) {
            $text = Get-Content -LiteralPath $workflow.FullName -Raw -Encoding utf8
            foreach ($forbidden in @('plugin-snapshot-publish\.yml', 'plugin-snapshot-production', 'plugins-snapshot/')) {
                $text | Should -Not -Match $forbidden -Because "$($workflow.Name) must not reference the retired publisher"
            }
        }
    }

    It 'Grants release write permission only to the evidence publishing job' {
        $document = Get-WorkflowDocument -Name 'plugin-package.yml'
        [string]$document['permissions']['contents'] | Should -BeExactly 'read'
        foreach ($name in @('discover-packages', 'package')) {
            [string]$document['jobs'][$name]['permissions']['contents'] | Should -BeExactly 'read'
        }

        $evidenceJob = $document['jobs']['publish-evidence']
        [string]$evidenceJob['needs'] | Should -BeExactly 'discover-packages'
        [string]$evidenceJob['permissions']['contents'] | Should -BeExactly 'write'
        [string]$evidenceJob['permissions']['id-token'] | Should -BeExactly 'write'
        [string]$evidenceJob['permissions']['attestations'] | Should -BeExactly 'write'

        $attest = Get-NamedJobStep -Document $document -JobName 'publish-evidence' -StepName 'Attest build provenance'
        [string]$attest['uses'] | Should -Match '^actions/attest-build-provenance@[0-9a-f]{40}$'
        [string]$attest['with']['subject-path'] | Should -BeExactly 'logs/plugin-release-evidence.json'

        $upload = Get-NamedJobStep -Document $document -JobName 'publish-evidence' -StepName 'Upload evidence to GitHub Release'
        [string]$upload['env']['TAG'] | Should -BeExactly '${{ inputs.release-tag }}'
        [string]$upload['run'] | Should -Match 'gh release upload "\$TAG"'
        [string]$upload['run'] | Should -Match 'logs/plugin-release-evidence\.json'
        [string]$upload['run'] | Should -Not -Match 'gh release (create|delete|edit)'
    }

    It 'Publishes canonical release evidence for both release lanes before publication' {
        foreach ($lane in @(
                @{ Workflow = 'release-prerelease.yml'; PackageJob = 'plugin-package-prerelease' },
                @{ Workflow = 'release-stable-publish.yml'; PackageJob = 'plugin-package-release' }
            )) {
            $document = Get-WorkflowDocument -Name $lane.Workflow
            $job = $document['jobs'][$lane.PackageJob]
            [string]$job['uses'] | Should -BeExactly './.github/workflows/plugin-package.yml'

            # The reusable call writes a release asset and attests it, so the
            # caller must grant exactly those permissions.
            [string]$job['permissions']['contents'] | Should -BeExactly 'write'
            [string]$job['permissions']['id-token'] | Should -BeExactly 'write'
            [string]$job['permissions']['attestations'] | Should -BeExactly 'write'

            # Producer before consumer: publication waits on the packaging call
            # that uploads the evidence asset every catalog consumer reads.
            @($document['jobs']['upload-plugin-packages']['needs']) | Should -Contain $lane.PackageJob
            @($document['jobs']['publish-release']['needs']) | Should -Contain 'upload-plugin-packages'
        }
    }

    It 'Verifies published attestations for the exact channel tag in <Workflow>' -ForEach @(
        @{ Workflow = 'release-prerelease.yml'; VerifyPattern = 'gh attestation verify "\$f" --repo "\$REPOSITORY"' }
        @{ Workflow = 'release-stable-publish.yml'; VerifyPattern = 'Invoke-ProvenanceVerification\.ps1' }
    ) {
        $document = Get-WorkflowDocument -Name $Workflow
        [string]$document['jobs']['verify-provenance']['permissions']['attestations'] | Should -BeExactly 'read'

        $download = Get-NamedJobStep -Document $document -JobName 'verify-provenance' -StepName 'Download release artifacts'
        [string]$download['env']['RELEASE_TAG'] | Should -BeExactly '${{ needs.validate-release.outputs.tag_name }}'
        [string]$download['run'] | Should -Match "-p '\*\.vsix'"

        @(Get-JobStepText -Document $document -JobName 'verify-provenance' |
                Where-Object { $_ -match $VerifyPattern }) | Should -HaveCount 1
    }

    It 'Publishes the marketplace lanes from the released ref' {
        # Generated lock workflows are runnable, so every workflow YAML class is a
        # caller candidate and none is excluded from discovery.
        $publisherCallers = [string[]]@(Get-ChildItem -LiteralPath $script:WorkflowDirectory -File |
                Where-Object { $_.Extension -in @('.yml', '.yaml') } |
                Where-Object {
                    (Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8) -match
                    'uses:\s+\./\.github/workflows/extension-marketplace-publish\.yml'
                } |
                ForEach-Object { $_.Name } |
                Sort-Object)
        $publisherCallers | Should -Be @('release-marketplace-prerelease.yml', 'release-marketplace-stable.yml')

        $stable = Get-WorkflowDocument -Name 'release-marketplace-stable.yml'
        $checkout = @($stable['jobs']['discover']['steps'] | Where-Object { $_.Contains('uses') -and [string]$_['uses'] -match '^actions/checkout@' })
        $checkout | Should -HaveCount 1
        [string]$checkout[0]['with']['ref'] | Should -BeExactly '${{ needs.normalize-version.outputs.tag }}'

        $prerelease = Get-WorkflowDocument -Name 'release-marketplace-prerelease.yml'
        [string]$prerelease['jobs']['package']['with']['source-ref'] | Should -BeExactly '${{ needs.validate-version.outputs.tag }}'
        [string]$prerelease['jobs']['package']['with']['version'] | Should -BeExactly '${{ needs.validate-version.outputs.version }}'

        [string]$stable['jobs']['publish']['with']['tag'] | Should -BeExactly '${{ needs.normalize-version.outputs.tag }}'
        $stable['jobs']['publish']['with']['pre-release'] | Should -BeFalse
        $stable['jobs']['publish']['with'].Contains('verify-attestation') | Should -BeFalse
        [string]$stable['jobs']['publish']['with']['attestation-signer-workflow'] |
            Should -BeExactly '.github/workflows/extension-provenance.yml'

        [string]$prerelease['jobs']['publish']['with']['tag'] | Should -BeExactly '${{ needs.validate-version.outputs.tag }}'
        $prerelease['jobs']['publish']['with']['pre-release'] | Should -BeTrue
        $prerelease['jobs']['publish']['with'].Contains('verify-attestation') | Should -BeFalse
        [string]$prerelease['jobs']['publish']['with']['attestation-signer-workflow'] |
            Should -BeExactly '.github/workflows/release-prerelease.yml'
        # Normal publication consumes discovery, so it no longer waits on the
        # dry-run packaging call it never read artifacts from.
        @($prerelease['jobs']['publish']['needs']) | Should -Contain 'validate-version'
        @($prerelease['jobs']['publish']['needs']) | Should -Contain 'discover'
        @($prerelease['jobs']['publish']['needs']) | Should -Not -Contain 'package'

        # The publisher verifies the release VSIX against the commit its release
        # tag names, so both producer lanes must attest this run's own event SHA.
        foreach ($lane in @('release-prerelease.yml', 'release-stable-publish.yml')) {
            [string](Get-WorkflowDocument -Name $lane)['jobs']['validate-release']['outputs']['sha'] |
                Should -BeExactly '${{ github.sha }}'
        }
        [string](Get-WorkflowDocument -Name 'release-stable-publish.yml')['jobs']['extension-provenance']['with']['source-ref'] |
            Should -BeExactly '${{ needs.validate-release.outputs.sha }}'

        $provenance = Get-WorkflowDocument -Name 'extension-provenance.yml'
        [string]$provenance['on']['workflow_call']['inputs']['source-ref']['description'] |
            Should -Match '(?i)full commit SHA'
        [string]$provenance['on']['workflow_call']['inputs']['source-ref']['description'] |
            Should -Not -Match '(?i)\bor tag\b'
        @($provenance['jobs']['build-attest']['needs']) | Should -Contain 'discover-packages'
        $sourceGuard = Get-NamedJobStep -Document $provenance -JobName 'discover-packages' -StepName 'Resolve effective version'
        [string]$sourceGuard['env']['EVENT_SHA'] | Should -BeExactly '${{ github.sha }}'
        [string]$sourceGuard['run'] | Should -Match ([regex]::Escape('^[0-9a-f]{40}$'))
        [string]$sourceGuard['run'] | Should -Match ([regex]::Escape('[ "$INPUT_SOURCE_REF" != "$EVENT_SHA" ]'))
    }

    It 'Keeps PreRelease marketplace event values out of shell source and permits release lookup' {
        $document = Get-WorkflowDocument -Name 'release-marketplace-prerelease.yml'
        $job = $document['jobs']['validate-version']
        [string]$job['permissions']['contents'] | Should -BeExactly 'read'
        $steps = Get-JobStepText -Document $document -JobName 'validate-version'
        foreach ($step in $steps) {
            $step | Should -Not -Match '\$\{\{\s*(github\.event|inputs\.)'
        }
        $resolve = @($job['steps'] | Where-Object { [string]$_['id'] -eq 'resolve' })[0]
        foreach ($name in @('EVENT_NAME', 'EVENT_TAG', 'MANUAL_VERSION', 'REPOSITORY')) {
            $resolve['env'].Contains($name) | Should -BeTrue
        }

        # Manual dispatch and the automatic release event reach the same channel
        # parity gate, so neither path can publish the wrong minor.
        [string]$job['if'] | Should -Match "github\.event_name == 'workflow_dispatch'"
        [string]$job['if'] | Should -Match 'github\.event\.release\.prerelease == true'
        $validate = @($job['steps'] | Where-Object { [string]$_['id'] -eq 'validate' })[0]
        [string]$validate['run'] | Should -Match 'PUBLISH_MINOR % 2 == 0'
        [string]$validate['run'] | Should -Match 'requires odd minor version'
        [string]$document['jobs']['package']['with']['channel'] | Should -BeExactly 'PreRelease'

        # Normal publication discovers the PreRelease package set from the
        # released tag, and only a dry run still builds VSIX artifacts.
        [string]$document['jobs']['package']['if'] | Should -BeExactly '${{ inputs.dry-run }}'
        $preReleaseCheckout = @($document['jobs']['discover']['steps'] |
                Where-Object { $_.Contains('uses') -and [string]$_['uses'] -match '^actions/checkout@' })
        $preReleaseCheckout | Should -HaveCount 1
        [string]$preReleaseCheckout[0]['with']['ref'] | Should -BeExactly 'refs/tags/${{ needs.validate-version.outputs.tag }}'
        $preReleaseCheckout[0]['with']['persist-credentials'] | Should -BeFalse
        $preReleaseDiscover = @($document['jobs']['discover']['steps'] | Where-Object { [string]$_['id'] -eq 'discover' })[0]
        [string]$preReleaseDiscover['run'] | Should -Match "-Channel 'PreRelease'"

        $stable = Get-WorkflowDocument -Name 'release-marketplace-stable.yml'
        $stableJob = $stable['jobs']['normalize-version']
        [string]$stableJob['permissions']['contents'] | Should -BeExactly 'read'
        [string]$stableJob['if'] | Should -Match "github\.event_name == 'workflow_dispatch'"
        [string]$stableJob['if'] | Should -Match 'github\.event\.release\.prerelease == false'
        $normalize = @($stableJob['steps'] | Where-Object { [string]$_['id'] -eq 'normalize' })[0]
        [string]$normalize['run'] | Should -Match 'PUBLISH_MINOR % 2 == 1'
        [string]$normalize['run'] | Should -Match 'requires even minor version'
        $discover = @($stable['jobs']['discover']['steps'] | Where-Object { [string]$_['id'] -eq 'discover' })[0]
        [string]$discover['run'] | Should -Match "-Channel 'Stable'"
    }
}

Describe 'Promotion and publication contracts' -Tag 'Unit' {
    BeforeAll {
        $script:PrepareDocument = Get-WorkflowDocument -Name 'release-stable.yml'
        $script:PublishDocument = Get-WorkflowDocument -Name 'release-stable-publish.yml'
    }

    It 'Keeps a stable per-hop promotion head and restores only release-owned fields' -ForEach @(
        @{
            Workflow = 'release-prerelease-prepare.yml'
            Source = 'main'
            Base = 'release/prerelease'
            Head = 'release-promotion--main--to--release-prerelease'
            HeadVariable = 'PROMOTION_HEAD'
            RestoreSource = $false
            Config = 'release-please-prerelease-config.json'
            Manifest = '.release-please-prerelease-manifest.json'
            Channel = 'PreRelease'
            ResolverStep = 'Resolve exact PreRelease version'
            ResolverInput = '-CurrentPreReleaseVersion "$PRERELEASE_BASELINE"'
            ForbiddenResolverInput = '-PromotedSourceVersion'
            ConstructedBaselineTag = 'prerelease-v$TARGET_VERSION'
            BootstrapSha = '0d4452b33c2409d03315019dae0d34e468641dfb'
            StableState = $false
        }
        @{
            Workflow = 'release-stable.yml'
            Source = 'release/prerelease'
            Base = 'release/stable'
            Head = 'release-promotion--release-prerelease--to--release-stable'
            HeadVariable = 'PROMOTION_HEAD_PREFIX'
            RestoreSource = $true
            Config = 'release-please-config.json'
            Manifest = '.release-please-manifest.json'
            Channel = 'Stable'
            ResolverStep = 'Resolve exact Stable version'
            ResolverInput = '-CurrentStableVersion "$STABLE_BASELINE"'
            ForbiddenResolverInput = '-CurrentPreReleaseVersion'
            ConstructedBaselineTag = 'v$TARGET_VERSION'
            BootstrapSha = 'e69486a5f809ede45c63c0a31358c12912bd5168'
            StableState = $true
        }
    ) {
        $document = Get-WorkflowDocument -Name $Workflow
        [string]$document['env']['SOURCE_BRANCH'] | Should -BeExactly $Source
        [string]$document['env']['BASE_BRANCH'] | Should -BeExactly $Base
        [string]$document['env'][$HeadVariable] | Should -BeExactly $Head
        [string]$document['env']['TARGET_CONFIG'] | Should -BeExactly $Config
        [string]$document['env']['TARGET_MANIFEST'] | Should -BeExactly $Manifest

        $text = Get-WorkflowText -Name $Workflow
        $text | Should -Not -Match 'gh pr merge|--auto|push --force|ref=refs/tags/'

        # Commit classification and the cross-channel baseline read are gone;
        # each lane resolves from the branch state it already owns.
        $text | Should -Not -Match 'Classify promoted commits'
        $text | Should -Not -Match 'release-class|release_class|release class'
        $prepareOutputs = $document['jobs']['prepare-promotion']['outputs']
        foreach ($removed in @('release-class', 'stable-baseline-source')) {
            $prepareOutputs.Contains($removed) | Should -BeFalse
        }

        $resolver = Get-NamedJobStep -Document $document -JobName 'prepare-promotion' -StepName $ResolverStep
        $resolverRun = [string]$resolver['run']
        $resolverRun | Should -Match "-Channel $Channel"
        $resolverRun | Should -Match ([regex]::Escape($ResolverInput))
        $resolverRun | Should -Not -Match ([regex]::Escape($ForbiddenResolverInput))

        if ($StableState) {
            [string]$document['env']['SOURCE_MANIFEST'] | Should -BeExactly '.release-please-prerelease-manifest.json'
            [string]$prepareOutputs['stable-baseline'] | Should -BeExactly '${{ steps.state.outputs.stable-baseline }}'
            [string](Get-NamedJobStep -Document $document -JobName 'prepare-promotion' -StepName 'Resolve promotion state')['run'] |
                Should -Match 'STABLE_BASELINE=\$\(git show "refs/remotes/origin/\$BASE_BRANCH:\$TARGET_MANIFEST"'
        }
        else {
            foreach ($removed in @('SOURCE_MANIFEST', 'STABLE_BRANCH', 'STABLE_MANIFEST')) {
                $document['env'].Contains($removed) | Should -BeFalse
            }
            $prepareOutputs.Contains('stable-baseline') | Should -BeFalse
            $text | Should -Not -Match 'STABLE_BASELINE|STABLE_BRANCH|STABLE_MANIFEST|stable-baseline|release/stable|Read Stable baseline'
            $resolverRun | Should -Match ([regex]::Escape('^[0-9]+\.[0-9]+\.[0-9]+$'))
            $resolverRun | Should -Match '\[\[ .*VERSION.*=~ \^\[0-9\]'
            $resolverRun | Should -Not -Match '% 2'
        }

        $refresh = Get-NamedJobStep -Document $document -JobName 'prepare-promotion' -StepName 'Refresh the promotion head'
        $run = [string]$refresh['run']
        $run | Should -Match 'merge_ref "refs/remotes/origin/\$BASE_BRANCH" theirs'
        $run | Should -Match 'merge_ref "\$SOURCE_SHA" theirs'
        # The complete prior marketplace is restored with the other target-owned
        # release state, so promotion never introduces candidate membership. The
        # changelog and catalog must exist at the base; a seeded branch that
        # predates its branch-local manifest promotes the merged source copy
        # instead of failing on an absent path. The channel config is absent
        # from this early restore: its ownership is decided further below, from
        # the baseline locator the restored catalog carries.
        $run | Should -Match ([regex]::Escape('restore_from_base required CHANGELOG.md .github/plugin/marketplace.json'))
        $run | Should -Match ([regex]::Escape('restore_from_base optional "$TARGET_MANIFEST"'))
        $run | Should -Match ([regex]::Escape('git cat-file -e "refs/remotes/origin/$BASE_BRANCH:$path"'))
        $run | Should -Match ([regex]::Escape('git checkout "refs/remotes/origin/$BASE_BRANCH" -- "${present[@]}"'))
        $run | Should -Not -Match 'CHANGELOG\.md "\$TARGET_CONFIG" "\$TARGET_MANIFEST" \\\s*\.github/plugin/marketplace\.json'
        [string[]]@(
            [regex]::Matches($run, '(?m)^\s*restore_from_base .+$') | ForEach-Object { $_.Value.Trim() }
        ) | Should -Be @(
            'restore_from_base required CHANGELOG.md .github/plugin/marketplace.json'
            'restore_from_base optional "$TARGET_MANIFEST"'
            'restore_from_base optional "$TARGET_CONFIG"'
        )
        $run | Should -Match 'Update-VersionFiles\.ps1'
        $run | Should -Match "-Channel $Channel"
        $run | Should -Not -Match '-CatalogRefMode'
        $run | Should -Match '-SkipManifest'
        $run | Should -Match '-SkipPluginGenerate'
        $run | Should -Match 'release-as'

        # One candidate record binds channel, immutable source, baseline tag,
        # candidate version, and both canonical digests.
        $run | Should -Match ([regex]::Escape('CANDIDATE_SOURCE_CATALOG="$RUNNER_TEMP/candidate-source-marketplace.json"'))
        $run | Should -Match ([regex]::Escape('git show "$SOURCE_SHA:.github/plugin/marketplace.json" > "$CANDIDATE_SOURCE_CATALOG"'))
        $run | Should -Match '-CandidateAction Record'
        $run | Should -Match ([regex]::Escape('-CandidateVersion "$VERSION"'))
        $run | Should -Match ([regex]::Escape('-CandidateSourceCommit "$SOURCE_SHA"'))
        $run | Should -Match ([regex]::Escape('-CandidateSourceCatalog "$CANDIDATE_SOURCE_CATALOG"'))

        # The recorded baseline identity is the one uniform locator the restored
        # target catalog already carries, so no channel prefix and baseline
        # version can assert a namespace the branch never held. Derivation is
        # shape-tolerant: a historical string-form source names no ref, so a
        # wholly ref-less bootstrap catalog derives the reserved OMITTED locator
        # instead of failing while indexing a string.
        $run | Should -Match ([regex]::Escape('BASELINE_TAG=$(jq -r '''))
        $run | Should -Match ([regex]::Escape("' .github/plugin/marketplace.json)"))
        $run | Should -Match ([regex]::Escape('(.metadata.version // "") as $version'))
        $run | Should -Match ([regex]::Escape('[.plugins[] | (.version // "")] as $versions'))
        $run | Should -Match ([regex]::Escape('if (.source | type) == "object" then (.source.ref // null) else null end] as $refs'))
        $run | Should -Match ([regex]::Escape('($version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))'))
        $run | Should -Match ([regex]::Escape('($versions | length) > 0'))
        $run | Should -Match ([regex]::Escape('($versions | all(. == $version))'))
        $run | Should -Match ([regex]::Escape('if ($refs | all(. == null))'))
        $run | Should -Match ([regex]::Escape('then "OMITTED"'))
        $run | Should -Match ([regex]::Escape('elif ($refs | all(type == "string" and length > 0))'))
        $run | Should -Match ([regex]::Escape('(($refs | unique) | length) == 1'))
        $run | Should -Match ([regex]::Escape('[ -z "$BASELINE_TAG" ]'))
        $run | Should -Match ([regex]::Escape('does not carry one uniform baseline locator across a complete catalog at its own metadata version'))
        # A string-form source is never indexed, and the channel manifest version
        # no longer filters the catalog the target branch already publishes.
        $run | Should -Not -Match ([regex]::Escape('select((.version // "") == $version)'))
        $run | Should -Not -Match ([regex]::Escape('| (.source.ref // null)] as $refs'))
        $run | Should -Not -Match ([regex]::Escape('jq -r --arg version "$TARGET_VERSION"'))
        $run | Should -Match ([regex]::Escape('-BaselineTag "$BASELINE_TAG"'))
        $run | Should -Not -Match ([regex]::Escape("-BaselineTag `"$ConstructedBaselineTag`""))
        $run.IndexOf('BASELINE_TAG=$(jq', [System.StringComparison]::Ordinal) |
            Should -BeLessThan $run.IndexOf('Update-VersionFiles.ps1', [System.StringComparison]::Ordinal)

        # The config anchor is the source of truth for the seed and the changelog
        # cutoff. It is captured in the state step from the current source
        # configuration and consumed here through that step output, so a restored
        # target copy the seed predates can never supply it. OMITTED describes
        # the ref-less bootstrap catalog, so it is accepted only while the target
        # branch tip is still that seed commit; an exact channel tag baseline is
        # never held to the bootstrap tip.
        [string]$refresh['env']['BOOTSTRAP_SHA'] | Should -BeExactly '${{ steps.state.outputs.bootstrap-sha }}'
        $run | Should -Not -Match ([regex]::Escape('BOOTSTRAP_SHA=$(jq'))
        $run | Should -Match ([regex]::Escape('grep -Eq ''^[0-9a-f]{40}$'''))
        $run | Should -Match ([regex]::Escape('Captured bootstrap-sha anchor is not a lowercase 40-character commit id'))
        $run | Should -Match ([regex]::Escape('if [ "$BASELINE_TAG" = ''OMITTED'' ]; then'))
        $run | Should -Match ([regex]::Escape('BASE_TIP=$(git rev-parse "refs/remotes/origin/$BASE_BRANCH")'))
        $run | Should -Match ([regex]::Escape('[ "$BASE_TIP" != "$BOOTSTRAP_SHA" ]'))

        # The derived locator, not the restore order, decides who owns the
        # channel config. First cutover keeps the merged current source config
        # so the branch adopts current tag, draft, and versioning policy instead
        # of the retired behavior its historical seed carries; every later
        # promotion restores the target copy and keeps steady-state settings.
        # Either way the captured anchor and release intent are written after.
        $ownership = [regex]::Match(
            $run,
            '(?s)if \[ "\$BASELINE_TAG" = ''OMITTED'' \]; then(?<omitted>.*?)\r?\n\s*else\r?\n(?<exact>.*?)\r?\n\s*fi\r?\n').Groups
        $ownership['omitted'].Value | Should -Not -Match 'restore_from_base'
        $ownership['omitted'].Value | Should -Match ([regex]::Escape('becomes its first branch-local release configuration'))
        $ownership['exact'].Value | Should -Match ([regex]::Escape('restore_from_base optional "$TARGET_CONFIG"'))
        $run.IndexOf('BASELINE_TAG=$(jq', [System.StringComparison]::Ordinal) |
            Should -BeLessThan $run.IndexOf('restore_from_base optional "$TARGET_CONFIG"', [System.StringComparison]::Ordinal)
        $run.IndexOf('restore_from_base optional "$TARGET_CONFIG"', [System.StringComparison]::Ordinal) |
            Should -BeLessThan $run.IndexOf('--arg bootstrap "$BOOTSTRAP_SHA"', [System.StringComparison]::Ordinal)

        # The captured anchor is persisted with the exact release intent, so a
        # target config introduced by this promotion still carries the current
        # changelog cutoff and seed identity.
        $run | Should -Match ([regex]::Escape('jq --arg version "$VERSION" --arg bootstrap "$BOOTSTRAP_SHA"'))
        $run | Should -Match ([regex]::Escape('.packages["."]["bootstrap-sha"] = $bootstrap'))
        $run | Should -Match ([regex]::Escape('.packages["."]["release-as"] = $version'))
        $run | Should -Match ([regex]::Escape('WRITTEN_ANCHOR=$(jq -r ''.packages["."]["bootstrap-sha"] // ""'' "$TARGET_CONFIG")'))
        $run | Should -Match ([regex]::Escape('[ "$WRITTEN_ANCHOR" != "$BOOTSTRAP_SHA" ]'))

        # The seed the workflow names must be the anchor the config carries, and
        # promotion never creates the branch it reports as missing.
        $anchor = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot $Config) -Raw -Encoding utf8 |
            ConvertFrom-Json -AsHashtable
        [string]$anchor['packages']['.']['bootstrap-sha'] | Should -BeExactly $BootstrapSha

        $state = Get-NamedJobStep -Document $document -JobName 'prepare-promotion' -StepName 'Resolve promotion state'
        $stateRun = [string]$state['run']
        $stateRun | Should -Match ([regex]::Escape('bootstrap-sha'))
        $stateRun | Should -Match 'does not exist yet; create it at'
        $stateRun | Should -Match 'protect'

        # The anchor is read from the current source configuration, before any
        # remote target state is fetched or restored, and published as the state
        # output the refresh step consumes.
        $stateRun | Should -Match ([regex]::Escape('BOOTSTRAP_SHA=$(jq -r ''.packages["."]["bootstrap-sha"] // ""'' "$TARGET_CONFIG")'))
        $stateRun | Should -Match ([regex]::Escape('carries no lowercase 40-character bootstrap-sha anchor'))
        $stateRun | Should -Match ([regex]::Escape('echo "bootstrap-sha=$BOOTSTRAP_SHA"'))
        $stateRun.IndexOf('BOOTSTRAP_SHA=$(jq', [System.StringComparison]::Ordinal) |
            Should -BeLessThan $stateRun.IndexOf('git fetch --no-tags origin', [System.StringComparison]::Ordinal)
        foreach ($forbidden in @('git push origin "refs/heads/$BASE_BRANCH"', 'git branch', 'gh api --method POST', '/git/refs')) {
            $stateRun | Should -Not -Match ([regex]::Escape($forbidden))
        }

        $run | Should -Match 'git add --all'
        $run | Should -Match ([regex]::Escape("'.github/plugin/release-candidate.json'"))

        if ($RestoreSource) {
            $run | Should -Match 'git checkout "\$SOURCE_SHA" --'
            $sourceRestore = [regex]::Match($run, '(?s)git checkout "\$SOURCE_SHA" -- \\\r?\n(?<files>.*?)\r?\n\s*\r?\n').Groups['files'].Value
            $sourceRestore | Should -Match 'package\.json package-lock\.json'
            $sourceRestore | Should -Match 'extension/templates/package\.template\.json'
            # Only the target-owned restore may carry the catalog.
            $sourceRestore | Should -Not -Match 'marketplace\.json'
            $run.IndexOf('merge_ref "$SOURCE_SHA"', [System.StringComparison]::Ordinal) |
                Should -BeLessThan $run.IndexOf('git checkout "$SOURCE_SHA"', [System.StringComparison]::Ordinal)
            $run.IndexOf('git checkout "$SOURCE_SHA"', [System.StringComparison]::Ordinal) |
                Should -BeLessThan $run.IndexOf('Update-VersionFiles.ps1', [System.StringComparison]::Ordinal)
        }
        else {
            $run | Should -Not -Match 'git checkout .*package\.json'
        }
        $run.IndexOf('merge_ref "$SOURCE_SHA"', [System.StringComparison]::Ordinal) |
            Should -BeLessThan $run.IndexOf('Update-VersionFiles.ps1', [System.StringComparison]::Ordinal)
        $run.IndexOf('Update-VersionFiles.ps1', [System.StringComparison]::Ordinal) |
            Should -BeLessThan $run.IndexOf('release-as', [System.StringComparison]::Ordinal)
    }

    # The PreRelease seed commit predates branch-local channel state, so the
    # first reviewed promotion is what introduces the missing manifest from the
    # merged source. Until then the baseline comes from the seeded catalog, and
    # only while the branch still sits on the exact captured anchor.
    It 'Falls back to the seeded catalog only at the exact PreRelease anchor' {
        $document = Get-WorkflowDocument -Name 'release-prerelease-prepare.yml'
        $stateRun = [string](Get-NamedJobStep -Document $document -JobName 'prepare-promotion' -StepName 'Resolve promotion state')['run']

        # A present target manifest still owns the baseline.
        $stateRun | Should -Match ([regex]::Escape('if TARGET_MANIFEST_JSON=$(git show "refs/remotes/origin/$BASE_BRANCH:$TARGET_MANIFEST" 2>/dev/null); then'))
        $stateRun | Should -Match ([regex]::Escape('PRERELEASE_BASELINE=$(printf ''%s'' "$TARGET_MANIFEST_JSON" | jq -r ''.["."] // ""'')'))

        # The fallback is gated on exact seed-tip equality with the captured
        # anchor and derives a complete catalog version, or it fails closed.
        $stateRun | Should -Match ([regex]::Escape('BASE_TIP=$(git rev-parse "refs/remotes/origin/$BASE_BRANCH")'))
        $stateRun | Should -Match ([regex]::Escape('if [ "$BASE_TIP" != "$BOOTSTRAP_SHA" ]; then'))
        $stateRun | Should -Match ([regex]::Escape('carries no $TARGET_MANIFEST and its tip $BASE_TIP is not the $TARGET_CONFIG bootstrap-sha $BOOTSTRAP_SHA'))
        $stateRun | Should -Match ([regex]::Escape('git show "refs/remotes/origin/$BASE_BRANCH:.github/plugin/marketplace.json"'))
        $stateRun | Should -Match ([regex]::Escape('(.metadata.version // "") as $version'))
        $stateRun | Should -Match ([regex]::Escape('[.plugins[] | (.version // "")] as $versions'))
        $stateRun | Should -Match ([regex]::Escape('($version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))'))
        $stateRun | Should -Match ([regex]::Escape('($versions | all(. == $version))'))
        $stateRun | Should -Match ([regex]::Escape('if [ -z "$PRERELEASE_BASELINE" ]; then'))
        $stateRun | Should -Match ([regex]::Escape('seed .github/plugin/marketplace.json carries no complete MAJOR.MINOR.PATCH catalog version'))

        # The fallback never widens into ancestry or a branch write.
        foreach ($forbidden in @('merge-base --is-ancestor', 'git push', 'git branch', 'git update-ref')) {
            $stateRun | Should -Not -Match ([regex]::Escape($forbidden))
        }

        # The seeded PreRelease catalog is the exact anchor commit, carries a
        # complete ref-less catalog, and predates branch-local channel state.
        $preReleaseConfig = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'release-please-prerelease-config.json') -Raw -Encoding utf8 |
            ConvertFrom-Json -AsHashtable
        [string]$preReleaseConfig['packages']['.']['bootstrap-sha'] |
            Should -BeExactly '0d4452b33c2409d03315019dae0d34e468641dfb'
    }

    # The applied baseline identity is read from the target release branch the
    # candidate advances from, at the same immutable remote ref that supplied
    # its manifest baseline. A drifted baseline catalog therefore fails the
    # retained record instead of reissuing a rebuilt namespace.
    It 'Derives the applied baseline identity from the target branch catalog in <Workflow>' -ForEach @(
        @{
            Workflow = 'release-prerelease.yml'
            Base = 'release/prerelease'
            Channel = 'PreRelease'
            ConstructedBaselineTag = 'prerelease-v$BASELINE'
        }
        @{
            Workflow = 'release-stable-publish.yml'
            Base = 'release/stable'
            Channel = 'Stable'
            ConstructedBaselineTag = 'v$BASELINE'
        }
    ) {
        $sync = Get-NamedJobStep -Document (Get-WorkflowDocument -Name $Workflow) `
            -JobName 'sync-release-pr' `
            -StepName 'Update committed version fields and retire the promotion intent'
        $run = [string]$sync['run']

        $run | Should -Match ([regex]::Escape("'+refs/heads/${Base}:refs/remotes/origin/${Base}'"))
        $run | Should -Match ([regex]::Escape("'refs/remotes/origin/${Base}:.github/plugin/marketplace.json'"))
        # Derivation is shape-tolerant: a historical string-form source names no
        # ref, so a ref-less catalog derives OMITTED instead of failing while
        # indexing a string. Completeness is proved against the catalog's own
        # metadata version, not the channel manifest baseline.
        $run | Should -Match ([regex]::Escape('(.metadata.version // "") as $version'))
        $run | Should -Match ([regex]::Escape('[.plugins[] | (.version // "")] as $versions'))
        $run | Should -Match ([regex]::Escape('if (.source | type) == "object" then (.source.ref // null) else null end] as $refs'))
        $run | Should -Match ([regex]::Escape('($version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))'))
        $run | Should -Match ([regex]::Escape('($versions | length) > 0'))
        $run | Should -Match ([regex]::Escape('($versions | all(. == $version))'))
        $run | Should -Match ([regex]::Escape('if ($refs | all(. == null))'))
        $run | Should -Match ([regex]::Escape('then "OMITTED"'))
        $run | Should -Match ([regex]::Escape('elif ($refs | all(type == "string" and length > 0))'))
        $run | Should -Match ([regex]::Escape('(($refs | unique) | length) == 1'))
        $run | Should -Not -Match ([regex]::Escape('jq -r --arg version "$BASELINE"'))
        $run | Should -Not -Match ([regex]::Escape('select((.version // "") == $version)'))
        $run | Should -Not -Match ([regex]::Escape('| (.source.ref // null)] as $refs'))
        $run | Should -Match ([regex]::Escape('[ -z "$BASELINE_TAG" ]'))
        $run | Should -Match ([regex]::Escape("${Base} .github/plugin/marketplace.json does not carry one uniform baseline locator across a complete catalog at its own metadata version"))

        $run | Should -Match "-Channel $Channel"
        $run | Should -Match '-CandidateAction Apply'
        $run | Should -Match ([regex]::Escape('-BaselineTag "$BASELINE_TAG"'))
        $run | Should -Not -Match ([regex]::Escape("-BaselineTag `"$ConstructedBaselineTag`""))
        $run.IndexOf('BASELINE_TAG=$(git', [System.StringComparison]::Ordinal) |
            Should -BeLessThan $run.IndexOf('Update-VersionFiles.ps1', [System.StringComparison]::Ordinal)
    }

    # An occupied tag or GitHub release is immutable, so release-please could
    # never issue that candidate. The probe therefore runs read-only, before any
    # branch mutation or release-intent write, and fails closed.
    It 'Proves the candidate release identity is unoccupied before mutating <Workflow>' -ForEach @(
        @{ Workflow = 'release-prerelease-prepare.yml'; TagPrefix = 'prerelease-v' }
        @{ Workflow = 'release-stable.yml'; TagPrefix = 'v' }
    ) {
        $document = Get-WorkflowDocument -Name $Workflow
        $probe = Get-NamedJobStep -Document $document -JobName 'prepare-promotion' -StepName 'Validate candidate release identity is unoccupied'
        [string]$probe['if'] | Should -BeExactly "`${{ steps.state.outputs.continue == 'true' }}"
        [string]$probe['env']['GH_TOKEN'] | Should -BeExactly '${{ github.token }}'
        [string]$probe['env']['REPOSITORY'] | Should -BeExactly '${{ github.repository }}'
        [string]$probe['env']['VERSION'] | Should -BeExactly '${{ steps.resolve.outputs.version }}'

        $run = [string]$probe['run']
        $run | Should -Match 'set -euo pipefail'
        $run | Should -Match ([regex]::Escape('cd "$GITHUB_WORKSPACE/promotion"'))
        $run | Should -Match ([regex]::Escape("CANDIDATE_REF=`"refs/tags/$TagPrefix`$VERSION`""))
        $run | Should -Match ([regex]::Escape('git ls-remote origin "$CANDIDATE_REF"'))
        $run | Should -Match ([regex]::Escape("gh api --include `"/repos/`$REPOSITORY/releases/tags/$TagPrefix`$VERSION`""))

        # Only an explicit not-found proves availability; success means occupied
        # and every other outcome is an error rather than a pass.
        $run | Should -Match 'PROBE_EXIT=\$\?'
        $run | Should -Match '\[ "\$PROBE_EXIT" -eq 0 \]'
        $run | Should -Match 'HTTP 404'
        $run | Should -Match 'no explicit not-found result'

        foreach ($forbidden in @('gh release ', 'ref=refs/tags/', 'git tag', 'git push', '--force', '--method', '-X POST', '-X PATCH', '-X DELETE')) {
            $run | Should -Not -Match ([regex]::Escape($forbidden))
        }

        $names = [string[]]@($document['jobs']['prepare-promotion']['steps'] | ForEach-Object { [string]$_['name'] })
        [array]::IndexOf($names, 'Validate candidate release identity is unoccupied') |
            Should -BeLessThan ([array]::IndexOf($names, 'Refresh the promotion head'))
    }

    # Release-please tags after the managed merge, so a retry may only resume on
    # state that already agrees. Every other observed state is terminal, and no
    # lane may move, delete, or force-update the tag to reconcile it.
    It 'Classifies tag and release recovery state without tag mutation in <Workflow>' -ForEach @(
        # PreRelease publication sets the pre-release flag as it drops the draft,
        # so only an already published release must carry it. Stable publication
        # drops the draft alone, so a draft carrying the flag would publish as a
        # pre-release; Stable rejects it in draft and published state alike.
        @{ Workflow = 'release-prerelease.yml'; ManagedGuard = '[ "$MERGED_HEAD" = ''release-please--branches--release/prerelease'' ]'; ChannelGuard = 'if [ "$DRAFT" != ''true'' ] && [ "$PRERELEASE" != ''true'' ]; then'; ForbiddenChannelGuard = 'if [ "$PRERELEASE" != ''true'' ]; then'; ChannelError = 'published without the pre-release flag' }
        @{ Workflow = 'release-stable-publish.yml'; ManagedGuard = '[ "$VALIDATED_MODE" = ''managed'' ]'; ChannelGuard = 'if [ "$PRERELEASE" != ''false'' ]; then'; ForbiddenChannelGuard = '[ "$DRAFT" != ''true'' ] && [ "$PRERELEASE"'; ChannelError = 'carries the pre-release flag; Stable requires prerelease=false' }
    ) {
        $document = Get-WorkflowDocument -Name $Workflow
        $classify = Get-NamedJobStep -Document $document -JobName 'validate-release' -StepName 'Classify tag and release recovery state'
        [string]$classify['id'] | Should -BeExactly 'classify'
        # Release-please creates a draft, and a draft is invisible to the
        # workflow token, so classification reads it through the release App
        # token while the job keeps contents: read.
        [string]$classify['env']['GH_TOKEN'] | Should -BeExactly '${{ steps.app-token.outputs.token }}'
        [string]$classify['env']['RELEASE_SHA'] | Should -BeExactly '${{ github.sha }}'
        [string]$classify['env']['RELEASE_TAG'] | Should -BeExactly '${{ needs.release-please.outputs.tag_name }}'

        $validateSteps = @($document['jobs']['validate-release']['steps'])
        $appToken = @($validateSteps | Where-Object { [string]$_['id'] -eq 'app-token' })
        $appToken | Should -HaveCount 1
        [string]$appToken[0]['uses'] | Should -Match '^actions/create-github-app-token@[0-9a-f]{40}$'
        $validateSteps.IndexOf($appToken[0]) | Should -BeLessThan $validateSteps.IndexOf($classify)
        [string]$document['jobs']['validate-release']['permissions']['contents'] | Should -BeExactly 'read'

        $run = [string]$classify['run']
        # Current remote tag identity is required. The refresh cannot be ignored,
        # so a transport, auth, or fetch failure is terminal instead of accepting
        # a stale local tag from an older checkout.
        $run | Should -Match ([regex]::Escape('git ls-remote --tags --refs origin "refs/tags/$RELEASE_TAG"'))
        $run | Should -Match 'Unable to read refs/tags/\$RELEASE_TAG from origin'
        $run | Should -Match ([regex]::Escape('if [ -z "$REMOTE_TAG" ]; then'))
        $run | Should -Match ([regex]::Escape('git fetch --no-tags origin "+refs/tags/$RELEASE_TAG:refs/tags/$RELEASE_TAG"'))
        foreach ($line in @($run -split '\r?\n' | Where-Object { $_ -match 'git (ls-remote|fetch) ' })) {
            $line | Should -Not -Match '\|\|\s*(true|:|exit\s+0)' -Because 'a failed tag refresh cannot be swallowed'
        }
        $run.IndexOf('git ls-remote') | Should -BeLessThan $run.IndexOf('git rev-parse')

        # Absent tag, and a tag that targets any other commit, are both terminal.
        $run | Should -Match ([regex]::Escape('refs/tags/$RELEASE_TAG^{commit}'))
        $run | Should -Match 'does not exist; rerun release-please tag-only creation'
        $run | Should -Match ([regex]::Escape('[ "$TAG_SHA" != "$RELEASE_SHA" ]'))
        $run | Should -Match 'targets \$TAG_SHA instead of the managed merge'
        # A missing release resumes at release creation; an incompatible channel
        # state is terminal. A draft is absent from /releases/tags/{tag}, so the
        # release list is paginated and matched on exact tag_name, and every API
        # or parse failure is terminal rather than an absent release.
        $run | Should -Match ([regex]::Escape('gh api --paginate "/repos/$REPOSITORY/releases?per_page=100"'))
        $run | Should -Match ([regex]::Escape('jq -s --arg tag "$RELEASE_TAG" ''[.[][] | select(.tag_name == $tag)]'''))
        $run | Should -Match ([regex]::Escape('MATCH_COUNT=$(printf ''%s'' "$MATCHED_RELEASES" | jq ''length'')'))
        $run | Should -Match ([regex]::Escape('if [ "$MATCH_COUNT" -gt 1 ]; then'))
        $run | Should -Match 'matches \$MATCH_COUNT GitHub releases; reconcile the duplicates'
        $run | Should -Match ([regex]::Escape('if [ "$MATCH_COUNT" -eq 0 ]; then'))
        $run | Should -Match 'Unable to list releases for \$REPOSITORY'
        $run | Should -Match 'Unable to parse the release list'
        $run | Should -Not -Match ([regex]::Escape('/repos/$REPOSITORY/releases/tags/'))
        $run | Should -Not -Match ([regex]::Escape('2>/dev/null || true'))
        $run | Should -Match 'has no GitHub release; rerun release-please release creation'
        $run | Should -Match ([regex]::Escape($ChannelGuard))
        $run | Should -Not -Match ([regex]::Escape($ForbiddenChannelGuard))
        $run | Should -Match ([regex]::Escape($ChannelError))
        # Draft and matching published state resume the ordinary downstream jobs.
        $run | Should -Match 'Resuming \$RELEASE_TAG at \$TAG_SHA'

        # The managed-merge recovery reads the release identity and never writes
        # or reconciles a reference, so classification stays the sole owner of
        # tag-target and channel-state decisions.
        $recovery = [string](Get-NamedJobStep -Document $document -JobName 'release-please' -StepName 'Validate release-please outputs')['run']
        foreach ($stepRun in @($run, $recovery)) {
            foreach ($forbidden in @('git tag', 'git push', 'git update-ref', '--force', '-X POST', '-X PATCH', '-X DELETE', 'gh release create', 'gh release delete', 'gh release edit')) {
                $stepRun | Should -Not -Match ([regex]::Escape($forbidden))
            }
        }
        $recovery | Should -Match ([regex]::Escape($ManagedGuard))
        $recovery | Should -Match 'rerun tag-only creation'
        $recovery | Should -Not -Match 'TAG_SHA|\.draft|\.prerelease'

        # Asset uploads replace assets on the same release only.
        $text = Get-WorkflowText -Name $Workflow
        @([regex]::Matches($text, 'gh release upload ')).Count | Should -BeGreaterThan 0
        $text | Should -Not -Match 'gh release (create|delete)'
    }

    # A managed rerun creates nothing, so release-please reports no release even
    # though one already exists. Recovery synthesizes that existing identity into
    # the job outputs; absent state stays terminal.
    It 'Synthesizes existing managed release identity into release-please outputs in <Workflow>' -ForEach @(
        @{ Workflow = 'release-prerelease.yml'; ManagedGuard = '[ "$MERGED_HEAD" = ''release-please--branches--release/prerelease'' ]'; Manifest = '.release-please-prerelease-manifest.json'; ForeignManifest = '"/repos/$REPOSITORY/contents/.release-please-manifest.json'; TagExpression = 'RELEASE_TAG="prerelease-v$RELEASE_VERSION"' }
        @{ Workflow = 'release-stable-publish.yml'; ManagedGuard = '[ "$VALIDATED_MODE" = ''managed'' ]'; Manifest = '.release-please-manifest.json'; ForeignManifest = '.release-please-prerelease-manifest.json'; TagExpression = 'RELEASE_TAG="v$RELEASE_VERSION"' }
    ) {
        $document = Get-WorkflowDocument -Name $Workflow
        $step = Get-NamedJobStep -Document $document -JobName 'release-please' -StepName 'Validate release-please outputs'
        foreach ($name in @('EVENT_SHA', 'GH_TOKEN', 'REPOSITORY')) {
            $step['env'].Contains($name) | Should -BeTrue -Because "recovery reads the immutable event SHA through the API"
        }
        [string]$step['env']['EVENT_SHA'] | Should -BeExactly '${{ github.sha }}'
        # Recovery must see the draft release release-please already created, so
        # it reads through the release App token the job already generates.
        [string]$step['env']['GH_TOKEN'] | Should -BeExactly '${{ steps.app-token.outputs.token }}'
        [string]$step['env']['REPOSITORY'] | Should -BeExactly '${{ github.repository }}'

        $run = [string]$step['run']
        $run | Should -Match ([regex]::Escape("$ManagedGuard && [ `"`$RELEASE_CREATED`" != 'true' ]"))
        # The version comes from this channel's manifest at the immutable event
        # SHA, never from the moving release branch.
        $run | Should -Match ([regex]::Escape("`"/repos/`$REPOSITORY/contents/$Manifest?ref=`$EVENT_SHA`""))
        $run | Should -Not -Match ([regex]::Escape($ForeignManifest))
        $run | Should -Not -Match 'refs/heads/|origin/release/|git rev-parse|git show'
        $run | Should -Match ([regex]::Escape($TagExpression))

        # An existing GitHub release for the derived tag is required, and the
        # draft release-please creates is absent from /releases/tags/{tag}. The
        # paginated release list is matched on exact tag_name instead, so an API
        # or parse failure is terminal and only zero matches keeps the branch
        # failed until release-please reruns.
        $run | Should -Match ([regex]::Escape('gh api --paginate "/repos/$REPOSITORY/releases?per_page=100"'))
        $run | Should -Match ([regex]::Escape('jq -s --arg tag "$RELEASE_TAG" ''[.[][] | select(.tag_name == $tag)]'''))
        $run | Should -Match ([regex]::Escape('if [ "$MATCH_COUNT" -gt 1 ]; then'))
        $run | Should -Match 'matches \$MATCH_COUNT GitHub releases; reconcile the duplicates'
        $run | Should -Match ([regex]::Escape('if [ "$MATCH_COUNT" -eq 0 ]; then'))
        $run | Should -Match 'Unable to list releases for \$REPOSITORY while recovering'
        $run | Should -Match 'Unable to parse the release list while recovering'
        $run | Should -Not -Match ([regex]::Escape('/repos/$REPOSITORY/releases/tags/'))
        $run | Should -Match ([regex]::Escape('RELEASE_BODY=$(printf ''%s'' "$MATCHED_RELEASES" | jq -r ''.[0].body // ""'')'))
        $run | Should -Match 'created no tag or release for merged managed head \$MERGED_HEAD; rerun tag-only creation'

        # Recovered identity flows through the same shared identity checks and
        # into the job outputs validate-release consumes.
        $run | Should -Match ([regex]::Escape('RELEASE_SHA="$EVENT_SHA"'))
        $run | Should -Match ([regex]::Escape("RELEASE_CREATED='true'"))
        foreach ($output in @('release_created=$RELEASE_CREATED', 'tag_name=$RELEASE_TAG', 'version=$RELEASE_VERSION', 'sha=$RELEASE_SHA')) {
            $run | Should -Match ([regex]::Escape($output))
        }

        $jobOutputs = $document['jobs']['release-please']['outputs']
        [string]$jobOutputs['release_created'] | Should -BeExactly '${{ steps.release-pr.outputs.release_created }}'
        [string]$jobOutputs['tag_name'] | Should -BeExactly '${{ steps.release-pr.outputs.tag_name }}'
        [string]$jobOutputs['version'] | Should -BeExactly '${{ steps.release-pr.outputs.version }}'
        [string]$jobOutputs['sha'] | Should -BeExactly '${{ steps.release-pr.outputs.sha }}'
    }

    It 'Separates matching draft state from matching published state in <Workflow>' -ForEach @(
        @{ Workflow = 'release-prerelease.yml' }
        @{ Workflow = 'release-stable-publish.yml' }
    ) {
        $document = Get-WorkflowDocument -Name $Workflow
        $run = [string](Get-NamedJobStep -Document $document -JobName 'validate-release' -StepName 'Classify tag and release recovery state')['run']
        $run | Should -Match ([regex]::Escape("RECOVERY_STATE='draft'"))
        $run | Should -Match ([regex]::Escape("if [ `"`$DRAFT`" != 'true' ]; then"))
        $run | Should -Match ([regex]::Escape("RECOVERY_STATE='published'"))
        $run | Should -Match ([regex]::Escape('echo "release-state=$RECOVERY_STATE" >> "$GITHUB_OUTPUT"'))
        # The matched release id is published once, so downstream verification
        # never resolves the release again through a draft-blind endpoint.
        $run | Should -Match ([regex]::Escape('RELEASE_ID=$(printf ''%s'' "$MATCHED_RELEASES" | jq -r ''.[0].id'')'))
        $run | Should -Match ([regex]::Escape('echo "release-id=$RELEASE_ID" >> "$GITHUB_OUTPUT"'))

        [string]$document['jobs']['validate-release']['outputs']['release-state'] |
            Should -BeExactly '${{ steps.classify.outputs.release-state }}'
        [string]$document['jobs']['validate-release']['outputs']['release-id'] |
            Should -BeExactly '${{ steps.classify.outputs.release-id }}'
    }

    # A matching published release is completed creation and publication, so its
    # required evidence is verified rather than rebuilt or clobbered.
    It 'Verifies published release assets instead of rebuilding them in <Workflow>' -ForEach @(
        @{ Workflow = 'release-prerelease.yml'; RequiredAssets = @('dependencies.spdx.json', 'plugin-release-evidence.json') }
        @{ Workflow = 'release-stable-publish.yml'; RequiredAssets = @('dependencies.spdx.json', 'plugin-release-evidence.json', 'hve-core.openvex.json') }
    ) {
        $document = Get-WorkflowDocument -Name $Workflow
        $verify = Get-NamedJobStep -Document $document -JobName 'validate-release' -StepName 'Verify published release assets'
        [string]$verify['if'] | Should -BeExactly "`${{ steps.classify.outputs.release-state == 'published' }}"
        [string]$verify['env']['GH_TOKEN'] | Should -BeExactly '${{ github.token }}'
        [string]$verify['env']['REPOSITORY'] | Should -BeExactly '${{ github.repository }}'
        [string]$verify['env']['RELEASE_ID'] | Should -BeExactly '${{ steps.classify.outputs.release-id }}'
        [string]$verify['env']['RELEASE_TAG'] | Should -BeExactly '${{ needs.release-please.outputs.tag_name }}'

        $run = [string]$verify['run']
        $run | Should -Match ([regex]::Escape('gh api --paginate "/repos/$REPOSITORY/releases/$RELEASE_ID/assets?per_page=100"'))
        # Classification already matched the release, so verification consumes
        # that id instead of resolving the draft-blind tag endpoint again.
        $run | Should -Not -Match ([regex]::Escape('/repos/$REPOSITORY/releases/tags/'))
        $run | Should -Not -Match ([regex]::Escape('RELEASE_ID=$('))
        foreach ($asset in $RequiredAssets) {
            $run | Should -Match ([regex]::Escape("'$asset'"))
        }
        # Every published VSIX and plugin ZIP carries its SPDX, Sigstore, and
        # in-toto sidecars, and both artifact kinds must be present.
        $run | Should -Match ([regex]::Escape('"$asset.spdx.json" "$asset.sigstore.json" "$asset.intoto.jsonl"'))
        $run | Should -Match ([regex]::Escape('*.vsix) VSIX_COUNT=$((VSIX_COUNT + 1))'))
        $run | Should -Match ([regex]::Escape('*.zip) ZIP_COUNT=$((ZIP_COUNT + 1))'))
        $run | Should -Match ([regex]::Escape('[ "$VSIX_COUNT" -eq 0 ] || [ "$ZIP_COUNT" -eq 0 ]'))

        # Incomplete evidence is terminal, and verification never writes assets.
        $run | Should -Match ([regex]::Escape('if [ "$INCOMPLETE" -ne 0 ]; then'))
        @([regex]::Matches($run, 'exit 1')).Count | Should -BeGreaterThan 1
        foreach ($forbidden in @('gh release upload', 'gh release download', '--clobber', 'download-artifact')) {
            $run | Should -Not -Match ([regex]::Escape($forbidden))
        }
    }

    # Skipping the direct artifact-producing roots skips every dependent job, so
    # a verified published release reruns no packaging, upload, or publication.
    # Draft state leaves the ordinary resume path, including partial assets.
    It 'Skips every artifact-producing chain for a matching published release in <Workflow>' -ForEach @(
        @{ Workflow = 'release-prerelease.yml'; SkipRoots = @('extension-package-prerelease', 'plugin-package-prerelease', 'generate-dependency-sbom') }
        @{ Workflow = 'release-stable-publish.yml'; SkipRoots = @('extension-provenance', 'plugin-package-release', 'generate-dependency-sbom') }
    ) {
        $document = Get-WorkflowDocument -Name $Workflow
        $jobs = $document['jobs']
        foreach ($root in $SkipRoots) {
            [string]$jobs[$root]['if'] |
                Should -BeExactly "`${{ needs.validate-release.outputs.release-state != 'published' }}" -Because "$root produces release artifacts"
        }

        # validate-release itself keeps running, so classification and asset
        # verification still execute for a published release.
        $jobs['validate-release'].Contains('if') | Should -BeTrue
        [string]$jobs['validate-release']['if'] | Should -Match "release_created == 'true'"

        $dependents = @($jobs.Keys | Where-Object {
                $_ -ne 'validate-release' -and (Get-JobNeedsClosure -Jobs $jobs -JobName $_) -contains 'validate-release'
            })
        @($dependents).Count | Should -BeGreaterThan @($SkipRoots).Count
        foreach ($dependent in $dependents) {
            $closure = @(Get-JobNeedsClosure -Jobs $jobs -JobName $dependent)
            @($SkipRoots | Where-Object { $_ -eq $dependent -or $closure -contains $_ }) |
                Should -Not -BeNullOrEmpty -Because "$dependent must reach a gated root so it skips with the published release"
            # Nothing overrides skip propagation back into the chain.
            if ($SkipRoots -notcontains $dependent) {
                [string]$jobs[$dependent]['if'] | Should -Not -Match 'always\(|cancelled\(|failure\('
            }
        }
    }

    It 'Reverifies the retained candidate record at the released commit in <Workflow>' -ForEach @(
        @{ Workflow = 'release-prerelease.yml'; Channel = 'PreRelease' }
        @{ Workflow = 'release-stable-publish.yml'; Channel = 'Stable' }
    ) {
        $document = Get-WorkflowDocument -Name $Workflow
        $verify = Get-NamedJobStep -Document $document -JobName 'validate-release' -StepName 'Verify retained candidate record'
        [string]$verify['env']['RELEASE_VERSION'] | Should -BeExactly '${{ needs.release-please.outputs.version }}'

        $run = [string]$verify['run']
        $run | Should -Match 'scripts/release/Update-VersionFiles\.ps1'
        $run | Should -Match "-Channel $Channel"
        $run | Should -Match '-CandidateAction Verify'
    }

    It 'Keeps main catalog synchronization retired across every workflow' {
        $script:PublishDocument['jobs'].Contains('open-main-sync-pr') | Should -BeFalse
        (Get-WorkflowText -Name 'release-stable-publish.yml') | Should -Not -Match 'release-main-catalog-sync|gh pr merge|--auto'

        Test-Path -LiteralPath (Join-Path $script:WorkflowDirectory 'release-main-catalog-sync.yml') |
            Should -BeFalse -Because 'main is refreshed explicitly rather than by automated catalog synchronization'
        foreach ($workflow in @(Get-ChildItem -LiteralPath $script:WorkflowDirectory -Filter '*.yml' -File)) {
            $text = Get-Content -LiteralPath $workflow.FullName -Raw -Encoding utf8
            $text | Should -Not -Match 'main-catalog-sync' -Because "$($workflow.Name) must not reference retired main catalog synchronization"
        }
    }

    It 'Gates Stable promotion intent on release/stable pull requests' {
        $prValidation = Get-WorkflowDocument -Name 'pr-validation.yml'
        @($prValidation['on']['pull_request']['branches']) |
            Should -Be @('main', 'develop', 'release/prerelease', 'release/stable')

        $stableMonotonic = Get-NamedJobStep -Document $prValidation -JobName 'gate-completeness-check' -StepName 'Validate Stable promotion intent advances release/stable'
        [string]$stableMonotonic['if'] | Should -Match "github\.event\.pull_request\.base\.ref == 'release/stable'"
        [string]$stableMonotonic['if'] | Should -Match 'release-promotion--release-prerelease--to--release-stable--prerelease-v'
        [string]$stableMonotonic['run'] | Should -Match 'CANDIDATE=.*release-please-config\.json'
        [string]$stableMonotonic['run'] | Should -Match 'BASELINE=.*\.release-please-manifest\.json'
        [string]$stableMonotonic['run'] | Should -Match 'already contained in release/stable'
        # A separate-run gate re-derives parity and advancement from the pull
        # request head, independently of the preparation run that proposed them.
        [string]$stableMonotonic['run'] | Should -Match 'SOURCE_MINOR % 2 == 0'
        [string]$stableMonotonic['run'] | Should -Match 'CANDIDATE_MINOR % 2 != 0'
        [string]$stableMonotonic['run'] | Should -Match 'has an odd minor'
        [string]$stableMonotonic['run'] | Should -Match 'sort -V \| tail -1'
        [string]$stableMonotonic['run'] | Should -Match 'release/stable already carries \$BASELINE'
    }

    It 'Proves the managed release head reproduces its retained candidate' {
        $prValidation = Get-WorkflowDocument -Name 'pr-validation.yml'
        $step = Get-NamedJobStep -Document $prValidation `
            -JobName 'gate-completeness-check' `
            -StepName 'Verify managed release head reproduces its retained candidate'

        # The required aggregate carries the gate, so a managed head that fails
        # to reproduce its candidate cannot merge.
        @($prValidation['jobs']['pr-validation-success']['needs']) |
            Should -Contain 'gate-completeness-check'

        # Scope is the exact same-repository managed release base and head pair.
        $condition = [string]$step['if']
        foreach ($clause in @(
                "github.event_name == 'pull_request'"
                'github.event.pull_request.head.repo.full_name == github.repository'
                "github.event.pull_request.base.ref == 'release/prerelease'"
                "github.event.pull_request.head.ref == 'release-please--branches--release/prerelease'"
                "github.event.pull_request.base.ref == 'release/stable'"
                "github.event.pull_request.head.ref == 'release-please--branches--release/stable'"
            )) {
            $condition | Should -Match ([regex]::Escape($clause))
        }
        foreach ($widened in @('startsWith(', 'github.head_ref', 'pull_request_target', 'contains(')) {
            $condition | Should -Not -Match ([regex]::Escape($widened))
        }

        [string]$step['env']['PR_NUMBER'] | Should -BeExactly '${{ github.event.pull_request.number }}'
        [string]$step['env']['HEAD_SHA'] | Should -BeExactly '${{ github.event.pull_request.head.sha }}'
        [string]$step['env']['BASE_REF'] | Should -BeExactly '${{ github.event.pull_request.base.ref }}'
        [string]$step['env']['HEAD_REF'] | Should -BeExactly '${{ github.event.pull_request.head.ref }}'

        $run = [string]$step['run']
        foreach ($clause in @(
                # Channel and manifest come from the exact base and head pair.
                "'release/prerelease|release-please--branches--release/prerelease')"
                'CHANNEL=PreRelease'
                'MANIFEST=.release-please-prerelease-manifest.json'
                "'release/stable|release-please--branches--release/stable')"
                'CHANNEL=Stable'
                'MANIFEST=.release-please-manifest.json'
                # The exact event head is fetched, compared, and detached onto.
                '"+refs/pull/$PR_NUMBER/head:refs/remotes/pull/$PR_NUMBER/head"'
                '"+refs/heads/$BASE_REF:refs/remotes/origin/$BASE_REF"'
                'FETCHED_HEAD=$(git rev-parse "refs/remotes/pull/$PR_NUMBER/head")'
                'if [ "$FETCHED_HEAD" != "$HEAD_SHA" ]; then'
                'does not match event head $HEAD_SHA'
                'git checkout --detach --force "$HEAD_SHA"'
                # Canonical version and retained record are read at that head.
                'VERSION=$(jq -r ''.["."] // ""'' "$MANIFEST")'
                'SOURCE_COMMIT=$(jq -r ''.sourceCommit // ""'' .github/plugin/release-candidate.json)'
                '^[0-9a-f]{40}$'
                # The immutable source is fetched and staged outside the tree.
                'git fetch --no-tags --depth 1 origin "$SOURCE_COMMIT"'
                'CANDIDATE_SOURCE_CATALOG="$RUNNER_TEMP/managed-head-candidate-source-marketplace.json"'
                'git show "$SOURCE_COMMIT:.github/plugin/marketplace.json" > "$CANDIDATE_SOURCE_CATALOG"'
                # The baseline comes from the fetched base branch alone, and its
                # locator derivation tolerates a historical string-form source
                # by treating it as naming no ref.
                'BASELINE=$(git show "refs/remotes/origin/$BASE_REF:$MANIFEST" | jq -r ''.["."] // ""'')'
                'git show "refs/remotes/origin/$BASE_REF:.github/plugin/marketplace.json"'
                '(.metadata.version // "") as $version'
                '[.plugins[] | (.version // "")] as $versions'
                'if (.source | type) == "object" then (.source.ref // null) else null end] as $refs'
                '($version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))'
                '($versions | length) > 0'
                '($versions | all(. == $version))'
                'if ($refs | all(. == null))'
                'then "OMITTED"'
                'elif ($refs | all(type == "string" and length > 0))'
                '(($refs | unique) | length) == 1'
                'if [ -z "$BASELINE_TAG" ]'
                'does not carry one uniform baseline locator across a complete catalog at its own metadata version'
                # Verification replays the source, baseline, and both digests.
                'pwsh -NoProfile -File ./scripts/release/Update-VersionFiles.ps1'
                '-Version "$VERSION"'
                '-Channel "$CHANNEL"'
                '-RepoRoot "$PWD"'
                '-CandidateAction Verify'
                '-CandidateSourceCommit "$SOURCE_COMMIT"'
                '-CandidateSourceCatalog "$CANDIDATE_SOURCE_CATALOG"'
                '-BaselineTag "$BASELINE_TAG"'
            )) {
            $run | Should -Match ([regex]::Escape($clause))
        }

        # The base catalog read is the only baseline producer, and the updater
        # consumes it verbatim rather than rebuilding a locator from a version.
        [string[]]@(
            [regex]::Matches($run, '(?m)^\s*BASELINE_TAG=\S*') | ForEach-Object { $_.Value.Trim() }
        ) | Should -Be @('BASELINE_TAG=$(git')
        [string[]]@(
            [regex]::Matches($run, '-BaselineTag\s+\S+') | ForEach-Object { $_.Value }
        ) | Should -Be @('-BaselineTag "$BASELINE_TAG"')

        # The gate proves state; it never repairs, writes, or moves a ref, and
        # it never resolves the head through the moving branch.
        foreach ($forbidden in @(
                'git push'
                'git commit'
                'git add'
                'git tag'
                'git branch'
                'git update-ref'
                'git reset'
                'git merge'
                'gh pr'
                'gh release'
                '-CandidateAction Record'
                '-CandidateAction Apply'
                'refs/heads/$HEAD_REF'
                'origin/$HEAD_REF'
                'BASELINE_TAG="'
                'jq -r --arg version "$BASELINE"'
                'select((.version // "") == $version)'
                '| (.source.ref // null)] as $refs'
            )) {
            $run | Should -Not -Match ([regex]::Escape($forbidden))
        }
    }

    It 'Requires complete canonical release evidence in every catalog consumer' {
        $consumers = @(
            @{
                Document = $script:PrepareDocument
                Job = 'prepare-promotion'
                Step = 'Resolve promotion state'
            }
            @{
                Document = $script:PublishDocument
                Job = 'validate-trigger'
                Step = 'Validate selected promotion source and intent'
            }
        )

        foreach ($consumer in $consumers) {
            $step = Get-NamedJobStep -Document $consumer.Document -JobName $consumer.Job -StepName $consumer.Step
            $run = [string]$step['run']
            foreach ($pattern in @(
                    'hve-core/plugin-release-evidence/v2'
                    '\.sourceCommit == \$source_commit'
                    '\.version == \$version'
                    '\.locator\.ref == \("prerelease-v" \+ \$version\)'
                    '\.packageCount \| type == "number"'
                    '\.packages \| type == "array"'
                    '\.digest \| type == "string"'
                    'gh release download'
                    'plugin-release-evidence\.json'
                )) {
                $run | Should -Match $pattern
            }
            # Only the projected package path clause is dropped; the evidence
            # addresses the repository at its release tag instead.
            $run | Should -Not -Match 'locator\.path'
        }

        $stableState = Get-NamedJobStep -Document $script:PrepareDocument -JobName 'prepare-promotion' -StepName 'Resolve promotion state'
        [string]$stableState['env']['REPOSITORY'] | Should -BeExactly '${{ github.repository }}'
        [string]$stableState['run'] | Should -Match ([regex]::Escape('--arg repository "$REPOSITORY"'))
    }
}

Describe 'Release and installation documentation contracts' -Tag 'Unit' {
    BeforeAll {
        $script:ReleaseDocumentationPaths = @(
            '.github/workflows/README.md'
            'extension/PACKAGING.md'
            'docs/architecture/workflows.md'
            'docs/contributing/release-process.md'
        )
        $script:ReleaseDocumentation = @{}
        foreach ($relativePath in $script:ReleaseDocumentationPaths) {
            $script:ReleaseDocumentation[$relativePath] = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot $relativePath) -Raw -Encoding utf8
        }
    }

    It 'Derives documented Stable workflow job names from parsed YAML' {
        $readme = $script:ReleaseDocumentation['.github/workflows/README.md']
        foreach ($workflow in @('release-stable.yml', 'release-stable-publish.yml')) {
            $match = [regex]::Match($readme, "(?m)^$([regex]::Escape($workflow)) jobs: (?<jobs>[^\r\n]+)$")
            $match.Success | Should -BeTrue -Because "$workflow must have one enumerated job contract"
            $document = Get-WorkflowDocument -Name $workflow
            $documented = [string[]]@($match.Groups['jobs'].Value.Split(',') | ForEach-Object { $_.Trim() } | Sort-Object)
            $expected = [string[]]@($document['jobs'].Keys | Sort-Object)
            $documented | Should -Be $expected
        }
    }

    It 'Contains no hand-maintained numeric job totals or stale Stable workflow ownership' {
        foreach ($relativePath in $script:ReleaseDocumentationPaths) {
            $text = $script:ReleaseDocumentation[$relativePath]
            $text | Should -Not -Match '(?i)\b\d+\s+(?:parallel\s+)?jobs?\b' -Because "$relativePath must not maintain workflow job totals"
            $text | Should -Match 'release-stable\.yml' -Because "$relativePath must name the Stable promotion workflow"
            $text | Should -Match 'release/prerelease' -Because "$relativePath must name the Stable promotion source"
            $text | Should -Match 'release/stable' -Because "$relativePath must name the Stable promotion target"
            $text | Should -Match 'release-stable-publish\.yml' -Because "$relativePath must name Stable release-please orchestration"
            $text | Should -Match '(?i)release-please' -Because "$relativePath must name the release authority"
            $text | Should -Match '(?i)draft' -Because "$relativePath must describe the reviewed draft boundary"
            $text | Should -Match '(?i)main' -Because "$relativePath must describe the moving main catalog"
        }
    }

    # Retirement vocabulary is asserted without naming a retired tag namespace,
    # so the contract survives the channel-vocabulary rewrite while still
    # requiring prospective-only retirement and immutable history.
    It 'Requires canonical evidence, signed release assets, and retirement vocabulary' {
        foreach ($relativePath in $script:ReleaseDocumentationPaths) {
            $text = $script:ReleaseDocumentation[$relativePath]
            $text | Should -Match 'plugin-release-evidence\.json' -Because "$relativePath must document canonical release evidence on the release"
            $text | Should -Match '(?is)signed\s+plugin ZIPs?' -Because "$relativePath must keep signed plugin ZIPs as release deliverables"
            foreach ($asset in @('SBOM', 'Sigstore', 'in-toto')) {
                $text | Should -Match ([regex]::Escape($asset)) -Because "$relativePath must keep $asset assets as release deliverables"
            }
            $text | Should -Match '(?is)snapshot publication has stopped' -Because "$relativePath must state prospective-only snapshot retirement"
            $text | Should -Match '(?is)tags\s+and\s+catalogs\s+remain\s+immutable\s+and\s+supported' -Because "$relativePath must keep legacy release tags and catalogs supported"
        }
    }

    # The policy paragraph is wrapped prose, so each contract is matched as a
    # durable whitespace-tolerant fragment rather than a whole-paragraph string.
    It 'Documents best-effort Marketplace publication recovery' {
        $readme = $script:ReleaseDocumentation['.github/workflows/README.md']
        foreach ($fragment in @(
                'no-environment\s+gate\s+validates\s+matrix\s+structure'
                'package-ID\s+grammar\s+and\s+uniqueness'
                'minor-version\s+parity'
                'before\s+any\s+Marketplace\s+environment\s+is\s+activated'
                'intentionally\s+best-effort\s+and\s+non-atomic'
                '`fail-fast:\s+false`'
                'inspect\s+every\s+matrix\s+leg\s+and\s+reconcile\s+or\s+republish'
                'neither\s+transactionality\s+nor\s+rollback'
                'Republication\s+is\s+supported\s+only\s+for\s+reviewed\s+channel\s+tags'
            )) {
            $readme | Should -Match "(?is)$fragment" -Because 'the workflow guide owns Marketplace partial-failure recovery policy'
        }
    }

    It 'States ref-less main refresh behavior and the main versus release attestation posture' {
        foreach ($relativePath in $script:ReleaseDocumentationPaths) {
            $text = $script:ReleaseDocumentation[$relativePath]
            $text | Should -Match '(?is)ref-less main catalog' -Because "$relativePath must name the ref-less main catalog"
            $text | Should -Match '(?is)(?:marketplace refresh|refreshes the marketplace)' -Because "$relativePath must require an explicit marketplace refresh instead of automatic main updates"
            $text | Should -Match '(?is)(?:plugin update|updates the plugin)' -Because "$relativePath must require an explicit plugin update instead of automatic main updates"
            $text | Should -Match '(?is)(?:without a|no)\s+release gate,\s+SBOM,\s+or\s+attestation' -Because "$relativePath must state that main bytes carry no release gate, SBOM, or attestation"
            $text | Should -Match '(?is)release-gated[^.]{0,120}SBOM-covered[^.]{0,120}attested' -Because "$relativePath must state that release channels remain gated and attested"
        }
    }

    It 'References only workflow files that exist' {
        foreach ($relativePath in $script:ReleaseDocumentationPaths) {
            $text = $script:ReleaseDocumentation[$relativePath]
            $workflowNames = @([regex]::Matches($text, '`(?<name>[a-z0-9-]+\.yml)`') | ForEach-Object { $_.Groups['name'].Value } | Sort-Object -Unique)
            foreach ($workflowName in $workflowNames) {
                Test-Path -LiteralPath (Join-Path $script:WorkflowDirectory $workflowName) -PathType Leaf |
                    Should -BeTrue -Because "$relativePath documents $workflowName"
            }
        }
    }

    It 'Treats capability groups as discovery aids rather than installable collections' {
        $rolePaths = @(
            'business-program-manager.md'
            'data-scientist.md'
            'security-architect.md'
            'sre-operations.md'
            'tech-lead.md'
            'tpm.md'
            'ux-designer.md'
        )
        $roleDirectory = Join-Path $script:RepositoryRoot 'docs/hve-guide/roles'
        foreach ($rolePath in $rolePaths) {
            $text = Get-Content -LiteralPath (Join-Path $roleDirectory $rolePath) -Raw -Encoding utf8
            $text | Should -Not -Match '(?im)^## Recommended Collections$'
            $text | Should -Not -Match '(?i)\bprimary collections?\b'
            $text | Should -Match '(?im)^## Capability Groups$'
            $text | Should -Match '(?i)selective clone'
        }
        $utility = Get-Content -LiteralPath (Join-Path $roleDirectory 'utility.md') -Raw -Encoding utf8
        $utility | Should -Not -Match '(?i)collection installation'
    }

    It 'Parses selective clone as the final install keyword' {
        $installPath = Join-Path $script:RepositoryRoot 'docs/getting-started/install.md'
        $installText = Get-Content -LiteralPath $installPath -Raw -Encoding utf8
        $match = [regex]::Match($installText, '(?s)\A---\r?\n(?<yaml>.*?)\r?\n---')
        $match.Success | Should -BeTrue
        $frontmatter = ConvertFrom-Yaml -Yaml $match.Groups['yaml'].Value
        $keywords = @($frontmatter['keywords'])
        $keywords[-1] | Should -BeExactly 'selective clone'
    }
}

Describe 'Catalog release ref and plugin locator consistency' -Tag 'Unit' {
    BeforeAll {
        $script:Catalog = Get-Content -LiteralPath $script:CatalogPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
        $script:Template = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'extension/templates/package.template.json') -Raw -Encoding utf8 | ConvertFrom-Json
        $script:Lock = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'package-lock.json') -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
    }

    It 'Agrees on one committed shared version without requiring a channel manifest on main' {
        $version = [string]$script:RootManifest.version
        $version | Should -Not -BeNullOrEmpty
        [string]$script:Template.version | Should -BeExactly $version
        [string]$script:Lock['version'] | Should -BeExactly $version
        [string]$script:Lock['packages']['']['version'] | Should -BeExactly $version
        [string]$script:Catalog['metadata']['version'] | Should -BeExactly $version
    }

    It 'Binds each release workflow to its own channel manifest while main skips manifests' {
        $preRelease = Get-WorkflowDocument -Name 'release-prerelease.yml'
        $preReleaseState = [string](Get-NamedJobStep -Document $preRelease -JobName 'validate-release' -StepName 'Verify committed pre-release state')['run']
        $preReleaseState | Should -Match '\.release-please-prerelease-manifest\.json'
        $preReleaseState | Should -Not -Match '"\.release-please-manifest\.json'
        $preReleaseState | Should -Match '\.source\.ref == \("prerelease-v" \+ \$version\)'

        $preReleaseSync = [string](Get-NamedJobStep -Document $preRelease -JobName 'sync-release-pr' -StepName 'Update committed version fields and retire the promotion intent')['run']
        $preReleaseSync | Should -Match '-Channel PreRelease'
        $preReleaseSync | Should -Match '-CandidateAction Apply'

        $stable = Get-WorkflowDocument -Name 'release-stable-publish.yml'
        $stableState = [string](Get-NamedJobStep -Document $stable -JobName 'validate-release' -StepName 'Verify release version and committed state')['run']
        $stableState | Should -Match '"\.release-please-manifest\.json'
        $stableState | Should -Not -Match 'release-please-prerelease-manifest\.json'
        $stableState | Should -Match '\.source\.ref == \("v" \+ \$version\)'
        $stableSync = [string](Get-NamedJobStep -Document $stable -JobName 'sync-release-pr' -StepName 'Update committed version fields and retire the promotion intent')['run']
        $stableSync | Should -Match '-Channel Stable'
        $stableSync | Should -Match '-CandidateAction Apply'
        # Final publication is an independent boundary: it rejects an odd minor
        # even though preparation already resolved an even one.
        $stableState | Should -Match 'MINOR % 2 != 0'
        $stableState | Should -Match 'has an odd minor'

        $pluginPackage = Get-WorkflowText -Name 'plugin-package.yml'
        $pluginPackage | Should -Match ([regex]::Escape('$entry[''source''][''ref''] -cne $env:RELEASE_TAG'))
    }

    # The committed catalog is the main channel. Release workflows add exact
    # refs to branch-owned catalog state before packaging or publication.
    It 'Keeps the committed main catalog canonical and ref-less' {
        $version = [string]$script:RootManifest.version
        @($script:Catalog['plugins']).Count | Should -BeGreaterThan 0
        foreach ($entry in @($script:Catalog['plugins'])) {
            [string]$entry['version'] | Should -BeExactly $version
            [string]$entry['source']['path'] | Should -BeExactly '.github'
            $entry['source'].Contains('ref') | Should -BeFalse
            $entry['source'].Contains('sha') | Should -BeFalse
        }
    }

    It 'Keeps main as a numeric moving catalog rather than a Stable release baseline' {
        $version = [string]$script:RootManifest.version
        $version | Should -Match '^\d+\.\d+\.\d+$'
        [string]$script:Catalog['metadata']['version'] | Should -BeExactly $version
    }
}
