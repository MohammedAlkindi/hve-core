#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
    Validates the ADR consistency rule registry against its JSON schema.

.DESCRIPTION
    adr-consistency-rules.schema.json previously reached the registry only
    through a schema-mapping.json entry that could never fire, because
    Validate-MarkdownFrontmatter.ps1 enumerates '*.md' exclusively. This suite
    is the enforcement path that entry implied.
#>

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
    $script:rulesPath = Join-Path $script:repoRoot 'scripts/linting/rules/adr-consistency-rules.json'
    $script:schemaPath = Join-Path $script:repoRoot 'scripts/linting/schemas/adr-consistency-rules.schema.json'

    $script:rulesJson = Get-Content -Path $script:rulesPath -Raw
    $script:schemaJson = Get-Content -Path $script:schemaPath -Raw
    $script:rules = ($script:rulesJson | ConvertFrom-Json).rules
}

Describe 'adr-consistency-rules.json conforms to adr-consistency-rules.schema.json' -Tag 'Unit' {
    It 'Schema file parses as JSON' {
        { $script:schemaJson | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'Rule registry parses as JSON' {
        { $script:rulesJson | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'Rule registry validates against the schema' {
        $result = Test-Json -Json $script:rulesJson -Schema $script:schemaJson -ErrorAction SilentlyContinue -ErrorVariable testErrors
        if (-not $result) {
            $detail = ($testErrors | ForEach-Object { $_.ToString() }) -join '; '
            throw "adr-consistency-rules.json failed schema validation: $detail"
        }
        $result | Should -BeTrue
    }
}

Describe 'adr-consistency-rules.json invariants the schema cannot express' -Tag 'Unit' {
    BeforeAll {
        $modulePath = Join-Path $script:repoRoot 'scripts/linting/Modules/AdrConsistency.psm1'
        $module = Import-Module $modulePath -Force -PassThru

        # Rule functions stay module-private, so resolve them inside module scope.
        $script:moduleFunctions = & $module {
            (Get-Command -CommandType Function -Name 'Test-*').Name
        }
    }

    It 'Dispatches every check to a rule function defined in AdrConsistency.psm1' {
        foreach ($rule in $script:rules) {
            $pascal = ($rule.check -split '-' | ForEach-Object {
                    $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1)
                }) -join ''
            $expected = "Test-$pascal"
            $script:moduleFunctions | Should -Contain $expected -Because "$($rule.id) declares check '$($rule.check)'"
        }
    }

    It 'Declares each rule id exactly once' {
        $duplicates = @($script:rules.id | Group-Object | Where-Object { $_.Count -gt 1 })
        $duplicates.Count | Should -Be 0 -Because "duplicate ids make findings ambiguous: $($duplicates.Name -join ', ')"
    }
}
