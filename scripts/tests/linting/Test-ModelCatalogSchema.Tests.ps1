#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
    Validates the committed model catalog against its JSON schema.

.DESCRIPTION
    model-catalog.json is hand-maintained between generator runs, and no lint
    stage enforces its schema: Validate-MarkdownFrontmatter.ps1 enumerates only
    '*.md', and Invoke-JsonLint.ps1 checks syntax without schema conformance.
#>

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
    $script:catalogPath = Join-Path $script:repoRoot 'scripts/linting/model-catalog.json'
    $script:schemaPath = Join-Path $script:repoRoot 'scripts/linting/schemas/model-catalog.schema.json'

    $script:catalogJson = Get-Content -Path $script:catalogPath -Raw
    $script:schemaJson = Get-Content -Path $script:schemaPath -Raw
    $script:catalog = $script:catalogJson | ConvertFrom-Json
}

Describe 'model-catalog.json conforms to model-catalog.schema.json' -Tag 'Unit' {
    It 'Schema file parses as JSON' {
        { $script:schemaJson | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'Catalog file parses as JSON' {
        { $script:catalogJson | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'Catalog validates against the schema' {
        $result = Test-Json -Json $script:catalogJson -Schema $script:schemaJson -ErrorAction SilentlyContinue -ErrorVariable testErrors
        if (-not $result) {
            $detail = ($testErrors | ForEach-Object { $_.ToString() }) -join '; '
            throw "model-catalog.json failed schema validation: $detail"
        }
        $result | Should -BeTrue
    }
}

Describe 'model-catalog.json invariants the schema cannot express' -Tag 'Unit' {
    It 'Carries retiredDate on every retiring model and on no other' {
        foreach ($model in $script:catalog.models) {
            $hasRetiredDate = $null -ne $model.PSObject.Properties['retiredDate']
            $isRetiring = $model.status -eq 'retiring'
            $hasRetiredDate | Should -Be $isRetiring -Because "'$($model.name)' has status '$($model.status)'"
        }
    }

    It 'Declares each model name exactly once' {
        $duplicates = @($script:catalog.models.name | Group-Object | Where-Object { $_.Count -gt 1 })
        $duplicates.Count | Should -Be 0 -Because "duplicate names break catalog lookups: $($duplicates.Name -join ', ')"
    }

    It 'Resolves a real provider for every model' {
        $unresolved = @($script:catalog.models | Where-Object { $_.provider -eq 'Unknown' })
        $unresolved.Count | Should -Be 0 -Because "'Unknown' is a generator sentinel, not a provider: $($unresolved.name -join ', ')"
    }
}
