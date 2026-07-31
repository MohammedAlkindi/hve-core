#Requires -Modules Pester
# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT

BeforeAll {
    . $PSScriptRoot/../../plugins/Validate-Marketplace.ps1

    function New-TestPluginSource {
        param(
            [string]$Name,
            [string]$Version = '1.0.0'
        )

        return [ordered]@{
            source = 'github'
            repo   = 'microsoft/hve-core'
            path   = "plugins/$Name"
            ref    = "plugins-v$Version"
        }
    }
}

Describe 'Invoke-MarketplaceValidation - missing manifest' {
    BeforeAll {
        $script:repoRoot = Join-Path $TestDrive 'repo-no-manifest'
        New-Item -ItemType Directory -Path $script:repoRoot -Force | Out-Null
    }

    It 'Returns failure when marketplace.json does not exist' {
        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot
        $result.Success | Should -BeFalse
        $result.ErrorCount | Should -Be 1
    }
}

Describe 'Invoke-MarketplaceValidation - invalid JSON' {
    BeforeAll {
        $script:repoRoot = Join-Path $TestDrive 'repo-bad-json'
        $manifestDir = Join-Path $script:repoRoot '.github/plugin'
        New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
        Set-Content -Path (Join-Path $manifestDir 'marketplace.json') -Value '{ invalid json }'
    }

    It 'Returns failure for malformed JSON' {
        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot
        $result.Success | Should -BeFalse
        $result.ErrorCount | Should -Be 1
    }
}

Describe 'Invoke-MarketplaceValidation - missing required fields' {
    BeforeAll {
        $script:repoRoot = Join-Path $TestDrive 'repo-missing-fields'
        $manifestDir = Join-Path $script:repoRoot '.github/plugin'
        New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
        # Missing 'owner' and 'plugins'
        $json = @{ name = 'test'; metadata = @{ description = 'd'; version = '1.0.0'; pluginRoot = 'plugins' } } | ConvertTo-Json -Depth 5
        Set-Content -Path (Join-Path $manifestDir 'marketplace.json') -Value $json
    }

    It 'Returns errors for missing top-level fields' {
        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot
        $result.Success | Should -BeFalse
        $result.ErrorCount | Should -BeGreaterOrEqual 2
    }
}

Describe 'Invoke-MarketplaceValidation - missing metadata fields' {
    BeforeAll {
        $script:repoRoot = Join-Path $TestDrive 'repo-missing-metadata'
        $manifestDir = Join-Path $script:repoRoot '.github/plugin'
        New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
        $pluginsDir = Join-Path $script:repoRoot 'plugins/my-plugin'
        New-Item -ItemType Directory -Path $pluginsDir -Force | Out-Null
        # metadata missing 'version' and 'pluginRoot'
        $json = @{
            name     = 'test'
            metadata = @{ description = 'd' }
            owner    = @{ name = 'owner' }
            plugins  = @(@{ name = 'my-plugin'; source = (New-TestPluginSource -Name 'my-plugin'); description = 'd'; version = '1.0.0' })
        } | ConvertTo-Json -Depth 5
        Set-Content -Path (Join-Path $manifestDir 'marketplace.json') -Value $json
    }

    It 'Returns errors for missing metadata fields' {
        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot
        $result.Success | Should -BeFalse
        $result.ErrorCount | Should -BeGreaterOrEqual 2
    }
}

Describe 'Invoke-MarketplaceValidation - missing owner name' {
    BeforeAll {
        $script:repoRoot = Join-Path $TestDrive 'repo-missing-owner'
        $manifestDir = Join-Path $script:repoRoot '.github/plugin'
        New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
        $pluginsDir = Join-Path $script:repoRoot 'plugins/my-plugin'
        New-Item -ItemType Directory -Path $pluginsDir -Force | Out-Null
        Set-Content -Path (Join-Path $script:repoRoot 'package.json') -Value '{"version":"1.0.0"}'
        $json = @{
            name     = 'test'
            metadata = @{ description = 'd'; version = '1.0.0'; pluginRoot = 'plugins' }
            owner    = @{}
            plugins  = @(@{ name = 'my-plugin'; source = (New-TestPluginSource -Name 'my-plugin'); description = 'd'; version = '1.0.0' })
        } | ConvertTo-Json -Depth 5
        Set-Content -Path (Join-Path $manifestDir 'marketplace.json') -Value $json
    }

    It 'Returns error for missing owner name' {
        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot
        $result.Success | Should -BeFalse
        $result.ErrorCount | Should -BeGreaterOrEqual 1
    }
}

