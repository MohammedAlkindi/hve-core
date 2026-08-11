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

    $cli = Join-Path -Path $repoRoot.Path -ChildPath 'node_modules/.bin/markdown-link-check'
    if ($IsWindows) {
        $cli += '.cmd'
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

        # Each file is an independent CLI invocation, so they run concurrently and
        # every result is aggregated serially afterwards to keep output ordered and
        # to keep CI annotations on the caller's runspace.
        $fileResults = @($relativeTargets | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
            Set-Location -LiteralPath $using:rootPath
            $relative = $_

            # Create temp file for XML output
            $xmlFile = [System.IO.Path]::GetTempFileName() + '.xml'
            $links = @()
            $output = $null
            $exitCode = 0
            $parseFailed = $false
            try {
                $commandArgs = $using:baseArguments + @($relative, '--reporters', 'default,junit', '--junit-output', $xmlFile)

                # Run markdown-link-check with XML output and capture output
                $output = & $using:cli @commandArgs 2>&1
                $exitCode = $LASTEXITCODE

                # Parse XML output
                if (Test-Path $xmlFile) {
                    [xml]$xml = Get-Content $xmlFile -Raw -Encoding utf8

                    foreach ($testsuite in $xml.testsuites.testsuite) {
                        foreach ($testcase in $testsuite.testcase) {
                            $links += [pscustomobject]@{
                                Url        = ($testcase.properties.property | Where-Object { $_.name -eq 'url' }).value
                                Status     = ($testcase.properties.property | Where-Object { $_.name -eq 'status' }).value
                                StatusCode = ($testcase.properties.property | Where-Object { $_.name -eq 'statusCode' }).value
                            }
                        }
                    }
                }
            }
            catch {
                Write-Warning "Failed to parse XML output for $relative : $_"
                $parseFailed = $true
            }
            finally {
                if (Test-Path $xmlFile) {
                    Remove-Item $xmlFile -Force
                }
            }

            [pscustomobject]@{
                File        = $relative
                ExitCode    = $exitCode
                Links       = $links
                Output      = $output
                ParseFailed = $parseFailed
            }
        })
    }
    finally {
        Pop-Location
    }

    foreach ($fileResult in ($fileResults | Sort-Object -Property File)) {
        $relative = $fileResult.File
        Write-Output "Checking $relative"

        # Display output if verbose mode or if there were errors
        if (($VerbosePreference -eq 'Continue' -or $fileResult.ExitCode -ne 0) -and $null -ne $fileResult.Output) {
            Write-Host $fileResult.Output
        }

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

        # A malformed report is treated as a failure even when the CLI exits zero.
        if (($fileResult.ExitCode -ne 0 -or $fileResult.ParseFailed) -and $failedFiles -notcontains $relative) {
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
