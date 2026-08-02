#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Discovery-time capability probe: the Bash parity fixtures execute the real
# agent-copy.sh, so they are skipped where no Bash interpreter is present.
$script:BashAvailable = [bool](Get-Command bash -ErrorAction SilentlyContinue)

BeforeAll {
    $script:PowerShellScript = (Resolve-Path (Join-Path $PSScriptRoot '../scripts/agent-copy.ps1')).Path
    $script:BashScript = (Resolve-Path (Join-Path $PSScriptRoot '../scripts/agent-copy.sh')).Path
    $script:FixtureCounter = 0

    function script:New-AgentCopyFixture {
        param([string]$Version = '2.0.0')

        $script:FixtureCounter++
        $root = Join-Path $TestDrive "agent-copy-$($script:FixtureCounter)"
        $source = Join-Path $root 'source'
        $target = Join-Path $root 'target'

        $agentFixtures = @{
            'hve-core/rpi-agent.agent.md'                = '# RPI Agent'
            'hve-core/documentation.agent.md'            = '# Documentation'
            'project-planning/adr-creation.agent.md'     = '# ADR Creation'
            'project-planning/subagents/prd-qa.agent.md' = '# PRD QA'
        }
        foreach ($rel in $agentFixtures.Keys) {
            $full = Join-Path $source ".github/agents/$rel"
            New-Item -ItemType Directory -Path (Split-Path $full -Parent) -Force | Out-Null
            Set-Content -LiteralPath $full -Value $agentFixtures[$rel] -NoNewline
        }

        Set-Content -LiteralPath (Join-Path $source 'package.json') -Value "{ `"version`": `"$Version`" }" -NoNewline
        New-Item -ItemType Directory -Path $target -Force | Out-Null

        return [pscustomobject]@{ Root = $root; Source = $source; Target = $target }
    }

    function script:Get-TrackingManifest {
        param([string]$TargetRoot)
        return Get-Content -LiteralPath (Join-Path $TargetRoot '.hve-tracking.json') -Raw | ConvertFrom-Json -AsHashtable
    }
}

