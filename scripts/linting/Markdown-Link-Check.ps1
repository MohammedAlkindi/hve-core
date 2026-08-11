#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Repository-aware wrapper for markdown-link-check.

.DESCRIPTION
    Runs markdown-link-check with the repo-specific configuration to validate
    all markdown links across the repository. Checks tracked and untracked,
    nonignored files so local validation does not require staging.

.PARAMETER Path
    One or more files or directories to scan. Directories are searched
    recursively for Markdown files. Defaults to the Docsify navigation sources.

.PARAMETER ConfigPath
    Path to the shared markdown-link-check configuration file.

.PARAMETER Quiet
    Suppress non-error output from markdown-link-check.

.PARAMETER ChangedFilesOnly
    Restrict validation to Markdown files changed relative to BaseBranch.

.PARAMETER BaseBranch
    Branch reference used by -ChangedFilesOnly to compute the changed-file set.

.PARAMETER ThrottleLimit
    Maximum number of files checked concurrently.

.EXAMPLE
    # Validate all markdown files in default paths
    ./Markdown-Link-Check.ps1

.EXAMPLE
    # Validate specific path with verbose output
    ./Markdown-Link-Check.ps1 -Path ".github" -Quiet:$false

.EXAMPLE
    # Validate only markdown files changed against the default base branch
    ./Markdown-Link-Check.ps1 -ChangedFilesOnly
    #>

[CmdletBinding()]
param(
    [string[]]$Path = @(
        ".",
        ".github",
        ".devcontainer"
    ),

    [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath 'markdown-link-check.config.json'),

    [switch]$Quiet,

    [switch]$ChangedFilesOnly,

    [string]$BaseBranch = 'origin/main',

    [ValidateRange(1, 32)]
    [int]$ThrottleLimit = 8
)

$ErrorActionPreference = 'Stop'

# Import LintingHelpers module
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'Modules/LintingHelpers.psm1') -Force
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../lib/Modules/CIHelpers.psm1') -Force

