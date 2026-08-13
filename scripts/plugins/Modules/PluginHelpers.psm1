# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT

# PluginHelpers.psm1
#
# Purpose: Shared functions for the Copilot CLI plugin generation pipeline.
# Author: HVE Core Team

#Requires -Version 7.4

Import-Module (Join-Path $PSScriptRoot '../../lib/Modules/ArtifactHelpers.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../../lib/Modules/MarketplaceHelpers.psm1') -Force

# ---------------------------------------------------------------------------
# Pure Functions (no file system side effects)
# ---------------------------------------------------------------------------

function New-PluginManifestContent {
    <#
    .SYNOPSIS
    Generates root plugin.json content as an ordered hashtable.

    .DESCRIPTION
    Creates the runtime manifest mirroring the standard catalog recipe: name,
    description, version, provenance, and component declarations for agents,
    commands, rules, skills, and hooks. Every component value is a
    manifest-relative reference to canonical repository content, so nothing is
    copied beneath a package root. The x-hve metadata overlay and catalog
    source metadata are catalog-only and never reach a generated manifest.

    .PARAMETER PackageName
    The package identifier used as the plugin name.

    .PARAMETER Description
    A short description of the plugin.

    .PARAMETER Version
    Semantic version string from the repository package.json.

    .PARAMETER Author
    Optional provenance author.

    .PARAMETER Homepage
    Optional provenance homepage URL.

    .PARAMETER Repository
    Optional provenance repository URL.

    .PARAMETER License
    Optional provenance license identifier.

    .PARAMETER Keywords
    Optional provenance keywords.

    .PARAMETER AgentPaths
    Optional. Manifest-relative references to canonical agent files.

    .PARAMETER CommandPaths
    Optional. Manifest-relative references to canonical prompt files.

    .PARAMETER RulePaths
    Optional. Manifest-relative references to canonical instruction files.

    .PARAMETER SkillPaths
    Optional. Manifest-relative references to canonical skill directories.

    .PARAMETER HookPaths
    Optional. Manifest-relative references to canonical hook JSON files.

    .OUTPUTS
    [hashtable] Plugin manifest with name, description, version, provenance,
    and component reference keys.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName,

        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [System.Collections.IDictionary]$Author,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Homepage,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Repository,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$License,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$Keywords,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$AgentPaths,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$CommandPaths,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$RulePaths,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$SkillPaths,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$HookPaths
    )

    $manifest = [ordered]@{
        name        = $PackageName
        description = $Description
        version     = $Version
    }

    if ($Author -and $Author.Contains('name') -and -not [string]::IsNullOrWhiteSpace([string]$Author['name'])) {
        $manifest['author'] = $Author
    }

    foreach ($provenance in @(
            @{ Key = 'homepage'; Value = $Homepage },
            @{ Key = 'repository'; Value = $Repository },
            @{ Key = 'license'; Value = $License }
        )) {
        if (-not [string]::IsNullOrWhiteSpace($provenance.Value)) {
            $manifest[$provenance.Key] = $provenance.Value
        }
    }

    if ($Keywords -and $Keywords.Count -gt 0) {
        $manifest['keywords'] = @($Keywords)
    }

    # Emit explicit reference arrays when provided; each entry names one
    # canonical artifact so a package never claims a whole shared directory.
    if ($AgentPaths -and $AgentPaths.Count -gt 0) {
        $manifest['agents'] = @($AgentPaths | Sort-Object)
    }

    if ($CommandPaths -and $CommandPaths.Count -gt 0) {
        $manifest['commands'] = @($CommandPaths | Sort-Object)
    }

    if ($RulePaths -and $RulePaths.Count -gt 0) {
        $manifest['rules'] = @($RulePaths | Sort-Object)
    }

    if ($SkillPaths -and $SkillPaths.Count -gt 0) {
        $manifest['skills'] = @($SkillPaths | Sort-Object)
    }

    if ($HookPaths -and $HookPaths.Count -gt 0) {
        # The CLI `hooks` field is a single hooks-config file path (or inline
        # object), not an array. Emit the lone path as a string; warn when more
        # than one hook manifest is registered since only one can be referenced.
        $sortedHooks = @($HookPaths | Sort-Object)
        if ($sortedHooks.Count -gt 1) {
            Write-Warning "Plugin '$PackageName' declares $($sortedHooks.Count) hook manifests; the CLI references only one. Using '$($sortedHooks[0])'."
        }
        $manifest['hooks'] = $sortedHooks[0]
    }

    return $manifest
}