Describe 'agent-copy parameter contract' -Tag 'Unit' {
    BeforeAll {
        $script:command = Get-Command -Name $script:PowerShellScript
        $script:powerShellSource = Get-Content -LiteralPath $script:PowerShellScript -Raw
        $script:bashSource = Get-Content -LiteralPath $script:BashScript -Raw
    }

    It 'Declares PackageId as a mandatory parameter' {
        $script:command.Parameters.Keys | Should -Contain 'PackageId'
        $attributes = @($script:command.Parameters['PackageId'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
        @($attributes | Where-Object { $_.Mandatory }).Count | Should -Be 1 -Because 'the marketplace package identity is required to write the tracking manifest'
    }

    It 'Declares no collection-named parameter' {
        @($script:command.Parameters.Keys | Where-Object { $_ -match 'collection' }) | Should -BeNullOrEmpty
    }

    It 'Uses package vocabulary and no collection fallback in the PowerShell implementation' {
        $script:powerShellSource | Should -Match '\$PackageId'
        $script:powerShellSource | Should -Not -Match '(?i)collection'
    }

    It 'Uses package vocabulary and no collection fallback in the Bash implementation' {
        $script:bashSource | Should -Match 'package_id'
        $script:bashSource | Should -Not -Match '(?i)collection'
    }
}

Describe 'agent-copy target directory' -Tag 'Unit' {
    BeforeEach {
        $script:fixture = New-AgentCopyFixture
        Push-Location $script:fixture.Target
    }

    AfterEach {
        Pop-Location
    }

    It 'Creates .github/agents when it is absent' {
        & $script:PowerShellScript -HveCoreBasePath $script:fixture.Source -PackageId 'hve-core' -FilesToCopy @('hve-core/rpi-agent.agent.md') | Out-Null

        Test-Path -LiteralPath '.github/agents' | Should -BeTrue
    }

    It 'Reuses an existing .github/agents directory without error' {
        New-Item -ItemType Directory -Path '.github/agents' -Force | Out-Null

        { & $script:PowerShellScript -HveCoreBasePath $script:fixture.Source -PackageId 'hve-core' -FilesToCopy @('hve-core/rpi-agent.agent.md') } | Should -Not -Throw
    }
}

Describe 'agent-copy file placement' -Tag 'Unit' {
    BeforeEach {
        $script:fixture = New-AgentCopyFixture
        Push-Location $script:fixture.Target
    }

    AfterEach {
        Pop-Location
    }

    It 'Flattens nested package agent paths into .github/agents' {
        & $script:PowerShellScript -HveCoreBasePath $script:fixture.Source -PackageId 'project-planning' -FilesToCopy @(
            'project-planning/adr-creation.agent.md'
            'project-planning/subagents/prd-qa.agent.md'
        ) | Out-Null

        Test-Path -LiteralPath '.github/agents/adr-creation.agent.md' | Should -BeTrue
        Test-Path -LiteralPath '.github/agents/prd-qa.agent.md' | Should -BeTrue
        Test-Path -LiteralPath '.github/agents/project-planning' | Should -BeFalse
    }

    It 'Copies source content verbatim' {
        & $script:PowerShellScript -HveCoreBasePath $script:fixture.Source -PackageId 'hve-core' -FilesToCopy @('hve-core/rpi-agent.agent.md') | Out-Null

        Get-Content -LiteralPath '.github/agents/rpi-agent.agent.md' -Raw | Should -Be '# RPI Agent'
    }

    It 'Overwrites an existing agent file when no collision is retained' {
        New-Item -ItemType Directory -Path '.github/agents' -Force | Out-Null
        Set-Content -LiteralPath '.github/agents/rpi-agent.agent.md' -Value '# Local edit' -NoNewline

        & $script:PowerShellScript -HveCoreBasePath $script:fixture.Source -PackageId 'hve-core' -FilesToCopy @('hve-core/rpi-agent.agent.md') | Out-Null

        Get-Content -LiteralPath '.github/agents/rpi-agent.agent.md' -Raw | Should -Be '# RPI Agent'
    }

    It 'Keeps a retained collision file untouched under -KeepExisting' {
        New-Item -ItemType Directory -Path '.github/agents' -Force | Out-Null
        Set-Content -LiteralPath '.github/agents/rpi-agent.agent.md' -Value '# Local edit' -NoNewline

        $output = & $script:PowerShellScript -HveCoreBasePath $script:fixture.Source -PackageId 'hve-core' `
            -FilesToCopy @('hve-core/rpi-agent.agent.md') -KeepExisting `
            -Collisions @('.github/agents/rpi-agent.agent.md') 6>&1 | Out-String

        Get-Content -LiteralPath '.github/agents/rpi-agent.agent.md' -Raw | Should -Be '# Local edit'
        $output | Should -Match 'Kept existing: rpi-agent\.agent\.md'
    }

    It 'Copies files absent from the collision list even under -KeepExisting' {
        New-Item -ItemType Directory -Path '.github/agents' -Force | Out-Null
        Set-Content -LiteralPath '.github/agents/rpi-agent.agent.md' -Value '# Local edit' -NoNewline

        & $script:PowerShellScript -HveCoreBasePath $script:fixture.Source -PackageId 'hve-core' `
            -FilesToCopy @('hve-core/rpi-agent.agent.md', 'hve-core/documentation.agent.md') -KeepExisting `
            -Collisions @('.github/agents/rpi-agent.agent.md') | Out-Null

        Get-Content -LiteralPath '.github/agents/rpi-agent.agent.md' -Raw | Should -Be '# Local edit'
        Get-Content -LiteralPath '.github/agents/documentation.agent.md' -Raw | Should -Be '# Documentation'
    }
}

Describe 'agent-copy tracking manifest' -Tag 'Unit' {
    BeforeEach {
        $script:fixture = New-AgentCopyFixture -Version '3.3.106'
        Push-Location $script:fixture.Target
    }

    AfterEach {
        Pop-Location
    }

    It 'Writes exactly the supported manifest keys' {
        & $script:PowerShellScript -HveCoreBasePath $script:fixture.Source -PackageId 'hve-core' -FilesToCopy @('hve-core/rpi-agent.agent.md') | Out-Null

        $manifest = Get-TrackingManifest -TargetRoot $script:fixture.Target
        @($manifest.Keys | Sort-Object) | Should -Be @('files', 'installed', 'package', 'source', 'version')
    }

    It 'Records the source repository and version read from package.json' {
        & $script:PowerShellScript -HveCoreBasePath $script:fixture.Source -PackageId 'hve-core' -FilesToCopy @('hve-core/rpi-agent.agent.md') | Out-Null

        $manifest = Get-TrackingManifest -TargetRoot $script:fixture.Target
        $manifest.source | Should -Be 'microsoft/hve-core'
        $manifest.version | Should -Be '3.3.106'
    }

    It 'Records the marketplace package identity supplied by the caller' {
        & $script:PowerShellScript -HveCoreBasePath $script:fixture.Source -PackageId 'project-planning' -FilesToCopy @('project-planning/adr-creation.agent.md') | Out-Null

        (Get-TrackingManifest -TargetRoot $script:fixture.Target).package | Should -Be 'project-planning'
    }

    It 'Records an ISO 8601 installation timestamp' {
        & $script:PowerShellScript -HveCoreBasePath $script:fixture.Source -PackageId 'hve-core' -FilesToCopy @('hve-core/rpi-agent.agent.md') | Out-Null

        $installed = (Get-TrackingManifest -TargetRoot $script:fixture.Target).installed
        [System.DateTimeOffset]::TryParse([string]$installed, [ref]([System.DateTimeOffset]::MinValue)) | Should -BeTrue
    }

    It 'Records a managed entry with the on-disk SHA256 for each copied file' {
        & $script:PowerShellScript -HveCoreBasePath $script:fixture.Source -PackageId 'hve-core' -FilesToCopy @('hve-core/rpi-agent.agent.md') | Out-Null

        $entry = (Get-TrackingManifest -TargetRoot $script:fixture.Target).files['.github/agents/rpi-agent.agent.md']
        $entry.status | Should -Be 'managed'
        $entry.version | Should -Be '3.3.106'
        $entry.sha256 | Should -Be (Get-FileHash -LiteralPath '.github/agents/rpi-agent.agent.md' -Algorithm SHA256).Hash.ToLower()
    }

    It 'Omits retained collision files from the managed file map' {
        New-Item -ItemType Directory -Path '.github/agents' -Force | Out-Null
        Set-Content -LiteralPath '.github/agents/rpi-agent.agent.md' -Value '# Local edit' -NoNewline

        & $script:PowerShellScript -HveCoreBasePath $script:fixture.Source -PackageId 'hve-core' `
            -FilesToCopy @('hve-core/rpi-agent.agent.md', 'hve-core/documentation.agent.md') -KeepExisting `
            -Collisions @('.github/agents/rpi-agent.agent.md') | Out-Null

        $files = (Get-TrackingManifest -TargetRoot $script:fixture.Target).files
        @($files.Keys) | Should -Be @('.github/agents/documentation.agent.md')
    }
}

Describe 'agent-copy error behavior' -Tag 'Unit' {
    BeforeEach {
        $script:fixture = New-AgentCopyFixture
        Push-Location $script:fixture.Target
    }

    AfterEach {
        Pop-Location
    }

    It 'Rejects an HveCoreBasePath that does not exist' {
        { & $script:PowerShellScript -HveCoreBasePath (Join-Path $script:fixture.Root 'missing-source') -PackageId 'hve-core' -FilesToCopy @('hve-core/rpi-agent.agent.md') } |
            Should -Throw -ExpectedMessage '*HveCoreBasePath*'
    }

    It 'Rejects an empty PackageId' {
        { & $script:PowerShellScript -HveCoreBasePath $script:fixture.Source -PackageId '' -FilesToCopy @('hve-core/rpi-agent.agent.md') } |
            Should -Throw -ExpectedMessage '*PackageId*'
    }

    It 'Fails and writes no manifest when a requested agent is absent from the source' {
        { & $script:PowerShellScript -HveCoreBasePath $script:fixture.Source -PackageId 'hve-core' -FilesToCopy @('hve-core/not-published.agent.md') } | Should -Throw

        Test-Path -LiteralPath '.hve-tracking.json' | Should -BeFalse
    }
}

Describe 'agent-copy PowerShell and Bash parity' -Tag 'Unit' -Skip:(-not $script:BashAvailable) {
    BeforeEach {
        $script:powerShellFixture = New-AgentCopyFixture -Version '3.3.106'
        $script:bashFixture = New-AgentCopyFixture -Version '3.3.106'
        $script:savedKeepExisting = $env:KEEP_EXISTING
        $script:savedCollisionsFile = $env:COLLISIONS_FILE
        $env:KEEP_EXISTING = $null
        $env:COLLISIONS_FILE = $null
    }

    AfterEach {
        $env:KEEP_EXISTING = $script:savedKeepExisting
        $env:COLLISIONS_FILE = $script:savedCollisionsFile
    }

    It 'Copies the same files with the same content' {
        Push-Location $script:powerShellFixture.Target
        try {
            & $script:PowerShellScript -HveCoreBasePath $script:powerShellFixture.Source -PackageId 'project-planning' `
                -FilesToCopy @('project-planning/adr-creation.agent.md', 'project-planning/subagents/prd-qa.agent.md') | Out-Null
        }
        finally { Pop-Location }

        Push-Location $script:bashFixture.Target
        try {
            & bash $script:BashScript $script:bashFixture.Source 'project-planning' 'project-planning/adr-creation.agent.md' 'project-planning/subagents/prd-qa.agent.md' 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0
        }
        finally { Pop-Location }

        $powerShellFiles = @(Get-ChildItem -LiteralPath (Join-Path $script:powerShellFixture.Target '.github/agents') -File | Select-Object -ExpandProperty Name | Sort-Object)
        $bashFiles = @(Get-ChildItem -LiteralPath (Join-Path $script:bashFixture.Target '.github/agents') -File | Select-Object -ExpandProperty Name | Sort-Object)
        $bashFiles | Should -Be $powerShellFiles

        foreach ($name in $powerShellFiles) {
            $bashContent = Get-Content -LiteralPath (Join-Path $script:bashFixture.Target ".github/agents/$name") -Raw
            $powerShellContent = Get-Content -LiteralPath (Join-Path $script:powerShellFixture.Target ".github/agents/$name") -Raw
            $bashContent | Should -Be $powerShellContent -Because "copied agent '$name' must not depend on the interpreter"
        }
    }

    It 'Writes the same manifest keys, package identity, and file entries' {
        Push-Location $script:powerShellFixture.Target
        try {
            & $script:PowerShellScript -HveCoreBasePath $script:powerShellFixture.Source -PackageId 'project-planning' `
                -FilesToCopy @('project-planning/adr-creation.agent.md') | Out-Null
        }
        finally { Pop-Location }

        Push-Location $script:bashFixture.Target
        try {
            & bash $script:BashScript $script:bashFixture.Source 'project-planning' 'project-planning/adr-creation.agent.md' 2>&1 | Out-Null
        }
        finally { Pop-Location }

        $powerShellManifest = Get-TrackingManifest -TargetRoot $script:powerShellFixture.Target
        $bashManifest = Get-TrackingManifest -TargetRoot $script:bashFixture.Target

        @($bashManifest.Keys | Sort-Object) | Should -Be @($powerShellManifest.Keys | Sort-Object)
        $bashManifest.source | Should -Be $powerShellManifest.source
        $bashManifest.version | Should -Be $powerShellManifest.version
        $bashManifest.package | Should -Be $powerShellManifest.package
        @($bashManifest.files.Keys | Sort-Object) | Should -Be @($powerShellManifest.files.Keys | Sort-Object)

        $entryKey = '.github/agents/adr-creation.agent.md'
        $bashManifest.files[$entryKey].sha256 | Should -Be $powerShellManifest.files[$entryKey].sha256
        $bashManifest.files[$entryKey].status | Should -Be $powerShellManifest.files[$entryKey].status
        [System.DateTimeOffset]::TryParse([string]$bashManifest.installed, [ref]([System.DateTimeOffset]::MinValue)) | Should -BeTrue
    }

    It 'Retains the same collision files under KEEP_EXISTING' {
        $targetAgents = Join-Path $script:bashFixture.Target '.github/agents'
        New-Item -ItemType Directory -Path $targetAgents -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $targetAgents 'adr-creation.agent.md') -Value '# Local edit' -NoNewline

        $collisionsFile = Join-Path $script:bashFixture.Root 'collisions.txt'
        Set-Content -LiteralPath $collisionsFile -Value '.github/agents/adr-creation.agent.md'

        $env:KEEP_EXISTING = 'true'
        $env:COLLISIONS_FILE = $collisionsFile

        Push-Location $script:bashFixture.Target
        try {
            & bash $script:BashScript $script:bashFixture.Source 'project-planning' 'project-planning/adr-creation.agent.md' 'project-planning/subagents/prd-qa.agent.md' 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0
        }
        finally { Pop-Location }

        Get-Content -LiteralPath (Join-Path $targetAgents 'adr-creation.agent.md') -Raw | Should -Be '# Local edit'
        Get-Content -LiteralPath (Join-Path $targetAgents 'prd-qa.agent.md') -Raw | Should -Be '# PRD QA'
        @((Get-TrackingManifest -TargetRoot $script:bashFixture.Target).files.Keys) | Should -Be @('.github/agents/prd-qa.agent.md')
    }

    It 'Exits non-zero when a requested agent is absent from the source' {
        Push-Location $script:bashFixture.Target
        try {
            & bash $script:BashScript $script:bashFixture.Source 'hve-core' 'hve-core/not-published.agent.md' 2>&1 | Out-Null
            $LASTEXITCODE | Should -Not -Be 0
        }
        finally { Pop-Location }
    }
}