function Get-MarkdownTarget {
    <#
    .SYNOPSIS
        Resolves Markdown files to validate from provided path arguments.

    .DESCRIPTION
        Accepts files or directories, expanding directories to all tracked and
        untracked, nonignored Markdown files discovered recursively, and returns
        a sorted, unique list of absolute file paths for downstream validation.

    .PARAMETER InputPath
        Files or directories that may contain Markdown content.

    .PARAMETER ChangedFilesOnly
        Restrict the result to Markdown files changed relative to BaseBranch.

    .PARAMETER BaseBranch
        Branch reference used to compute the changed-file set.

    .OUTPUTS
        System.String[]
    #>
    param(
        [string[]]$InputPath,

        [switch]$ChangedFilesOnly,

        [string]$BaseBranch = 'origin/main'
    )

    $targets = @()
    $repoRoot = git rev-parse --show-toplevel 2>$null

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Not in a git repository, falling back to file system search"
        if ($ChangedFilesOnly) {
            Write-Warning "Changed-files-only mode requires a git repository; scanning all Markdown files"
        }
        # Fallback to original implementation if not in git repo
        foreach ($item in $InputPath) {
            if ([string]::IsNullOrWhiteSpace($item)) {
                continue
            }

            $resolved = Resolve-Path -LiteralPath $item -ErrorAction SilentlyContinue
            if (-not $resolved) {
                Write-Warning "Unable to resolve path: $item"
                continue
            }

            foreach ($resolvedPath in $resolved) {
                if (Test-Path -LiteralPath $resolvedPath -PathType Container) {
                    $targets += Get-ChildItem -LiteralPath $resolvedPath -Recurse -Include *.md |
                                Where-Object { -not $_.PSIsContainer } |
                                Select-Object -ExpandProperty FullName
                }
                else {
                    $targets += $resolvedPath.ProviderPath
                }
            }
        }
        return ($targets | Sort-Object -Unique)
    }

    Write-Verbose "Searching for tracked and untracked, nonignored markdown files..."
    Write-Verbose "Repository root: $repoRoot"

    # Repo-relative changed-file allowlist; $null means "no changed-file filtering".
    $changedSet = $null
    if ($ChangedFilesOnly) {
        $changedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($changed in @(Get-ChangedFilesFromGit -BaseBranch $BaseBranch -FileExtensions @('*.md'))) {
            [void]$changedSet.Add(($changed -replace '\\', '/'))
        }

        Write-Verbose "Changed markdown files detected against ${BaseBranch}: $($changedSet.Count)"
    }

    # Git-aware implementation
    foreach ($item in $InputPath) {
        if ([string]::IsNullOrWhiteSpace($item)) {
            continue
        }

        # Check if it's a specific file or directory
        if (Test-Path -Path $item -PathType Leaf) {
            # Specific file - check if it is tracked or untracked and nonignored.
            $absolutePath = (Resolve-Path $item).Path
            $relativePath = [System.IO.Path]::GetRelativePath($repoRoot, $absolutePath) -replace '\\', '/'
            $listed = git ls-files --cached --others --exclude-standard -- $relativePath 2>$null
            if ($LASTEXITCODE -ne 0) {
                throw "git ls-files failed while resolving '$item'."
            }

            if ($listed -and $item -like "*.md") {
                if ($null -eq $changedSet -or $changedSet.Contains($relativePath)) {
                    $targets += $absolutePath
                }
            }
            elseif (-not $listed) {
                Write-Warning "File is ignored by git: $item"
            }
        }
        elseif (Test-Path -Path $item -PathType Container) {
            # Directory - get all tracked and untracked, nonignored markdown files.
            $absolutePath = (Resolve-Path $item).Path
            $relativePath = [System.IO.Path]::GetRelativePath($repoRoot, $absolutePath) -replace '\\', '/'
            $prefix = if ($relativePath -eq '.') { '' } else { "$relativePath/" }

            Write-Verbose "Searching under: $(if ($prefix) { $prefix } else { '<repository root>' })"

            # Enumerate without a pathspec, then filter in PowerShell. Git pathspec
            # wildcards match a single path component here, so '<dir>/**/*.md' silently
            # skipped both nested files and files sitting directly in <dir>.
            $listedFiles = @(git ls-files --cached --others --exclude-standard 2>$null)
            if ($LASTEXITCODE -ne 0) {
                throw "git ls-files failed while searching '$item'."
            }

            $trackedFiles = $listedFiles |
                Where-Object { $_ -like '*.md' } |
                Where-Object { $prefix -eq '' -or $_.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) } |
                Where-Object { $_ -notlike 'scripts/tests/*fixtures/*' } |
                # Generated output; 490 of its 504 markdown files symlink to sources already checked.
                Where-Object { $_ -notlike 'plugins/*' } |
                Where-Object { $null -eq $changedSet -or $changedSet.Contains($_) }

            if ($trackedFiles) {
                foreach ($file in $trackedFiles) {
                    $fullPath = Join-Path $repoRoot $file
                    if (Test-Path -LiteralPath $fullPath) {
                        $targets += $fullPath
                    }
                }
            }
        }
        else {
            Write-Warning "Unable to resolve path: $item"
        }
    }

    Write-Verbose "Found $($targets.Count) tracked and untracked markdown files"
    return ($targets | Sort-Object -Unique)
}

function Get-RelativePrefix {
    <#
    .SYNOPSIS
        Builds a normalized relative prefix between two paths.

    .DESCRIPTION
        Computes the relative path from a source directory to a destination and
        enforces forward-slash separators with a trailing slash when required to
        produce consistent link prefixes.

    .PARAMETER FromPath
        The directory from which the relative path should be calculated.

    .PARAMETER ToPath
        The target path that should be expressed relative to the source.

    .OUTPUTS
        System.String
    #>
    param(
        [string]$FromPath,
        [string]$ToPath
    )

    $relative = [System.IO.Path]::GetRelativePath($FromPath, $ToPath)
    if ([string]::IsNullOrWhiteSpace($relative) -or $relative -eq '.') {
        return ''
    }

    $normalized = $relative -replace '\\', '/'
    if (-not $normalized.EndsWith('/')) {
        $normalized += '/'
    }

    return $normalized
}

function Split-MarkdownTargetBatch {
    <#
    .SYNOPSIS
        Splits Markdown targets into deterministic balanced batches.

    .DESCRIPTION
        Sorts the supplied target paths and distributes them across no more than
        the configured throttle limit. Each returned object preserves its file
        array as one pipeline item for parallel processing.

    .PARAMETER Target
        Repository-relative Markdown file paths to batch.

    .PARAMETER ThrottleLimit
        Maximum number of batches to create.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$Target,

        [ValidateRange(1, 32)]
        [int]$ThrottleLimit
    )

    $sortedTargets = @($Target | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object)
    if ($sortedTargets.Count -eq 0) {
        return
    }

    $batchCount = [Math]::Min($sortedTargets.Count, $ThrottleLimit)
    $baseSize = [Math]::Floor($sortedTargets.Count / $batchCount)
    $remainder = $sortedTargets.Count % $batchCount
    $offset = 0

    for ($index = 0; $index -lt $batchCount; $index++) {
        $batchSize = $baseSize + $(if ($index -lt $remainder) { 1 } else { 0 })
        $files = @($sortedTargets[$offset..($offset + $batchSize - 1)])
        [pscustomobject]@{
            Index = $index
            Files = $files
        }
        $offset += $batchSize
    }
}