function New-PluginReleaseLocator {
    <#
    .SYNOPSIS
    Builds a validated immutable release locator for an active channel tag.

    .DESCRIPTION
    Produces the repository and immutable ref addressing the active release tag
    for a channel. Stable addresses 'v<version>' and PreRelease addresses
    'prerelease-v<version>'. Accepts an explicit tag in the requested channel's
    namespace or derives one from a package version.

    The locator is pathless: it addresses the repository at the release tag
    rather than a projected package tree. Legacy tag namespaces, cross-channel
    tags, branch names, and commit-SHA locators are refused.

    .PARAMETER Tag
    Explicit immutable release tag in the requested channel's namespace.

    .PARAMETER Version
    Semantic version from which the channel release tag is derived.

    .PARAMETER Channel
    Release channel whose tag namespace the locator addresses.

    .PARAMETER Repo
    Source repository in 'owner/name' form.

    .OUTPUTS
    [hashtable] Locator with Repo and Ref keys.

    .EXAMPLE
    New-PluginReleaseLocator -Version '1.2.3' -Channel Stable

    .EXAMPLE
    New-PluginReleaseLocator -Tag 'prerelease-v1.2.3' -Channel PreRelease
    #>
    [CmdletBinding(DefaultParameterSetName = 'Tag')]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Tag')]
        [AllowEmptyString()]
        [string]$Tag,

        [Parameter(Mandatory = $true, ParameterSetName = 'Version')]
        [AllowEmptyString()]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Stable', 'PreRelease')]
        [string]$Channel,

        [Parameter(Mandatory = $false)]
        [string]$Repo = 'microsoft/hve-core'
    )

    $semVerPattern = '\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?'
    $tagPrefix = if ($Channel -eq 'PreRelease') { 'prerelease-v' } else { 'v' }

    if ($PSCmdlet.ParameterSetName -eq 'Version') {
        if ($Version -cnotmatch "^$semVerPattern$") {
            throw "Release version '$Version' is not a semantic version."
        }
        $Tag = "$tagPrefix$Version"
    }

    if ($Tag -match '^[0-9a-fA-F]{40}$') {
        throw "Release locator '$Tag' is a commit sha. Sha-pinned release locators are not supported; use the immutable '$tagPrefix<version>' tag."
    }

    if ($Tag -cnotmatch "^$tagPrefix$semVerPattern$") {
        throw "Release locator '$Tag' must use the immutable $Channel '$tagPrefix<version>' tag form."
    }

    if ($Repo -notmatch '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$') {
        throw "Release repository '$Repo' must use 'owner/name' form."
    }

    return @{
        Repo = $Repo
        Ref  = $Tag
    }
}

function New-GenerateResult {
    <#
    .SYNOPSIS
    Creates a standardized result object.

    .DESCRIPTION
    Returns a hashtable representing the outcome of a plugin generation run
    with success status, plugin count, and optional error message.

    .PARAMETER Success
    Whether the operation succeeded.

    .PARAMETER PluginCount
    Number of plugins generated.

    .PARAMETER ErrorMessage
    Optional error message when Success is $false.

    .OUTPUTS
    [hashtable] Result with Success, PluginCount, and ErrorMessage keys.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Success,

        [Parameter(Mandatory = $true)]
        [int]$PluginCount,

        [Parameter(Mandatory = $false)]
        [string]$ErrorMessage = ''
    )

    return @{
        Success      = $Success
        PluginCount  = $PluginCount
        ErrorMessage = $ErrorMessage
    }
}

# ---------------------------------------------------------------------------
# I/O Functions (file system operations)
# ---------------------------------------------------------------------------

