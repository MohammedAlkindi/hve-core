#Requires -Modules Pester
# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT

# Agent Plugins v1.0.0 conformance coverage for the strict skills package.
# Each rule from the published specification (https://agent-plugins.org/specification)
# is restated as an executable check. The version is pinned in code: nothing is
# fetched at runtime and no upstream schema document is vendored.

BeforeDiscovery {
    $script:StrictPackageRoot = Join-Path (Resolve-Path "$PSScriptRoot/../../..").Path 'plugins/hve-core-skills'
    $script:StrictPackagePresent = Test-Path -LiteralPath $script:StrictPackageRoot -PathType Container
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../plugins/Modules/PluginHelpers.psm1') -Force

    $script:RepoRoot = (Resolve-Path "$PSScriptRoot/../../..").Path
    $script:CanonicalSchema = 'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json'

    function New-StrictFixturePackage {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Parent,

            [Parameter(Mandatory = $false)]
            [string]$PackageName = 'fixture-skills'
        )

        $root = Join-Path $Parent $PackageName
        $skillDir = Join-Path $root 'skills/alpha'
        New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $skillDir 'SKILL.md') `
            -Value "---`nname: alpha`ndescription: Alpha skill`n---`n"

        $manifest = New-StrictPluginManifestContent -PackageName $PackageName -Version '1.0.0' `
            -Description 'Fixture package' -AuthorName 'Microsoft' -License 'MIT' `
            -Homepage 'https://example.invalid' -Repository 'https://example.invalid' `
            -Keywords @('one', 'two')
        Set-Content -LiteralPath (Join-Path $root 'plugin.json') -Value ($manifest | ConvertTo-Json -Depth 10)

        return $root
    }

    function Get-FixtureManifest {
        param([Parameter(Mandatory = $true)][string]$Root)
        return (Get-Content -LiteralPath (Join-Path $Root 'plugin.json') -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable)
    }

    function Set-FixtureManifest {
        param(
            [Parameter(Mandatory = $true)][string]$Root,
            [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Manifest
        )
        Set-Content -LiteralPath (Join-Path $Root 'plugin.json') -Value ($Manifest | ConvertTo-Json -Depth 10)
    }
}

Describe 'Strict manifest generation' {
    It 'Declares the canonical schema identifier' {
        $manifest = New-StrictPluginManifestContent -PackageName 'hve-core-skills' -Version '1.0.0'
        $manifest['$schema'] | Should -Be $script:CanonicalSchema
    }

    It 'Emits only permitted top-level fields' {
        $manifest = New-StrictPluginManifestContent -PackageName 'hve-core-skills' -Version '1.0.0' `
            -Description 'd' -AuthorName 'Microsoft' -Homepage 'https://example.invalid' `
            -Repository 'https://example.invalid' -License 'MIT' -Keywords @('a')
        $permitted = Get-AgentPluginManifestField
        foreach ($key in $manifest.Keys) {
            $permitted | Should -Contain $key
        }
    }

    It 'Carries no Copilot component array' {
        $manifest = New-StrictPluginManifestContent -PackageName 'hve-core-skills' -Version '1.0.0'
        foreach ($field in @('agents', 'commands', 'rules', 'skills', 'hooks', 'x-hve')) {
            $manifest.Contains($field) | Should -BeFalse
        }
    }

    It 'Projects a catalog author string onto the author object' {
        $manifest = New-StrictPluginManifestContent -PackageName 'hve-core-skills' -Version '1.0.0' -AuthorName 'Microsoft'
        $manifest['author'] | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
        $manifest['author']['name'] | Should -Be 'Microsoft'
    }

    It 'Omits optional metadata instead of emitting empty values' {
        $manifest = New-StrictPluginManifestContent -PackageName 'hve-core-skills' -Version '1.0.0'
        foreach ($field in @('description', 'author', 'homepage', 'repository', 'license', 'keywords')) {
            $manifest.Contains($field) | Should -BeFalse
        }
    }

    It 'Refuses to generate a manifest with an invalid name' {
        { New-StrictPluginManifestContent -PackageName 'Invalid-Name' -Version '1.0.0' } |
            Should -Throw '*lowercase*'
    }
}