function ConvertFrom-MarkdownLinkCheckReport {
    <#
    .SYNOPSIS
        Converts a batched JUnit report into per-file link-check results.

    .DESCRIPTION
        Matches each JUnit suite to an expected file through its full file
        property. Selective attribution is trusted only when suites and expected
        files form a one-to-one set; otherwise every expected file fails closed
        while links from suites that could be identified remain available.

    .PARAMETER ExpectedFile
        Repository-relative files supplied to one CLI invocation.

    .PARAMETER ReportContent
        JUnit XML emitted by markdown-link-check.

    .PARAMETER ExitCode
        Aggregate exit code from the batched CLI invocation.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$ExpectedFile,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$ReportContent,

        [int]$ExitCode = 0
    )

    $expectedFiles = @($ExpectedFile | Sort-Object)
    if ($expectedFiles.Count -eq 0) {
        return
    }

    $pathComparer = if ($IsWindows) {
        [System.StringComparer]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparer]::Ordinal
    }
    $expectedByNormalizedPath = [System.Collections.Generic.Dictionary[string, string]]::new($pathComparer)
    $linksByFile = @{}
    $failedByFile = @{}
    $reportTrusted = $true
    $reportError = $null

    foreach ($expected in $expectedFiles) {
        $normalized = $expected -replace '\\', '/'
        if ($expectedByNormalizedPath.ContainsKey($normalized)) {
            $reportTrusted = $false
        }
        else {
            $expectedByNormalizedPath.Add($normalized, $expected)
        }
        $linksByFile[$expected] = @()
        $failedByFile[$expected] = $false
    }

    try {
        if ([string]::IsNullOrWhiteSpace($ReportContent)) {
            throw 'The JUnit report was not created.'
        }

        [xml]$xml = $ReportContent
        $seenFiles = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
        foreach ($testSuite in @($xml.testsuites.testsuite)) {
            $fileProperties = @($testSuite.properties.property | Where-Object { $_.name -eq 'file' })
            if ($fileProperties.Count -ne 1 -or [string]::IsNullOrWhiteSpace($fileProperties[0].value)) {
                $reportTrusted = $false
                continue
            }

            $normalizedSuiteFile = ([string]$fileProperties[0].value) -replace '\\', '/'
            if (-not $expectedByNormalizedPath.ContainsKey($normalizedSuiteFile) -or -not $seenFiles.Add($normalizedSuiteFile)) {
                $reportTrusted = $false
                continue
            }

            $expected = $expectedByNormalizedPath[$normalizedSuiteFile]
            $links = foreach ($testCase in @($testSuite.testcase)) {
                if ($null -eq $testCase) {
                    continue
                }

                $properties = @($testCase.properties.property)
                [pscustomobject]@{
                    Url = ($properties | Where-Object { $_.name -eq 'url' } | Select-Object -First 1).value
                    Status = ($properties | Where-Object { $_.name -eq 'status' } | Select-Object -First 1).value
                    StatusCode = ($properties | Where-Object { $_.name -eq 'statusCode' } | Select-Object -First 1).value
                }
            }
            $linksByFile[$expected] = @($links)
            $failedByFile[$expected] = (
                [int]$testSuite.failures -gt 0 -or
                [int]$testSuite.errors -gt 0 -or
                @($links | Where-Object { $_.Status -in @('dead', 'error') }).Count -gt 0
            )
        }

        if ($seenFiles.Count -ne $expectedByNormalizedPath.Count) {
            $reportTrusted = $false
        }
    }
    catch {
        $reportTrusted = $false
        $reportError = $_.Exception.Message
    }

    $hasReportedFailure = @($failedByFile.Values | Where-Object { $_ }).Count -gt 0
    $unexplainedExit = $reportTrusted -and $ExitCode -ne 0 -and -not $hasReportedFailure

    foreach ($expected in $expectedFiles) {
        [pscustomobject]@{
            File = $expected
            Links = @($linksByFile[$expected])
            Failed = (-not $reportTrusted) -or $unexplainedExit -or $failedByFile[$expected]
            ParseFailed = -not $reportTrusted
            ReportError = $reportError
        }
    }
}