function Get-PluginOutputFileIndex {
    <#
    .SYNOPSIS
    Indexes every regular file in a plugin output tree by relative path.

    .DESCRIPTION
    Returns forward-slash relative paths mapped to SHA256 content hashes so two
    generated trees can be compared by exact path set and bytes. A missing root
    yields an empty index, which makes an absent tracked tree read as complete
    drift rather than a silent pass.

    .PARAMETER Root
    Absolute path to a plugin output root.

    .OUTPUTS
    [hashtable] Relative path to SHA256 hash.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Root
    )

    $index = @{}
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return $index
    }

    $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
    foreach ($file in Get-ChildItem -LiteralPath $resolvedRoot -File -Recurse -Force) {
        $relative = [System.IO.Path]::GetRelativePath($resolvedRoot, $file.FullName) -replace '\\', '/'
        $index[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    return $index
}

function Compare-PluginOutputTree {
    <#
    .SYNOPSIS
    Compares an expected plugin output tree with a tracked one.

    .DESCRIPTION
    Reports every relative path present in only one tree and every shared path
    whose bytes differ. Neither tree is modified, so the result is usable as a
    non-mutating drift verdict.

    .PARAMETER ExpectedRoot
    Absolute path to the freshly generated expected tree.

    .PARAMETER ActualRoot
    Absolute path to the tracked repository tree.

    .OUTPUTS
    [hashtable] Missing, Extra, Changed (sorted relative paths) and HasDrift.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ExpectedRoot,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ActualRoot
    )

    $expected = Get-PluginOutputFileIndex -Root $ExpectedRoot
    $actual = Get-PluginOutputFileIndex -Root $ActualRoot

    $missing = [System.Collections.Generic.List[string]]::new()
    $changed = [System.Collections.Generic.List[string]]::new()
    foreach ($relative in $expected.Keys) {
        if (-not $actual.ContainsKey($relative)) {
            $missing.Add($relative)
        }
        elseif ($actual[$relative] -ne $expected[$relative]) {
            $changed.Add($relative)
        }
    }

    $extra = [System.Collections.Generic.List[string]]::new()
    foreach ($relative in $actual.Keys) {
        if (-not $expected.ContainsKey($relative)) {
            $extra.Add($relative)
        }
    }

    return @{
        Missing  = [string[]]@($missing | Sort-Object)
        Extra    = [string[]]@($extra | Sort-Object)
        Changed  = [string[]]@($changed | Sort-Object)
        HasDrift = (($missing.Count + $extra.Count + $changed.Count) -gt 0)
    }
}

function Get-PluginTrackedPathIndex {
    <#
    .SYNOPSIS
    Builds the git-tracked path allowlist for a repository working tree.

    .DESCRIPTION
    Reads the repository-relative paths recorded in the git index. Release
    evidence digests only these paths, so untracked working-tree content such
    as virtual environments, dependency directories, and bytecode caches can
    never enter a digest. Throws when the directory is not a git working tree,
    because digesting without the allowlist would silently absorb that residue.

    .PARAMETER RepoRoot
    Absolute path to the repository working tree.

    .OUTPUTS
    [hashtable] Index with RepoRoot, Paths (ordered list), and Lookup (set) keys.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($RepoRoot)

    # core.quotePath=false keeps non-ASCII paths raw instead of octal-escaped.
    $gitArgs = @('-C', $resolvedRoot, '-c', 'core.quotePath=false', 'ls-files', '--cached', '--full-name')
    $output = & git @gitArgs 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to enumerate git-tracked paths in '$resolvedRoot' (git ls-files exit code $LASTEXITCODE)."
    }

    $paths = [System.Collections.Generic.List[string]]::new()
    $lookup = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    foreach ($line in @($output)) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        $normalized = ([string]$line) -replace '\\', '/'
        if ($lookup.Add($normalized)) {
            $paths.Add($normalized)
        }
    }

    return @{
        RepoRoot = $resolvedRoot
        Paths    = $paths
        Lookup   = $lookup
    }
}