Describe 'Plugin name constraints' {
    It 'Accepts a conformant name' -ForEach @('a', 'my-plugin', 'acme.tools', 'lint3r', 'hve-core-skills') {
        @(Test-AgentPluginName -Name $_) | Should -BeNullOrEmpty
    }

    It 'Rejects an empty name for its length' {
        @(Test-AgentPluginName -Name '') -join '; ' | Should -BeLike '*1 to 64 characters*'
    }

    It 'Rejects a name longer than the upper length bound' {
        @(Test-AgentPluginName -Name ('a' * 65)) -join '; ' | Should -BeLike '*1 to 64 characters*'
    }

    It 'Accepts a name at the upper length bound' {
        @(Test-AgentPluginName -Name ('a' * 64)) | Should -BeNullOrEmpty
    }

    It 'Rejects a character outside the permitted set' -ForEach @('My-Plugin', 'has_underscore', 'has space', 'sla/sh') {
        @(Test-AgentPluginName -Name $_) -join '; ' | Should -BeLike '*lowercase letters, digits, hyphens, and periods*'
    }

    It 'Rejects a non-alphanumeric boundary character' -ForEach @('-start', 'end-', '.start', 'end.') {
        @(Test-AgentPluginName -Name $_) -join '; ' | Should -BeLike '*start and end with an alphanumeric*'
    }

    It 'Rejects consecutive hyphens or periods' -ForEach @('has--double', 'too.many..dots') {
        @(Test-AgentPluginName -Name $_) -join '; ' | Should -BeLike '*consecutive hyphens or periods*'
    }
}