Describe 'Invoke-MarketplaceValidation - version mismatch' {
    BeforeAll {
        $script:repoRoot = Join-Path $TestDrive 'repo-version-mismatch'
        $manifestDir = Join-Path $script:repoRoot '.github/plugin'
        New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
        $pluginsDir = Join-Path $script:repoRoot 'plugins/my-plugin'
        New-Item -ItemType Directory -Path $pluginsDir -Force | Out-Null
        Set-Content -Path (Join-Path $script:repoRoot 'package.json') -Value '{"version":"2.0.0"}'
        $json = @{
            name     = 'test'
            metadata = @{ description = 'd'; version = '1.0.0'; pluginRoot = 'plugins' }
            owner    = @{ name = 'owner' }
            plugins  = @(@{ name = 'my-plugin'; source = (New-TestPluginSource -Name 'my-plugin'); description = 'd'; version = '1.0.0' })
        } | ConvertTo-Json -Depth 5
        Set-Content -Path (Join-Path $manifestDir 'marketplace.json') -Value $json
    }

    It 'Returns error when metadata version does not match package.json' {
        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot
        $result.Success | Should -BeFalse
        $result.ErrorCount | Should -BeGreaterOrEqual 1
    }
}

Describe 'Invoke-MarketplaceValidation - empty plugins array' {
    BeforeAll {
        $script:repoRoot = Join-Path $TestDrive 'repo-empty-plugins'
        $manifestDir = Join-Path $script:repoRoot '.github/plugin'
        New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
        Set-Content -Path (Join-Path $script:repoRoot 'package.json') -Value '{"version":"1.0.0"}'
        $json = @{
            name     = 'test'
            metadata = @{ description = 'd'; version = '1.0.0'; pluginRoot = 'plugins' }
            owner    = @{ name = 'owner' }
            plugins  = @()
        } | ConvertTo-Json -Depth 5
        Set-Content -Path (Join-Path $manifestDir 'marketplace.json') -Value $json
    }

    It 'Returns error for empty plugins array' {
        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot
        $result.Success | Should -BeFalse
        $result.ErrorCount | Should -BeGreaterOrEqual 1
    }
}

Describe 'Invoke-MarketplaceValidation - duplicate plugin names' {
    BeforeAll {
        $script:repoRoot = Join-Path $TestDrive 'repo-dupes'
        $manifestDir = Join-Path $script:repoRoot '.github/plugin'
        New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:repoRoot 'plugins/my-plugin') -Force | Out-Null
        Set-Content -Path (Join-Path $script:repoRoot 'package.json') -Value '{"version":"1.0.0"}'
        $json = @{
            name     = 'test'
            metadata = @{ description = 'd'; version = '1.0.0'; pluginRoot = 'plugins' }
            owner    = @{ name = 'owner' }
            plugins  = @(
                @{ name = 'my-plugin'; source = (New-TestPluginSource -Name 'my-plugin'); description = 'd1'; version = '1.0.0' }
                @{ name = 'my-plugin'; source = (New-TestPluginSource -Name 'my-plugin'); description = 'd2'; version = '1.0.0' }
            )
        } | ConvertTo-Json -Depth 5
        Set-Content -Path (Join-Path $manifestDir 'marketplace.json') -Value $json
    }

    It 'Returns error for duplicate plugin names' {
        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot
        $result.Success | Should -BeFalse
        $result.ErrorCount | Should -BeGreaterOrEqual 1
    }
}

