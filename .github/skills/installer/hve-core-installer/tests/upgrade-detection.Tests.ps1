#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Discovery-time capability probe: the Bash parity fixtures execute the real
# upgrade-detection.sh, so they are skipped where no Bash interpreter is present.
$script:BashAvailable = [bool](Get-Command bash -ErrorAction SilentlyContinue)

BeforeAll {
    $script:PowerShellScript = (Resolve-Path (Join-Path $PSScriptRoot '../scripts/upgrade-detection.ps1')).Path
    $script:BashScript = (Resolve-Path (Join-Path $PSScriptRoot '../scripts/upgrade-detection.sh')).Path
    $script:FixtureCounter = 0

    function script:New-UpgradeFixture {
        param(
            [string]$SourceVersion = '3.3.106',
            [AllowNull()][hashtable]$Manifest
        )

        $script:FixtureCounter++
        $root = Join-Path $TestDrive "upgrade-$($script:FixtureCounter)"
        $source = Join-Path $root 'source'
        $target = Join-Path $root 'target'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        New-Item -ItemType Directory -Path $target -Force | Out-Null

        Set-Content -LiteralPath (Join-Path $source 'package.json') -Value "{ `"version`": `"$SourceVersion`" }" -NoNewline

        if ($null -ne $Manifest) {
            $Manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $target '.hve-tracking.json') -NoNewline
        }

        return [pscustomobject]@{ Root = $root; Source = $source; Target = $target }
    }

    function script:Invoke-PowerShellDetector {
        param([pscustomobject]$Fixture)

        Push-Location $Fixture.Target
        try {
            return (& $script:PowerShellScript -HveCoreBasePath $Fixture.Source 6>&1 | Out-String).Trim()
        }
        finally { Pop-Location }
    }

    function script:Invoke-BashDetector {
        param([pscustomobject]$Fixture)

        Push-Location $Fixture.Target
        try {
            return (& bash $script:BashScript $Fixture.Source 2>&1 | Out-String).Trim()
        }
        finally { Pop-Location }
    }

    function script:New-InstalledManifest {
        param(
            [string]$Version = '3.3.100',
            [string]$Package
        )

        $manifest = @{
            source  = 'microsoft/hve-core'
            version = $Version
            files   = @{}
        }
        if ($PSBoundParameters.ContainsKey('Package')) {
            $manifest['package'] = $Package
        }
        return $manifest
    }
}

Describe 'upgrade-detection contract' -Tag 'Unit' {
    BeforeAll {
        $script:command = Get-Command -Name $script:PowerShellScript
        $script:powerShellSource = Get-Content -LiteralPath $script:PowerShellScript -Raw
        $script:bashSource = Get-Content -LiteralPath $script:BashScript -Raw
    }

    It 'Declares only the HVE-Core base path parameter' {
        @($script:command.Parameters.Keys | Where-Object { $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters }) | Should -Be @('HveCoreBasePath')
    }

    It 'Emits package vocabulary and no collection fallback in the PowerShell implementation' {
        $script:powerShellSource | Should -Match 'INSTALLED_PACKAGE='
        $script:powerShellSource | Should -Not -Match '(?i)collection'
    }

    It 'Emits package vocabulary and no collection fallback in the Bash implementation' {
        $script:bashSource | Should -Match 'INSTALLED_PACKAGE='
        $script:bashSource | Should -Not -Match '(?i)collection'
    }
}

Describe 'upgrade-detection fresh installation' -Tag 'Unit' {
    BeforeAll {
        $script:fixture = New-UpgradeFixture
        $script:output = Invoke-PowerShellDetector -Fixture $script:fixture
    }

    It 'Reports UPGRADE_MODE=false when no tracking manifest exists' {
        $script:output | Should -Be 'UPGRADE_MODE=false'
    }

    It 'Emits no package or version keys' {
        $script:output | Should -Not -Match 'INSTALLED_PACKAGE='
        $script:output | Should -Not -Match 'INSTALLED_VERSION='
        $script:output | Should -Not -Match 'VERSION_CHANGED='
    }
}