Describe 'Strict manifest contract' {
    It 'Accepts a conformant manifest' {
        $manifest = New-StrictPluginManifestContent -PackageName 'fixture-skills' -Version '1.0.0' `
            -Description 'd' -AuthorName 'Microsoft' -Homepage 'https://example.invalid' `
            -Repository 'https://example.invalid' -License 'MIT' -Keywords @('a', 'b')
        @(Test-StrictPluginManifest -Manifest $manifest) | Should -BeNullOrEmpty
    }

    It 'Rejects a non-object manifest' {
        @(Test-StrictPluginManifest -Manifest 'not-an-object') -join '; ' | Should -BeLike '*top-level JSON object*'
    }

    It 'Rejects a missing schema identifier' {
        $manifest = [ordered]@{ name = 'fixture-skills' }
        @(Test-StrictPluginManifest -Manifest $manifest) -join '; ' | Should -BeLike "*'`$schema' is missing*"
    }

    It 'Rejects a non-canonical schema identifier' {
        $manifest = [ordered]@{ '$schema' = 'https://example.invalid/plugin.schema.json'; name = 'fixture-skills' }
        @(Test-StrictPluginManifest -Manifest $manifest) -join '; ' | Should -BeLike '*canonical identifier*'
    }

    It 'Rejects a missing name' {
        $manifest = [ordered]@{ '$schema' = $script:CanonicalSchema }
        @(Test-StrictPluginManifest -Manifest $manifest) -join '; ' | Should -BeLike "*'name' is missing*"
    }

    It 'Rejects a non-string name' {
        $manifest = [ordered]@{ '$schema' = $script:CanonicalSchema; name = 42 }
        @(Test-StrictPluginManifest -Manifest $manifest) -join '; ' | Should -BeLike "*'name' must be a string*"
    }

    It 'Rejects a non-string metadata field' -ForEach @('version', 'description', 'homepage', 'repository', 'license') {
        $manifest = [ordered]@{ '$schema' = $script:CanonicalSchema; name = 'fixture-skills' }
        $manifest[$_] = 42
        @(Test-StrictPluginManifest -Manifest $manifest) -join '; ' | Should -BeLike "*'$_' must be a string*"
    }

    It 'Accepts a closed author object with string members' {
        $manifest = [ordered]@{
            '$schema' = $script:CanonicalSchema
            name      = 'fixture-skills'
            author    = [ordered]@{ name = 'Microsoft'; email = 'a@example.invalid'; url = 'https://example.invalid' }
        }
        @(Test-StrictPluginManifest -Manifest $manifest) | Should -BeNullOrEmpty
    }

    It 'Rejects a non-object author' {
        $manifest = [ordered]@{ '$schema' = $script:CanonicalSchema; name = 'fixture-skills'; author = 'Microsoft' }
        @(Test-StrictPluginManifest -Manifest $manifest) -join '; ' | Should -BeLike "*'author' must be an object*"
    }

    It 'Rejects an author member outside the closed set' {
        $manifest = [ordered]@{
            '$schema' = $script:CanonicalSchema
            name      = 'fixture-skills'
            author    = [ordered]@{ name = 'Microsoft'; org = 'Contoso' }
        }
        @(Test-StrictPluginManifest -Manifest $manifest) -join '; ' | Should -BeLike "*author member 'org' is not permitted*"
    }

    It 'Rejects a non-string author member' {
        $manifest = [ordered]@{
            '$schema' = $script:CanonicalSchema
            name      = 'fixture-skills'
            author    = [ordered]@{ name = 42 }
        }
        @(Test-StrictPluginManifest -Manifest $manifest) -join '; ' | Should -BeLike "*author member 'name' must be a string*"
    }

    It 'Rejects keywords that are not an array' {
        $manifest = [ordered]@{ '$schema' = $script:CanonicalSchema; name = 'fixture-skills'; keywords = 'one' }
        @(Test-StrictPluginManifest -Manifest $manifest) -join '; ' | Should -BeLike "*'keywords' must be an array of strings*"
    }

    It 'Rejects a non-string keyword item' {
        $manifest = [ordered]@{ '$schema' = $script:CanonicalSchema; name = 'fixture-skills'; keywords = @('one', 2) }
        @(Test-StrictPluginManifest -Manifest $manifest) -join '; ' | Should -BeLike "*'keywords' must contain only strings*"
    }

    It 'Accepts object-valued extension namespaces' {
        $manifest = [ordered]@{
            '$schema'  = $script:CanonicalSchema
            name       = 'fixture-skills'
            extensions = [ordered]@{ 'com.example.client' = [ordered]@{ setting = $true } }
        }
        @(Test-StrictPluginManifest -Manifest $manifest) | Should -BeNullOrEmpty
    }

    It 'Rejects a non-object extensions field' {
        $manifest = [ordered]@{ '$schema' = $script:CanonicalSchema; name = 'fixture-skills'; extensions = 'nope' }
        @(Test-StrictPluginManifest -Manifest $manifest) -join '; ' | Should -BeLike "*'extensions' must be an object*"
    }

    It 'Rejects a non-object extension namespace value' {
        $manifest = [ordered]@{
            '$schema'  = $script:CanonicalSchema
            name       = 'fixture-skills'
            extensions = [ordered]@{ 'com.example.client' = 'nope' }
        }
        @(Test-StrictPluginManifest -Manifest $manifest) -join '; ' | Should -BeLike "*must map to an object*"
    }

    It 'Rejects an unknown top-level field' {
        $manifest = [ordered]@{ '$schema' = $script:CanonicalSchema; name = 'fixture-skills'; agents = @('agents/') }
        @(Test-StrictPluginManifest -Manifest $manifest) -join '; ' | Should -BeLike "*unknown top-level field 'agents'*"
    }
}