Describe 'Invoke-MarketplaceValidation - bare source rejection' {
    BeforeAll {
        $script:repoRoot = Join-Path $TestDrive 'repo-source-errors'
        $manifestDir = Join-Path $script:repoRoot '.github/plugin'
        New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
        Set-Content -Path (Join-Path $script:repoRoot 'package.json') -Value '{"version":"1.0.0"}'
        $json = @{
            name     = 'test'
            metadata = @{ description = 'd'; version = '1.0.0'; pluginRoot = 'plugins' }
            owner    = @{ name = 'owner' }
            plugins  = @(
                @{ name = 'my-plugin'; source = 'my-plugin'; description = 'd'; version = '1.0.0' }
            )
        } | ConvertTo-Json -Depth 5
        Set-Content -Path (Join-Path $manifestDir 'marketplace.json') -Value $json
    }

    It 'Returns error for a bare package source' {
        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot
        $result.Success | Should -BeFalse
        $result.ErrorCount | Should -BeGreaterOrEqual 1
    }
}

Describe 'Invoke-MarketplaceValidation - name-source mismatch' {
    BeforeAll {
        $script:repoRoot = Join-Path $TestDrive 'repo-name-mismatch'
        $manifestDir = Join-Path $script:repoRoot '.github/plugin'
        New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:repoRoot 'plugins/actual-source') -Force | Out-Null
        Set-Content -Path (Join-Path $script:repoRoot 'package.json') -Value '{"version":"1.0.0"}'
        $json = @{
            name     = 'test'
            metadata = @{ description = 'd'; version = '1.0.0'; pluginRoot = 'plugins' }
            owner    = @{ name = 'owner' }
            plugins  = @(
                @{ name = 'display-name'; source = (New-TestPluginSource -Name 'actual-source'); description = 'd'; version = '1.0.0' }
            )
        } | ConvertTo-Json -Depth 5
        Set-Content -Path (Join-Path $manifestDir 'marketplace.json') -Value $json
    }

    It 'Returns error when the object path does not match the plugin name' {
        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot
        $result.Success | Should -BeFalse
        $result.ErrorCount | Should -BeGreaterOrEqual 1
    }
}

Describe 'Invoke-MarketplaceValidation - plugin version mismatch' {
    BeforeAll {
        $script:repoRoot = Join-Path $TestDrive 'repo-plugin-version'
        $manifestDir = Join-Path $script:repoRoot '.github/plugin'
        New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:repoRoot 'plugins/my-plugin') -Force | Out-Null
        Set-Content -Path (Join-Path $script:repoRoot 'package.json') -Value '{"version":"2.0.0"}'
        $json = @{
            name     = 'test'
            metadata = @{ description = 'd'; version = '2.0.0'; pluginRoot = 'plugins' }
            owner    = @{ name = 'owner' }
            plugins  = @(
                @{ name = 'my-plugin'; source = (New-TestPluginSource -Name 'my-plugin'); description = 'd'; version = '1.0.0' }
            )
        } | ConvertTo-Json -Depth 5
        Set-Content -Path (Join-Path $manifestDir 'marketplace.json') -Value $json
    }

    It 'Returns error when plugin version does not match package.json' {
        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot
        $result.Success | Should -BeFalse
        $result.ErrorCount | Should -BeGreaterOrEqual 1
    }
}

Describe 'Invoke-MarketplaceValidation - missing plugin fields' {
    BeforeAll {
        $script:repoRoot = Join-Path $TestDrive 'repo-missing-plugin-fields'
        $manifestDir = Join-Path $script:repoRoot '.github/plugin'
        New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
        Set-Content -Path (Join-Path $script:repoRoot 'package.json') -Value '{"version":"1.0.0"}'
        # Plugin missing 'description' and 'version'
        $json = @{
            name     = 'test'
            metadata = @{ description = 'd'; version = '1.0.0'; pluginRoot = 'plugins' }
            owner    = @{ name = 'owner' }
            plugins  = @(
                @{ name = 'my-plugin'; source = (New-TestPluginSource -Name 'my-plugin') }
            )
        } | ConvertTo-Json -Depth 5
        Set-Content -Path (Join-Path $manifestDir 'marketplace.json') -Value $json
    }

    It 'Returns errors for missing plugin-level fields' {
        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot
        $result.Success | Should -BeFalse
        $result.ErrorCount | Should -BeGreaterOrEqual 2
    }
}