function Write-PluginManifest {
    <#
    .SYNOPSIS
    Writes the sole runtime manifest for one catalog package.

    .DESCRIPTION
    Serializes plugins/<package>/plugin.json from the resolved catalog recipe.
    Component values are the manifest-relative references the catalog declares,
    so the runtime reads canonical repository content in place and the package
    root carries no copied payload. Any other entry already present in the
    package root is removed, keeping the delivered inventory to one manifest.

    .PARAMETER Entry
    Marketplace catalog entry describing package identity and provenance.

    .PARAMETER Items
    Resolved recipe items with Kind, Field, PackagePath, SourcePath, and
    Maturity keys.

    .PARAMETER PluginsDir
    Absolute path to the root plugins output directory.

    .PARAMETER Version
    Semantic version string from the repository package.json.

    .PARAMETER DryRun
    When specified, logs actions without creating or removing files.

    .OUTPUTS
    [hashtable] Result with Success, ManifestPath, AgentCount, CommandCount,
    InstructionCount, SkillCount, and HookCount keys.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Entry,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [hashtable[]]$Items,

        [Parameter(Mandatory = $true)]
        [string]$PluginsDir,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $false)]
        [switch]$DryRun
    )

    $packageName = [string]$Entry['name']
    $pluginRoot = Join-Path -Path $PluginsDir -ChildPath $packageName
    $manifestPath = Join-Path -Path $pluginRoot -ChildPath 'plugin.json'

    $references = @{
        agent       = [System.Collections.Generic.List[string]]::new()
        prompt      = [System.Collections.Generic.List[string]]::new()
        instruction = [System.Collections.Generic.List[string]]::new()
        skill       = [System.Collections.Generic.List[string]]::new()
        hook        = [System.Collections.Generic.List[string]]::new()
    }

    foreach ($item in $Items) {
        $kind = [string]$item.Kind
        if (-not $references.ContainsKey($kind)) {
            Write-Warning "Package '$packageName' declares unsupported component kind '$kind'."
            continue
        }
        $reference = [string]$item.PackagePath
        if (-not $references[$kind].Contains($reference)) {
            $references[$kind].Add($reference)
        }
    }

    $manifestArgs = @{
        PackageName  = $packageName
        Description  = [string]$Entry['description']
        Version      = $Version
        AgentPaths   = [string[]]$references.agent.ToArray()
        CommandPaths = [string[]]$references.prompt.ToArray()
        RulePaths    = [string[]]$references.instruction.ToArray()
        SkillPaths   = [string[]]$references.skill.ToArray()
        HookPaths    = [string[]]$references.hook.ToArray()
    }
    if ($Entry.Contains('author') -and $Entry['author'] -is [System.Collections.IDictionary]) {
        $manifestArgs['Author'] = $Entry['author']
    }
    foreach ($provenance in @('homepage', 'repository', 'license')) {
        if ($Entry.Contains($provenance) -and -not [string]::IsNullOrWhiteSpace([string]$Entry[$provenance])) {
            $manifestArgs[[cultureinfo]::InvariantCulture.TextInfo.ToTitleCase($provenance)] = [string]$Entry[$provenance]
        }
    }
    if ($Entry.Contains('keywords') -and $Entry['keywords']) {
        $manifestArgs['Keywords'] = @($Entry['keywords'] | ForEach-Object { [string]$_ })
    }

    $manifest = New-PluginManifestContent @manifestArgs

    if ($DryRun) {
        Write-Verbose "DryRun: Would write plugin.json at $manifestPath"
    }
    else {
        if (-not (Test-Path -LiteralPath $pluginRoot -PathType Container)) {
            New-Item -ItemType Directory -Path $pluginRoot -Force | Out-Null
        }
        Set-ContentIfChanged -Path $manifestPath -Value ($manifest | ConvertTo-Json -Depth 10) | Out-Null

        # The manifest is the only file a package root delivers, so anything
        # else present is retired rather than left as an undeclared payload.
        foreach ($existing in Get-ChildItem -LiteralPath $pluginRoot -Force) {
            if ($existing.PSIsContainer -or -not [string]::Equals($existing.Name, 'plugin.json', [System.StringComparison]::Ordinal)) {
                Remove-Item -LiteralPath $existing.FullName -Recurse -Force -ErrorAction Stop
                Write-Verbose "Removed non-manifest package entry: $($existing.FullName)"
            }
        }
    }

    return @{
        Success          = $true
        ManifestPath     = $manifestPath
        AgentCount       = $references.agent.Count
        CommandCount     = $references.prompt.Count
        InstructionCount = $references.instruction.Count
        SkillCount       = $references.skill.Count
        HookCount        = $references.hook.Count
    }
}

Export-ModuleMember -Function @(
    'Compare-PluginOutputTree',
    'Get-PluginOutputFileIndex',
    'Get-PluginTrackedPathIndex',
    'New-GenerateResult',
    'New-PluginManifestContent',
    'New-PluginReleaseLocator',
    'Write-PluginManifest'
)
