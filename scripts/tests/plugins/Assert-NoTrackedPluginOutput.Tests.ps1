#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

BeforeAll {
    . (Join-Path $PSScriptRoot '../../plugins/Assert-NoTrackedPluginOutput.ps1')
}

Describe 'Assert-NoTrackedPluginOutput' -Tag 'Unit' {
    BeforeEach {
        $script:repoRoot = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:repoRoot -Force | Out-Null
        Set-Content -Path (Join-Path $script:repoRoot 'source.txt') -Value 'source' -NoNewline

        & git -C $script:repoRoot init --quiet
        & git -C $script:repoRoot config user.email 'test@example.com'
        & git -C $script:repoRoot config user.name 'Test User'
        & git -C $script:repoRoot add source.txt
        & git -C $script:repoRoot commit --quiet -m 'baseline'
    }

    It 'Accepts an index with regular source files' {
        $result = Assert-NoTrackedPluginOutput -RepoRoot $script:repoRoot

        $result.EntryCount | Should -Be 1
        $result.TrackedPluginPathCount | Should -Be 0
        $result.SymbolicLinkPathCount | Should -Be 0
    }

    It 'Rejects a tracked plugin output path and names it' {
        New-Item -ItemType Directory -Path (Join-Path $script:repoRoot 'plugins/alpha') -Force | Out-Null
        Set-Content -Path (Join-Path $script:repoRoot 'plugins/alpha/plugin.json') -Value '{}' -NoNewline
        & git -C $script:repoRoot add plugins/alpha/plugin.json

        { Assert-NoTrackedPluginOutput -RepoRoot $script:repoRoot } |
            Should -Throw '*Tracked plugin output is forbidden: plugins/alpha/plugin.json*'
    }

    It 'Rejects symbolic-link mode and names the path' {
        $blob = (& git -C $script:repoRoot rev-parse HEAD:source.txt).Trim()
        & git -C $script:repoRoot update-index --cacheinfo "120000,$blob,source.txt"

        { Assert-NoTrackedPluginOutput -RepoRoot $script:repoRoot } |
            Should -Throw '*Symbolic-link mode 120000 is forbidden: source.txt*'
    }
}