Describe 'Invoke-MarketplaceValidation - valid manifest' {
    BeforeAll {
        $script:repoRoot = Join-Path $TestDrive 'repo-valid'
        $manifestDir = Join-Path $script:repoRoot '.github/plugin'
        New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:repoRoot 'plugins/my-plugin') -Force | Out-Null
        Set-Content -Path (Join-Path $script:repoRoot 'package.json') -Value '{"version":"1.0.0"}'
        $json = @{
            name     = 'test'
            metadata = @{ description = 'd'; version = '1.0.0'; pluginRoot = 'plugins' }
            owner    = @{ name = 'owner' }
            plugins  = @(
                @{ name = 'my-plugin'; source = (New-TestPluginSource -Name 'my-plugin'); description = 'A plugin'; version = '1.0.0' }
            )
        } | ConvertTo-Json -Depth 5
        Set-Content -Path (Join-Path $manifestDir 'marketplace.json') -Value $json
    }

    It 'Returns success for a valid manifest' {
        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot
        $result.Success | Should -BeTrue
        $result.ErrorCount | Should -Be 0
    }

    It 'Returns success with multiple valid plugins' {
        New-Item -ItemType Directory -Path (Join-Path $script:repoRoot 'plugins/other-plugin') -Force | Out-Null
        $json = @{
            name     = 'test'
            metadata = @{ description = 'd'; version = '1.0.0'; pluginRoot = 'plugins' }
            owner    = @{ name = 'owner' }
            plugins  = @(
                @{ name = 'my-plugin'; source = (New-TestPluginSource -Name 'my-plugin'); description = 'A plugin'; version = '1.0.0' }
                @{ name = 'other-plugin'; source = (New-TestPluginSource -Name 'other-plugin'); description = 'Another'; version = '1.0.0' }
            )
        } | ConvertTo-Json -Depth 5
        $manifestDir = Join-Path $script:repoRoot '.github/plugin'
        Set-Content -Path (Join-Path $manifestDir 'marketplace.json') -Value $json

        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot
        $result.Success | Should -BeTrue
        $result.ErrorCount | Should -Be 0
    }
}

Describe 'Invoke-MarketplaceValidation - JSON output' {
    BeforeEach {
        $script:repoRoot = Join-Path $TestDrive 'repo-json-output'
        $script:manifestDir = Join-Path $script:repoRoot '.github/plugin'
        New-Item -ItemType Directory -Path $script:manifestDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:repoRoot 'plugins/my-plugin') -Force | Out-Null
        Set-Content -Path (Join-Path $script:repoRoot 'package.json') -Value '{"version":"1.0.0"}'
    }

    It 'Writes report with expected schema for valid plugin validation' {
        $outputPath = Join-Path $TestDrive 'logs/marketplace-validation-results.json'
        $json = @{
            name     = 'test'
            metadata = @{ description = 'd'; version = '1.0.0'; pluginRoot = 'plugins' }
            owner    = @{ name = 'owner' }
            plugins  = @(
                @{ name = 'my-plugin'; source = (New-TestPluginSource -Name 'my-plugin'); description = 'A plugin'; version = '1.0.0' }
            )
        } | ConvertTo-Json -Depth 5
        Set-Content -Path (Join-Path $script:manifestDir 'marketplace.json') -Value $json

        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot -OutputPath $outputPath
        $report = Get-Content -Path $outputPath -Raw | ConvertFrom-Json

        $result.Success | Should -BeTrue
        $report.Timestamp | Should -Not -BeNullOrEmpty
        { [DateTimeOffset]::Parse($report.Timestamp) } | Should -Not -Throw
        $report.ErrorCount | Should -Be 0
        $report.Results.Count | Should -Be 1
        $report.Results[0].PluginName | Should -Be 'my-plugin'
        $report.Results[0].IsValid | Should -BeTrue
        $report.Results[0].Errors | Should -BeNullOrEmpty
        $report.Results[0].Warnings | Should -BeNullOrEmpty
    }

    It 'Writes per-plugin errors into JSON results' {
        $outputPath = Join-Path $TestDrive 'logs/marketplace-validation-results.json'
        New-Item -ItemType Directory -Path (Join-Path $script:repoRoot 'plugins/actual-source') -Force | Out-Null
        $json = @{
            name     = 'test'
            metadata = @{ description = 'd'; version = '1.0.0'; pluginRoot = 'plugins' }
            owner    = @{ name = 'owner' }
            plugins  = @(
                @{ name = 'display-name'; source = (New-TestPluginSource -Name 'actual-source'); description = 'A plugin'; version = '1.0.0' }
            )
        } | ConvertTo-Json -Depth 5
        Set-Content -Path (Join-Path $script:manifestDir 'marketplace.json') -Value $json

        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot -OutputPath $outputPath
        $report = Get-Content -Path $outputPath -Raw | ConvertFrom-Json
        $pluginResult = @($report.Results | Where-Object { $_.PluginName -eq 'display-name' })[0]

        $result.Success | Should -BeFalse
        $report.ErrorCount | Should -BeGreaterThan 0
        $pluginResult.IsValid | Should -BeFalse
        $pluginResult.Errors | Should -Contain "object source path must match package name 'plugins/display-name'"
        $pluginResult.Warnings | Should -BeNullOrEmpty
    }
}