function Invoke-MarkdownLinkCheck {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [string[]]$Path,
        [string]$ConfigPath,
        [switch]$Quiet,
        [switch]$ChangedFilesOnly,
        [string]$BaseBranch = 'origin/main',
        [int]$ThrottleLimit = 8
    )

    $scriptRootParent = Split-Path -Path $PSScriptRoot -Parent
    $repoRootPath = Split-Path -Path $scriptRootParent -Parent
    $repoRoot = Resolve-Path -LiteralPath $repoRootPath
    $config = Resolve-Path -LiteralPath $ConfigPath -ErrorAction Stop

    $targetParams = @{ InputPath = $Path }
    if ($ChangedFilesOnly) {
        $targetParams['ChangedFilesOnly'] = $true
        $targetParams['BaseBranch'] = $BaseBranch
    }

    $filesToCheck = @(Get-MarkdownTarget @targetParams)

    if (-not $filesToCheck -or @($filesToCheck).Count -eq 0) {
        # An empty changed-file set is the expected outcome for pull requests that
        # touch no Markdown, so it reports a clean run instead of failing.
        if (-not $ChangedFilesOnly) {
            throw 'No markdown files were found to validate.'
        }

        Write-Output 'No changed markdown files to validate.'
    }

    $cliOverride = Get-Variable -Name MarkdownLinkCheckCliOverride -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($cliOverride) {
        $cli = [string]$cliOverride
    }
    else {
        $cli = Join-Path -Path $repoRoot.Path -ChildPath 'node_modules/.bin/markdown-link-check'
        if ($IsWindows) {
            $cli += '.cmd'
        }
    }

    if (-not (Test-Path -LiteralPath $cli)) {
        throw 'markdown-link-check is not installed. Run "npm install --save-dev markdown-link-check" first.'
    }

    $baseArguments = @('-c', $config.Path)
    if ($Quiet) {
        $baseArguments += '-q'
    }

    $failedFiles = @()
    $brokenLinks = @()
    $totalLinks = 0
    $totalFiles = $filesToCheck.Count
    $rootPath = $repoRoot.Path

    Push-Location $rootPath
    try {
        $relativeTargets = @($filesToCheck | ForEach-Object {
            [System.IO.Path]::GetRelativePath($rootPath, (Resolve-Path -LiteralPath $_))
        })
        $targetBatches = @(Split-MarkdownTargetBatch -Target $relativeTargets -ThrottleLimit $ThrottleLimit)

        $batchResults = @($targetBatches | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
            Set-Location -LiteralPath $using:rootPath
            $batch = $_

            $xmlFile = [System.IO.Path]::GetTempFileName() + '.xml'
            $output = $null
            $exitCode = 0
            $reportContent = $null
            $invocationError = $null
            try {
                $commandArgs = $using:baseArguments + @($batch.Files) + @('--reporters', 'default,junit', '--junit-output', $xmlFile)

                $output = & $using:cli @commandArgs 2>&1
                $exitCode = $LASTEXITCODE

                if (Test-Path $xmlFile) {
                    $reportContent = Get-Content $xmlFile -Raw -Encoding utf8
                }
            }
            catch {
                $invocationError = $_.Exception.Message
            }
            finally {
                if (Test-Path $xmlFile) {
                    Remove-Item $xmlFile -Force
                }
            }

            [pscustomobject]@{
                Index = $batch.Index
                Files = @($batch.Files)
                ExitCode = $exitCode
                Output = $output
                ReportContent = $reportContent
                InvocationError = $invocationError
            }
        })
    }
    finally {
        Pop-Location
    }

    $fileResults = @()
    foreach ($batchResult in ($batchResults | Sort-Object -Property Index)) {
        if (($VerbosePreference -eq 'Continue' -or $batchResult.ExitCode -ne 0) -and $null -ne $batchResult.Output) {
            Write-Host $batchResult.Output
        }

        $convertedResults = @(ConvertFrom-MarkdownLinkCheckReport `
            -ExpectedFile $batchResult.Files `
            -ReportContent $batchResult.ReportContent `
            -ExitCode $batchResult.ExitCode)
        if (@($convertedResults | Where-Object ParseFailed).Count -gt 0) {
            $reason = if ($batchResult.InvocationError) {
                $batchResult.InvocationError
            }
            elseif ($convertedResults[0].ReportError) {
                $convertedResults[0].ReportError
            }
            else {
                'The report did not contain one unique suite for every expected file.'
            }
            Write-Warning "Failed to parse or attribute XML output for batch $($batchResult.Index): $reason"
        }
        $fileResults += $convertedResults
    }

    foreach ($fileResult in ($fileResults | Sort-Object -Property File)) {
        $relative = $fileResult.File
        Write-Output "Checking $relative"

        foreach ($link in $fileResult.Links) {
            $totalLinks++

            # Display human-readable output if not quiet
            if (-not $Quiet) {
                if ($link.Status -eq 'alive') {
                    Write-Host "  ✓ $($link.Url)" -ForegroundColor Green
                }
                elseif ($link.Status -eq 'ignored') {
                    Write-Host "  / $($link.Url) (ignored)" -ForegroundColor Yellow
                }
                elseif ($link.Status -eq 'dead') {
                    Write-Host "  ✖ $($link.Url) → Status: $($link.StatusCode)" -ForegroundColor Red
                }
            }

            # Process broken links
            if ($link.Status -eq 'dead') {
                $brokenLinks += @{
                    File = $relative
                    Link = $link.Url
                    Status = "$($link.StatusCode)"
                }

                Write-CIAnnotation -Message "Broken link: $($link.Url) (Status: $($link.StatusCode))" -Level Error -File $relative
            }
        }

        if ($fileResult.Failed -and $failedFiles -notcontains $relative) {
            $failedFiles += $relative
        }
    }

    # Create logs directory and export results
    $logsDir = Join-Path -Path $repoRoot.Path -ChildPath 'logs'
    if (-not (Test-Path $logsDir)) {
        New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
    }

    $results = @{
        Timestamp = Get-StandardTimestamp
        script = 'markdown-link-check'
        summary = @{
            total_files = $totalFiles
            files_with_broken_links = $failedFiles.Count
            total_links_checked = $totalLinks
            total_broken_links = $brokenLinks.Count
        }
        broken_links = $brokenLinks
    }

    $resultsPath = Join-Path -Path $logsDir -ChildPath 'markdown-link-check-results.json'
    $results | ConvertTo-Json -Depth 10 | Set-Content -Path $resultsPath -Encoding UTF8

    # Generate GitHub step summary
    if ($failedFiles.Count -gt 0) {
        $summaryContent = @"
## ❌ Markdown Link Check Failed

**Files with broken links:** $($failedFiles.Count) / $totalFiles
**Total broken links:** $($brokenLinks.Count)

### Broken Links

| File | Broken Link |
|------|-------------|
"@

        foreach ($link in $brokenLinks) {
            $safeFile = if ((Get-CIPlatform) -eq 'azdo') {
                ConvertTo-AzureDevOpsEscaped -Value $link.File
            } else { $link.File }
            $safeLink = if ((Get-CIPlatform) -eq 'azdo') {
                ConvertTo-AzureDevOpsEscaped -Value $link.Link
            } else { $link.Link }
            $summaryContent += "`n| ``$safeFile`` | ``$safeLink`` |"
        }

        $summaryContent += @"


### How to Fix

1. Review the broken links listed above
2. Update or remove invalid links
3. Re-run the link check to verify fixes

For more information, see the [markdown-link-check documentation](https://github.com/tcort/markdown-link-check).
"@

        Write-CIStepSummary -Content $summaryContent
        Set-CIEnv -Name "MARKDOWN_LINK_CHECK_FAILED" -Value "true"

        throw ("markdown-link-check reported failures for: {0}" -f ($failedFiles -join ', '))
    }
    else {
        $summaryContent = @"
## ✅ Markdown Link Check Passed

**Files checked:** $totalFiles
**Total links checked:** $totalLinks
**Broken links:** 0

Great job! All markdown links are valid. 🎉
"@

        Write-CIStepSummary -Content $summaryContent
        Write-Output 'markdown-link-check completed successfully.'
    }
}

#region Main Execution
if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-MarkdownLinkCheck -Path $Path -ConfigPath $ConfigPath -Quiet:$Quiet `
            -ChangedFilesOnly:$ChangedFilesOnly -BaseBranch $BaseBranch -ThrottleLimit $ThrottleLimit
        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue "Markdown-Link-Check failed: $($_.Exception.Message)"
        Write-CIAnnotation -Message $_.Exception.Message -Level Error
        exit 1
    }
}
#endregion Main Execution