Describe 'Strict package contract' {
    BeforeEach {
        $script:fixtureParent = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:fixtureParent -Force | Out-Null
        $script:fixture = New-StrictFixturePackage -Parent $script:fixtureParent
    }

    It 'Accepts a conformant package' {
        @(Test-StrictPluginPackage -PackageRoot $script:fixture) | Should -BeNullOrEmpty
    }

    It 'Treats an absent mcp.json as valid' {
        Test-Path (Join-Path $script:fixture 'mcp.json') | Should -BeFalse
        @(Test-StrictPluginPackage -PackageRoot $script:fixture) | Should -BeNullOrEmpty
    }

    It 'Rejects an mcp.json that is not a regular file' {
        New-Item -ItemType Directory -Path (Join-Path $script:fixture 'mcp.json') -Force | Out-Null
        @(Test-StrictPluginPackage -PackageRoot $script:fixture) -join '; ' | Should -BeLike '*mcp.json*regular file*'
    }

    It 'Rejects a missing root manifest' {
        Remove-Item -LiteralPath (Join-Path $script:fixture 'plugin.json') -Force
        @(Test-StrictPluginPackage -PackageRoot $script:fixture) -join '; ' | Should -BeLike '*plugin.json is missing from the package root*'
    }

    It 'Rejects an alternate manifest beside the root manifest' {
        $alternate = Join-Path $script:fixture '.github/plugin'
        New-Item -ItemType Directory -Path $alternate -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:fixture 'plugin.json') -Destination (Join-Path $alternate 'plugin.json')
        @(Test-StrictPluginPackage -PackageRoot $script:fixture) -join '; ' | Should -BeLike '*alternate manifest*'
    }

    It 'Rejects a manifest name that does not match the package directory' {
        $manifest = Get-FixtureManifest -Root $script:fixture
        $manifest['name'] = 'other-name'
        Set-FixtureManifest -Root $script:fixture -Manifest $manifest
        @(Test-StrictPluginPackage -PackageRoot $script:fixture) -join '; ' | Should -BeLike '*does not match the package directory name*'
    }

    It 'Rejects invalid manifest JSON' {
        Set-Content -LiteralPath (Join-Path $script:fixture 'plugin.json') -Value '{ not json'
        @(Test-StrictPluginPackage -PackageRoot $script:fixture) -join '; ' | Should -BeLike '*not valid JSON*'
    }

    It 'Rejects an immediate child of skills/ without SKILL.md' {
        New-Item -ItemType Directory -Path (Join-Path $script:fixture 'skills/empty') -Force | Out-Null
        @(Test-StrictPluginPackage -PackageRoot $script:fixture) -join '; ' | Should -BeLike '*has no SKILL.md*'
    }

    It 'Rejects a file placed directly under skills/' {
        Set-Content -LiteralPath (Join-Path $script:fixture 'skills/stray.md') -Value 'stray'
        @(Test-StrictPluginPackage -PackageRoot $script:fixture) -join '; ' | Should -BeLike '*is not a skill directory beneath skills/*'
    }

    It 'Rejects a skills location that is not a directory' {
        Remove-Item -LiteralPath (Join-Path $script:fixture 'skills') -Recurse -Force
        Set-Content -LiteralPath (Join-Path $script:fixture 'skills') -Value 'not a directory'
        @(Test-StrictPluginPackage -PackageRoot $script:fixture) -join '; ' | Should -BeLike '*skills is present but does not resolve to a directory*'
    }

    It 'Rejects a nested skill below the immediate children of skills/' {
        $nested = Join-Path $script:fixture 'skills/alpha/inner'
        New-Item -ItemType Directory -Path $nested -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $nested 'SKILL.md') -Value "---`nname: inner`ndescription: Inner`n---`n"
        @(Test-StrictPluginPackage -PackageRoot $script:fixture) -join '; ' | Should -BeLike '*nested skill*below the immediate children*'
    }

    It 'Rejects a skill whose declared name differs from its directory' {
        Set-Content -LiteralPath (Join-Path $script:fixture 'skills/alpha/SKILL.md') `
            -Value "---`nname: beta`ndescription: Alpha skill`n---`n"
        @(Test-StrictPluginPackage -PackageRoot $script:fixture) -join '; ' | Should -BeLike "*declares name 'beta' that does not match its directory name*"
    }

    It 'Rejects a skill with no declared name' {
        Set-Content -LiteralPath (Join-Path $script:fixture 'skills/alpha/SKILL.md') `
            -Value "---`ndescription: Alpha skill`n---`n"
        @(Test-StrictPluginPackage -PackageRoot $script:fixture) -join '; ' | Should -BeLike '*does not declare a name in SKILL.md*'
    }

    It 'Rejects a skill with no declared description' {
        Set-Content -LiteralPath (Join-Path $script:fixture 'skills/alpha/SKILL.md') `
            -Value "---`nname: alpha`n---`n"
        @(Test-StrictPluginPackage -PackageRoot $script:fixture) -join '; ' | Should -BeLike '*does not declare a description in SKILL.md*'
    }

    It 'Rejects a package path that escapes the package root' {
        $outside = Join-Path $script:fixtureParent 'outside'
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $outside 'escaped.md') -Value 'escaped'

        try {
            New-Item -ItemType SymbolicLink -Path (Join-Path $script:fixture 'skills/alpha/escape.md') -Target (Join-Path $outside 'escaped.md') -ErrorAction Stop | Out-Null
        }
        catch {
            Set-ItResult -Skipped -Because 'the filesystem does not permit symbolic link creation'
            return
        }

        @(Test-StrictPluginPackage -PackageRoot $script:fixture) -join '; ' | Should -BeLike '*resolves outside the package root*'
    }

    It 'Reports a missing package root' {
        @(Test-StrictPluginPackage -PackageRoot (Join-Path $TestDrive 'no-such-package')) -join '; ' |
            Should -BeLike '*is not a directory*'
    }
}