Describe 'Test-PluginSourcePath' {
    It 'Returns empty string for a repository-relative package path' {
        Test-PluginSourcePath -Path 'plugins/hve-core' | Should -BeNullOrEmpty
    }

    It 'Returns error for a backslash path' {
        Test-PluginSourcePath -Path 'plugins\hve-core' | Should -BeLike '*must use forward slashes*'
    }

    It 'Returns error for an absolute POSIX path' {
        Test-PluginSourcePath -Path '/plugins/hve-core' | Should -BeLike '*must be relative to the repository root*'
    }

    It 'Returns error for an absolute Windows path' {
        Test-PluginSourcePath -Path 'C:/plugins/hve-core' | Should -BeLike '*must be relative to the repository root*'
    }

    It 'Returns error for an escaping path' {
        Test-PluginSourcePath -Path '../../etc/passwd' | Should -BeLike '*must not escape the source repository*'
    }

    It 'Returns error for an embedded escaping segment' {
        Test-PluginSourcePath -Path 'plugins/../../secrets' | Should -BeLike '*must not escape the source repository*'
    }

    It 'Returns error for a relative path segment' {
        Test-PluginSourcePath -Path 'plugins/./hve-core' | Should -BeLike '*must not contain relative path segments*'
    }

    It 'Returns error for an empty path segment' {
        Test-PluginSourcePath -Path 'plugins//hve-core' | Should -BeLike '*must not contain empty path segments*'
    }
}