Describe 'upgrade-detection version reporting' -Tag 'Unit' {
    It 'Reports the installed and source versions' {
        $fixture = New-UpgradeFixture -SourceVersion '3.3.106' -Manifest (New-InstalledManifest -Version '3.3.100' -Package 'hve-core')

        $output = Invoke-PowerShellDetector -Fixture $fixture

        $output | Should -Match '(?m)^UPGRADE_MODE=true$'
        $output | Should -Match '(?m)^INSTALLED_VERSION=3\.3\.100$'
        $output | Should -Match '(?m)^SOURCE_VERSION=3\.3\.106$'
    }

    It 'Reports VERSION_CHANGED=true when the source version differs' {
        $fixture = New-UpgradeFixture -SourceVersion '3.3.106' -Manifest (New-InstalledManifest -Version '3.3.100' -Package 'hve-core')

        Invoke-PowerShellDetector -Fixture $fixture | Should -Match '(?m)^VERSION_CHANGED=true$'
    }

    It 'Reports VERSION_CHANGED=false when the versions match' {
        $fixture = New-UpgradeFixture -SourceVersion '3.3.106' -Manifest (New-InstalledManifest -Version '3.3.106' -Package 'hve-core')

        Invoke-PowerShellDetector -Fixture $fixture | Should -Match '(?m)^VERSION_CHANGED=false$'
    }
}

Describe 'upgrade-detection package reporting' -Tag 'Unit' {
    It 'Reports the package recorded by the installer' {
        $fixture = New-UpgradeFixture -Manifest (New-InstalledManifest -Package 'project-planning')

        Invoke-PowerShellDetector -Fixture $fixture | Should -Match '(?m)^INSTALLED_PACKAGE=project-planning$'
    }

    It 'Defaults to hve-core when the manifest records no package' {
        $fixture = New-UpgradeFixture -Manifest (New-InstalledManifest)

        Invoke-PowerShellDetector -Fixture $fixture | Should -Match '(?m)^INSTALLED_PACKAGE=hve-core$'
    }

    It 'Defaults to hve-core when the manifest records only an unsupported legacy key' {
        $manifest = New-InstalledManifest
        $manifest['collection'] = 'legacy-bundle'
        $fixture = New-UpgradeFixture -Manifest $manifest

        $output = Invoke-PowerShellDetector -Fixture $fixture
        $output | Should -Match '(?m)^INSTALLED_PACKAGE=hve-core$'
        $output | Should -Not -Match 'legacy-bundle'
    }
}

Describe 'upgrade-detection PowerShell and Bash parity' -Tag 'Unit' -Skip:(-not $script:BashAvailable) {
    It 'Produces identical output for a fresh installation' {
        $fixture = New-UpgradeFixture

        Invoke-BashDetector -Fixture $fixture | Should -Be (Invoke-PowerShellDetector -Fixture $fixture)
    }

    It 'Produces identical output for an upgradeable installation' {
        $fixture = New-UpgradeFixture -SourceVersion '3.3.106' -Manifest (New-InstalledManifest -Version '3.3.100' -Package 'project-planning')

        Invoke-BashDetector -Fixture $fixture | Should -Be (Invoke-PowerShellDetector -Fixture $fixture)
    }

    It 'Produces identical output for an up-to-date installation' {
        $fixture = New-UpgradeFixture -SourceVersion '3.3.106' -Manifest (New-InstalledManifest -Version '3.3.106' -Package 'hve-core')

        Invoke-BashDetector -Fixture $fixture | Should -Be (Invoke-PowerShellDetector -Fixture $fixture)
    }

    It 'Produces identical output when the manifest records no package' {
        $fixture = New-UpgradeFixture -Manifest (New-InstalledManifest)

        Invoke-BashDetector -Fixture $fixture | Should -Be (Invoke-PowerShellDetector -Fixture $fixture)
    }

    It 'Reads an explicit package on the fallback path without jq' {
        $fixture = New-UpgradeFixture -Manifest (New-InstalledManifest -Package 'project-planning')
        $bashPath = (Get-Command bash).Source

        # The script probes with `command -v jq`, so the fallback branch is forced
        # by running against a PATH that exposes only the tools it needs.
        $shimDir = Join-Path $fixture.Root 'no-jq-bin'
        New-Item -ItemType Directory -Path $shimDir -Force | Out-Null
        foreach ($tool in @('grep', 'head', 'sed')) {
            $resolved = (Get-Command $tool).Source
            $shim = Join-Path $shimDir $tool
            Set-Content -LiteralPath $shim -Value "#!$bashPath`nexec '$resolved' `"`$@`"`n" -NoNewline
            & chmod '+x' $shim
        }

        $savedPath = $env:PATH
        try {
            $env:PATH = $shimDir
            Push-Location $fixture.Target
            try {
                $output = (& $bashPath $script:BashScript $fixture.Source 2>&1 | Out-String).Trim()
            }
            finally { Pop-Location }
        }
        finally { $env:PATH = $savedPath }

        $output | Should -Match '(?m)^INSTALLED_PACKAGE=project-planning$'
        $output | Should -Match '(?m)^UPGRADE_MODE=true$'
    }
}