Describe 'Generated hve-core-skills package' -Skip:(-not $script:StrictPackagePresent) {
    BeforeAll {
        $script:generatedRoot = Join-Path $script:RepoRoot 'plugins/hve-core-skills'
        $script:catalog = Get-MarketplaceCatalog -Path (Join-Path $script:RepoRoot '.github/plugin/marketplace.json')

        # Expected membership is derived here from the catalog and the source
        # SKILL.md files, independently of the generator projection it checks.
        $expected = @{}
        foreach ($entry in @($script:catalog['plugins'])) {
            $overlay = if ($entry.Contains('x-hve') -and $entry['x-hve'] -is [System.Collections.IDictionary]) { $entry['x-hve'] } else { @{} }
            if ($overlay.Contains('derived')) { continue }
            if ($overlay.Contains('maturity') -and [string]$overlay['maturity'] -in @('deprecated', 'removed')) { continue }

            $componentMaturity = if ($overlay.Contains('componentMaturity') -and $overlay['componentMaturity'] -is [System.Collections.IDictionary]) {
                $overlay['componentMaturity']
            }
            else { @{} }

            foreach ($declared in @($entry['skills'])) {
                if ([string]::IsNullOrWhiteSpace([string]$declared)) { continue }
                $maturity = if ($componentMaturity.Contains([string]$declared)) { [string]$componentMaturity[[string]$declared] } else { 'stable' }
                if ($maturity -notin @('stable', 'preview', 'experimental')) { continue }

                $sourcePath = '.github/skills/' + ([string]$declared).Substring('skills/'.Length)
                $skillFile = Join-Path $script:RepoRoot ($sourcePath + '/SKILL.md')
                $name = ''
                $inFrontmatter = $false
                foreach ($line in (Get-Content -LiteralPath $skillFile -Encoding utf8)) {
                    if ($line -eq '---') {
                        if ($inFrontmatter) { break }
                        $inFrontmatter = $true
                        continue
                    }
                    if ($inFrontmatter -and $line -match '^name:\s*(.+?)\s*$') {
                        $name = $Matches[1].Trim('"', "'")
                        break
                    }
                }
                $expected[$name] = $sourcePath
            }
        }

        $script:expectedNames = [string[]]@($expected.Keys)
        [array]::Sort($script:expectedNames, [System.StringComparer]::Ordinal)

        $script:actualNames = [string[]]@(Get-ChildItem -LiteralPath (Join-Path $script:generatedRoot 'skills') -Directory -Force | ForEach-Object { $_.Name })
        [array]::Sort($script:actualNames, [System.StringComparer]::Ordinal)
    }

    It 'Matches the independently derived skill name set' {
        $script:expectedNames.Count | Should -BeGreaterThan 0
        $script:actualNames | Should -Be $script:expectedNames
    }

    It 'Matches the independently derived membership digest' {
        $toDigest = {
            param($names)
            $manifest = ($names -join "`n") + "`n"
            [System.Convert]::ToHexString(
                [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($manifest))
            ).ToLowerInvariant()
        }
        (& $toDigest $script:actualNames) | Should -Be (& $toDigest $script:expectedNames)
    }

    It 'Passes the complete package conformance contract' {
        @(Test-StrictPluginPackage -PackageRoot $script:generatedRoot) | Should -BeNullOrEmpty
    }

    It 'Contains only the manifest, the README, and the skills tree' {
        $rootEntries = @(Get-ChildItem -LiteralPath $script:generatedRoot -Force | ForEach-Object { $_.Name })
        [array]::Sort($rootEntries, [System.StringComparer]::Ordinal)
        $rootEntries | Should -Be @('README.md', 'plugin.json', 'skills')
    }

    It 'Contains no symbolic link' {
        @(Get-ChildItem -LiteralPath $script:generatedRoot -Recurse -Force | Where-Object { $_.LinkType }).Count | Should -Be 0
    }
}