Describe 'Test-PluginObjectSource' {
    It 'Returns no errors for a tag-pinned github locator' {
        $result = Test-PluginObjectSource -Source ([ordered]@{
                source = 'github'
                repo   = 'microsoft/hve-core'
                path   = 'plugins/hve-core'
                ref    = 'plugins-v1.2.3'
            })
        $result | Should -BeNullOrEmpty
    }

    It 'Returns an error for a sha-pinned github locator' {
        $result = Test-PluginObjectSource -Source ([ordered]@{
                source = 'github'
                repo   = 'microsoft/hve-core'
                path   = 'plugins/hve-core'
                sha    = '0123456789abcdef0123456789abcdef01234567'
            })
        $result | Should -Contain "object source 'sha' is not supported; use an immutable 'plugins-v<version>' ref"
    }

    It 'Returns an error for an unpinned github locator' {
        $result = Test-PluginObjectSource -Source ([ordered]@{
                source = 'github'
                repo   = 'microsoft/hve-core'
                path   = 'plugins/hve-core'
            })
        $result | Should -Contain "object source 'ref' must be a non-empty string"
    }

    It 'Returns an error for a url locator' {
        $result = Test-PluginObjectSource -Source ([ordered]@{
                source = 'url'
                url    = 'https://example.com/hve-core.git'
                path   = 'plugins/hve-core'
            })
        @($result)[0] | Should -BeLike "*'url' is not supported*"
    }

    It 'Returns error when source type is missing' {
        $result = Test-PluginObjectSource -Source ([ordered]@{ repo = 'microsoft/hve-core'; path = 'plugins/hve-core' })
        $result | Should -Contain "object source is missing required field 'source'"
    }

    It 'Returns error for an unsupported source type' {
        $result = Test-PluginObjectSource -Source ([ordered]@{ source = 'ftp'; path = 'plugins/hve-core' })
        @($result)[0] | Should -BeLike "*'ftp' is not supported*"
    }

    It 'Returns error when a github locator omits repo' {
        $result = Test-PluginObjectSource -Source ([ordered]@{ source = 'github'; path = 'plugins/hve-core' })
        $result | Should -Contain "object source of type 'github' is missing required field 'repo'"
    }

    It 'Returns error for a malformed repo locator' {
        $result = Test-PluginObjectSource -Source ([ordered]@{ source = 'github'; repo = 'hve-core'; path = 'plugins/hve-core' })
        @($result)[0] | Should -BeLike "*must use 'owner/name' form*"
    }

    It 'Returns error when path is missing' {
        $result = Test-PluginObjectSource -Source ([ordered]@{ source = 'github'; repo = 'microsoft/hve-core' })
        $result | Should -Contain "object source is missing required field 'path'"
    }

    It 'Returns error for an escaping path' {
        $result = Test-PluginObjectSource -Source ([ordered]@{ source = 'github'; repo = 'microsoft/hve-core'; path = '../../etc' })
        @($result)[0] | Should -BeLike '*must not escape the source repository*'
    }

    It 'Returns error for a non-string ref' {
        $result = Test-PluginObjectSource -Source ([ordered]@{ source = 'github'; repo = 'microsoft/hve-core'; path = 'plugins/x'; ref = 3 })
        $result | Should -Contain "object source 'ref' must be a non-empty string"
    }

    It 'Returns error for an empty ref' {
        $result = Test-PluginObjectSource -Source ([ordered]@{ source = 'github'; repo = 'microsoft/hve-core'; path = 'plugins/x'; ref = '  ' })
        $result | Should -Contain "object source 'ref' must be a non-empty string"
    }

    It 'Returns error for a moving ref' {
        $result = Test-PluginObjectSource -Source ([ordered]@{ source = 'github'; repo = 'microsoft/hve-core'; path = 'plugins/x'; ref = 'main' })
        $result | Should -Contain "object source 'ref' must use the immutable 'plugins-v<version>' tag form"
    }
}

Describe 'Invoke-MarketplaceValidation - object source entries' {
    BeforeAll {
        $script:repoRoot = Join-Path $TestDrive 'repo-object-source'
        $script:manifestDir = Join-Path $script:repoRoot '.github/plugin'
        New-Item -ItemType Directory -Path $script:manifestDir -Force | Out-Null
        Set-Content -Path (Join-Path $script:repoRoot 'package.json') -Value '{"version":"1.0.0"}'
        # No plugins/ directory: object sources resolve remotely, so validation must not require generated output.
        $json = @{
            name     = 'test'
            metadata = @{ description = 'd'; version = '1.0.0'; pluginRoot = 'plugins' }
            owner    = @{ name = 'owner' }
            plugins  = @(
                @{
                    name        = 'my-plugin'
                    source      = [ordered]@{
                        source = 'github'
                        repo   = 'microsoft/hve-core'
                        path   = 'plugins/my-plugin'
                        ref    = 'plugins-v1.0.0'
                    }
                    description = 'A plugin'
                    version     = '1.0.0'
                }
            )
        } | ConvertTo-Json -Depth 6
        Set-Content -Path (Join-Path $script:manifestDir 'marketplace.json') -Value $json
    }

    It 'Accepts a GitHub object source when generated output is absent' {
        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot -OutputPath (Join-Path $TestDrive 'logs/object-source.json')
        $result.Success | Should -BeTrue
        $result.ErrorCount | Should -Be 0
    }

    It 'Does not apply name-source equality to an object source' {
        $json = @{
            name     = 'test'
            metadata = @{ description = 'd'; version = '1.0.0'; pluginRoot = 'plugins' }
            owner    = @{ name = 'owner' }
            plugins  = @(
                @{
                    name        = 'my-plugin'
                    source      = [ordered]@{
                        source = 'github'
                        repo   = 'microsoft/hve-core'
                        path   = 'plugins/my-plugin'
                        ref    = 'plugins-v1.0.0'
                    }
                    description = 'A plugin'
                    version     = '1.0.0'
                }
            )
        } | ConvertTo-Json -Depth 6
        Set-Content -Path (Join-Path $script:manifestDir 'marketplace.json') -Value $json

        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot -OutputPath (Join-Path $TestDrive 'logs/object-name.json')
        $result.Success | Should -BeTrue
    }

    It 'Reports object source errors in the JSON report' {
        $outputPath = Join-Path $TestDrive 'logs/object-source-errors.json'
        $json = @{
            name     = 'test'
            metadata = @{ description = 'd'; version = '1.0.0'; pluginRoot = 'plugins' }
            owner    = @{ name = 'owner' }
            plugins  = @(
                @{
                    name        = 'my-plugin'
                    source      = [ordered]@{
                        source = 'github'
                        repo   = 'not-a-repo-locator'
                        path   = '../escape'
                    }
                    description = 'A plugin'
                    version     = '1.0.0'
                }
            )
        } | ConvertTo-Json -Depth 6
        Set-Content -Path (Join-Path $script:manifestDir 'marketplace.json') -Value $json

        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot -OutputPath $outputPath
        $report = Get-Content -Path $outputPath -Raw | ConvertFrom-Json
        $pluginResult = @($report.Results | Where-Object { $_.PluginName -eq 'my-plugin' })[0]

        $result.Success | Should -BeFalse
        $pluginResult.IsValid | Should -BeFalse
        $pluginResult.Errors.Count | Should -Be 5
    }

    It 'Returns error when source is neither a string nor an object' {
        $json = @{
            name     = 'test'
            metadata = @{ description = 'd'; version = '1.0.0'; pluginRoot = 'plugins' }
            owner    = @{ name = 'owner' }
            plugins  = @(
                @{ name = 'my-plugin'; source = @('a', 'b'); description = 'A plugin'; version = '1.0.0' }
            )
        } | ConvertTo-Json -Depth 6
        Set-Content -Path (Join-Path $script:manifestDir 'marketplace.json') -Value $json

        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot -OutputPath (Join-Path $TestDrive 'logs/object-source-type.json')
        $result.Success | Should -BeFalse
    }
}

Describe 'Invoke-MarketplaceValidation - bare source rejection' {
    BeforeAll {
        $script:repoRoot = Join-Path $TestDrive 'repo-bare-conditional'
        $script:manifestDir = Join-Path $script:repoRoot '.github/plugin'
        New-Item -ItemType Directory -Path $script:manifestDir -Force | Out-Null
        Set-Content -Path (Join-Path $script:repoRoot 'package.json') -Value '{"version":"1.0.0"}'
        $script:json = @{
            name     = 'test'
            metadata = @{ description = 'd'; version = '1.0.0'; pluginRoot = 'plugins' }
            owner    = @{ name = 'owner' }
            plugins  = @(
                @{ name = 'my-plugin'; source = 'my-plugin'; description = 'A plugin'; version = '1.0.0' }
            )
        } | ConvertTo-Json -Depth 5
        Set-Content -Path (Join-Path $script:manifestDir 'marketplace.json') -Value $script:json
    }

    It 'Rejects a bare source when generated output is absent' {
        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot -OutputPath (Join-Path $TestDrive 'logs/bare-absent.json')
        $result.Success | Should -BeFalse
    }

    It 'Rejects a bare source when generated output is present' {
        New-Item -ItemType Directory -Path (Join-Path $script:repoRoot 'plugins/my-plugin') -Force | Out-Null
        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot -OutputPath (Join-Path $TestDrive 'logs/bare-present.json')
        $result.Success | Should -BeFalse
    }
}

Describe 'Invoke-MarketplaceValidation - entry component contract' {
    BeforeAll {
        $script:repoRoot = Join-Path $TestDrive 'repo-entry-contract'
        $script:manifestDir = Join-Path $script:repoRoot '.github/plugin'
        New-Item -ItemType Directory -Path $script:manifestDir -Force | Out-Null
        Set-Content -Path (Join-Path $script:repoRoot 'package.json') -Value '{"version":"1.0.0"}'

        function script:Set-EntryContractManifest {
            param([hashtable]$Entry)

            $json = @{
                name     = 'test'
                metadata = @{ description = 'd'; version = '1.0.0'; pluginRoot = 'plugins' }
                owner    = @{ name = 'owner' }
                plugins  = @($Entry)
            } | ConvertTo-Json -Depth 8
            Set-Content -Path (Join-Path $script:manifestDir 'marketplace.json') -Value $json
        }
    }

    It 'Accepts standard commands and rules membership with a metadata-only x-hve overlay' {
        Set-EntryContractManifest -Entry @{
            name        = 'my-plugin'
            source      = (New-TestPluginSource -Name 'my-plugin')
            description = 'A plugin'
            version     = '1.0.0'
            author      = [ordered]@{ name = 'Microsoft'; url = 'https://www.microsoft.com' }
            commands    = @('commands/rpi-research.md')
            rules       = @('instructions/markdown.instructions.md')
            hooks       = 'hooks/shared/telemetry.json'
            'x-hve'     = [ordered]@{
                maturity          = 'stable'
                componentMaturity = [ordered]@{ 'commands/rpi-research.md' = 'preview' }
                documentation     = 'docs/plugins/my-plugin.md'
            }
        }

        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot -OutputPath (Join-Path $TestDrive 'logs/entry-contract-valid.json')
        $result.Success | Should -BeTrue
        $result.ErrorCount | Should -Be 0
    }

    It 'Rejects a string author' {
        Set-EntryContractManifest -Entry @{
            name        = 'my-plugin'
            source      = (New-TestPluginSource -Name 'my-plugin')
            description = 'A plugin'
            version     = '1.0.0'
            author      = 'Microsoft'
        }

        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot -OutputPath (Join-Path $TestDrive 'logs/string-author.json')
        $result.Success | Should -BeFalse
    }

    It 'Rejects array-valued hooks' {
        Set-EntryContractManifest -Entry @{
            name        = 'my-plugin'
            source      = (New-TestPluginSource -Name 'my-plugin')
            description = 'A plugin'
            version     = '1.0.0'
            hooks       = @('hooks/shared/telemetry.json')
        }

        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot -OutputPath (Join-Path $TestDrive 'logs/array-hooks.json')
        $result.Success | Should -BeFalse
    }

    It 'Rejects an x-hve overlay that owns component membership' {
        Set-EntryContractManifest -Entry @{
            name        = 'my-plugin'
            source      = (New-TestPluginSource -Name 'my-plugin')
            description = 'A plugin'
            version     = '1.0.0'
            'x-hve'     = [ordered]@{
                maturity     = 'stable'
                instructions = @('instructions/markdown.instructions.md')
            }
        }

        $outputPath = Join-Path $TestDrive 'logs/entry-contract-membership.json'
        $result = Invoke-MarketplaceValidation -RepoRoot $script:repoRoot -OutputPath $outputPath
        $report = Get-Content -Path $outputPath -Raw | ConvertFrom-Json

        $result.Success | Should -BeFalse
        @($report.Results | Where-Object { $_.PluginName -eq 'my-plugin' })[0].Errors |
            Should -Contain "x-hve contains unsupported key 'instructions'"
    }
}
