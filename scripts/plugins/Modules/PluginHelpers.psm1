# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT

# PluginHelpers.psm1
#
# Purpose: Shared functions for the Copilot CLI plugin generation pipeline.
# Author: HVE Core Team

#Requires -Version 7.4

Import-Module (Join-Path $PSScriptRoot '../../collections/Modules/CollectionHelpers.psm1') -Force

# Marker pair delimiting the optional package notice inside a durable package
# document. The notice renders in the generated README immediately after the
# package description rather than inside the Overview section.
$script:PluginNoticeBeginMarker = '<!-- BEGIN PACKAGE NOTICE -->'
$script:PluginNoticeEndMarker = '<!-- END PACKAGE NOTICE -->'

# ---------------------------------------------------------------------------
# Pure Functions (no file system side effects)
# ---------------------------------------------------------------------------

function Get-PluginItemName {
    <#
    .SYNOPSIS
    Returns an artifact filename, stripping kind suffixes for CLI display.

    .DESCRIPTION
    Validated entry point for filename handling in the plugin pipeline.
    Agent and prompt files have their kind suffix (.agent.md, .prompt.md)
    replaced with .md so the CLI title is clean. Instruction files keep
    their suffix because VS Code discovery filters on *.instructions.md.

    .PARAMETER FileName
    The original filename (e.g. rpi-agent.agent.md).

    .PARAMETER Kind
    The artifact kind: agent, prompt, instruction, or skill.

    .OUTPUTS
    [string] The processed filename.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('agent', 'prompt', 'instruction', 'skill', 'hook')]
        [string]$Kind
    )

    switch ($Kind) {
        'agent'       { return $FileName -replace '\.agent\.md$', '.md' }
        'prompt'      { return $FileName -replace '\.prompt\.md$', '.md' }
        'instruction' { return $FileName }
        'skill'       { return $FileName }
        'hook'        { return $FileName }
    }
}

function Get-PluginItemSubpath {
    <#
    .SYNOPSIS
    Extracts the subdirectory path between the kind root prefix and the leaf.

    .DESCRIPTION
    Given a repo-relative item path and its kind, strips the known prefix
    (e.g. .github/agents/) and returns the intermediate directory segments.
    Returns empty string when the item is directly under the kind root.

    .PARAMETER Path
    Repo-relative item path (e.g. .github/agents/hve-core/rpi-agent.agent.md).

    .PARAMETER Kind
    The artifact kind: agent, prompt, instruction, or skill.

    .OUTPUTS
    [string] Intermediate subdirectory path, or empty string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet('agent', 'prompt', 'instruction', 'skill', 'hook')]
        [string]$Kind
    )

    $prefixMap = @{
        'agent'       = '.github/agents/'
        'prompt'      = '.github/prompts/'
        'instruction' = '.github/instructions/'
        'skill'       = '.github/skills/'
        'hook'        = '.github/hooks/'
    }

    $prefix = $prefixMap[$Kind]
    $normalized = $Path -replace '\\', '/'

    if (-not $normalized.StartsWith($prefix)) {
        return ''
    }

    $relative = $normalized.Substring($prefix.Length)
    $parts = $relative -split '/'

    if ($parts.Count -gt 1) {
        return ($parts[0..($parts.Count - 2)] -join '/')
    }

    return ''
}

function Get-PluginSubdirectory {
    <#
    .SYNOPSIS
    Returns the plugin subdirectory name for an artifact kind.

    .DESCRIPTION
    Maps a collection item kind to the corresponding subdirectory name
    within the plugin directory structure.

    .PARAMETER Kind
    The artifact kind: agent, prompt, instruction, or skill.

    .OUTPUTS
    [string] The standard component directory name (agents, commands, rules, skills, or hooks).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('agent', 'prompt', 'instruction', 'skill', 'hook')]
        [string]$Kind
    )

    switch ($Kind) {
        'agent' { return 'agents' }
        'prompt' { return 'commands' }
        'instruction' { return 'rules' }
        'skill' { return 'skills' }
        'hook' { return 'hooks' }
    }
}

function Get-MarketplaceComponentFieldMap {
    <#
    .SYNOPSIS
    Returns the standard marketplace component fields and their artifact kinds.

    .DESCRIPTION
    Standard component membership fields are the sole authority for what a
    package contains. The map is the single source of truth for the accepted
    field names and the artifact kind each one carries, so validation,
    generation, and root-manifest emission cannot disagree.

    .OUTPUTS
    [System.Collections.Specialized.OrderedDictionary] Field name to artifact kind.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    return [ordered]@{
        agents   = 'agent'
        commands = 'prompt'
        rules    = 'instruction'
        skills   = 'skill'
        hooks    = 'hook'
    }
}

function Get-MarketplaceMetadataKey {
    <#
    .SYNOPSIS
    Returns the closed key set permitted inside a marketplace entry x-hve overlay.

    .DESCRIPTION
    The x-hve extension carries entry-level metadata only. It never owns
    component membership, so any key outside this set is a contract violation.

    .OUTPUTS
    [string[]] Permitted x-hve keys.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return , @('maturity', 'componentMaturity', 'documentation', 'aggregate')
}

function Get-MarketplaceComponentSourceRoot {
    <#
    .SYNOPSIS
    Returns the canonical repository root and suffix for each component field.

    .DESCRIPTION
    Standard component paths are both public manifest data and the build
    recipe, so the mapping between a package-relative path and its canonical
    repository source must be deterministic in both directions. This map is the
    single place that records the repository root and the filename suffix each
    field uses on either side of that mapping.

    .OUTPUTS
    [System.Collections.Specialized.OrderedDictionary] Field name to root/suffix descriptor.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    return [ordered]@{
        agents   = @{ Kind = 'agent'; SourceRoot = '.github/agents'; SourceSuffix = '.agent.md'; PackageSuffix = '.md' }
        commands = @{ Kind = 'prompt'; SourceRoot = '.github/prompts'; SourceSuffix = '.prompt.md'; PackageSuffix = '.md' }
        rules    = @{ Kind = 'instruction'; SourceRoot = '.github/instructions'; SourceSuffix = '.instructions.md'; PackageSuffix = '.instructions.md' }
        skills   = @{ Kind = 'skill'; SourceRoot = '.github/skills'; SourceSuffix = ''; PackageSuffix = '' }
        hooks    = @{ Kind = 'hook'; SourceRoot = '.github/hooks'; SourceSuffix = '.json'; PackageSuffix = '.json' }
    }
}

function Get-MarketplaceComponentField {
    <#
    .SYNOPSIS
    Returns the standard component field name that carries an artifact kind.

    .PARAMETER Kind
    The artifact kind: agent, prompt, instruction, skill, or hook.

    .OUTPUTS
    [string] Standard component field name.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('agent', 'prompt', 'instruction', 'skill', 'hook')]
        [string]$Kind
    )

    return Get-PluginSubdirectory -Kind $Kind
}

function Get-MarketplacePackagePath {
    <#
    .SYNOPSIS
    Projects a canonical repository source path to its standard component path.

    .DESCRIPTION
    Produces the package-relative path a catalog entry declares for a source
    artifact. The projection reuses the plugin subdirectory, subpath, and
    filename primitives so the catalog recipe and the materialized package
    layout cannot disagree.

    .PARAMETER SourcePath
    Repository-relative source path (for example .github/agents/ado/x.agent.md).

    .PARAMETER Kind
    The artifact kind carried by the source path.

    .OUTPUTS
    [string] Package-relative component path.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [ValidateSet('agent', 'prompt', 'instruction', 'skill', 'hook')]
        [string]$Kind
    )

    $normalized = ($SourcePath -replace '\\', '/').TrimEnd('/')
    $field = Get-PluginSubdirectory -Kind $Kind
    $roots = Get-MarketplaceComponentSourceRoot
    $expectedRoot = "$($roots[$field].SourceRoot)/"

    if (-not $normalized.StartsWith($expectedRoot, [System.StringComparison]::Ordinal)) {
        throw "Source path '$SourcePath' is not under the canonical '$($roots[$field].SourceRoot)' root for kind '$Kind'."
    }

    $leaf = Get-PluginItemName -FileName (Split-Path -Leaf $normalized) -Kind $Kind
    $subpath = Get-PluginItemSubpath -Path $normalized -Kind $Kind

    if ($subpath) {
        return "$field/$subpath/$leaf"
    }

    return "$field/$leaf"
}

function Resolve-MarketplaceComponentSource {
    <#
    .SYNOPSIS
    Resolves a standard component path back to its canonical repository source.

    .DESCRIPTION
    Inverse of Get-MarketplacePackagePath. The catalog declares package-relative
    membership, and generation materializes those declarations from canonical
    repository sources, so this mapping is the only permitted way to locate the
    source content for a declared component. Nothing is discovered by scanning
    the filesystem for undeclared artifacts.

    .PARAMETER PackagePath
    Package-relative component path (for example agents/ado/x.md).

    .PARAMETER Field
    Standard component field the path was declared under.

    .OUTPUTS
    [hashtable] Kind, PackagePath, and SourcePath for the declared component.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackagePath,

        [Parameter(Mandatory = $true)]
        [ValidateSet('agents', 'commands', 'rules', 'skills', 'hooks')]
        [string]$Field
    )

    $resolved = Resolve-MarketplaceComponentPath -Path $PackagePath
    if ($resolved.Error) {
        throw "Component field '$Field': $($resolved.Error)"
    }

    $normalized = $resolved.Path
    $prefix = "$Field/"
    if (-not $normalized.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
        throw "Component path '$PackagePath' must start with the '$Field/' package directory."
    }

    $descriptor = (Get-MarketplaceComponentSourceRoot)[$Field]
    $relative = $normalized.Substring($prefix.Length)

    if ($descriptor.PackageSuffix) {
        if (-not $relative.EndsWith($descriptor.PackageSuffix, [System.StringComparison]::Ordinal)) {
            throw "Component path '$PackagePath' must end with '$($descriptor.PackageSuffix)'."
        }
        $stem = $relative.Substring(0, $relative.Length - $descriptor.PackageSuffix.Length)
        $relative = "$stem$($descriptor.SourceSuffix)"
    }

    return @{
        Kind        = $descriptor.Kind
        PackagePath = $normalized
        SourcePath  = "$($descriptor.SourceRoot)/$relative"
    }
}

function Get-MarketplaceCatalog {
    <#
    .SYNOPSIS
    Loads the marketplace catalog as the sole package-definition input.

    .PARAMETER Path
    Absolute path to a marketplace.json catalog.

    .OUTPUTS
    [hashtable] Parsed catalog.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Marketplace catalog not found: $Path"
    }

    $catalog = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
    if ($null -eq $catalog -or -not $catalog.Contains('plugins')) {
        throw "Marketplace catalog '$Path' does not declare a plugins array."
    }

    return $catalog
}

function Get-MarketplacePackageRecipe {
    <#
    .SYNOPSIS
    Projects one catalog entry into a channel-filtered, ordered build recipe.

    .DESCRIPTION
    Standard component fields own membership and x-hve.componentMaturity
    carries the per-component maturity overlay, so the recipe applies the
    channel maturity policy to declared paths only. Removed components are
    tombstones: they stay available to the catalog for maturity policy but are
    never eligible for materialization. Output is ordered by field then path so
    generation is deterministic without display configuration.

    .PARAMETER Entry
    One marketplace plugin entry.

    .PARAMETER Channel
    Release channel controlling eligible component maturities.

    .OUTPUTS
    [hashtable[]] Items with Kind, Field, PackagePath, SourcePath, and Maturity.
    #>
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Entry,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Stable', 'PreRelease')]
        [string]$Channel
    )

    $allowed = if ($Channel -eq 'Stable') { @('stable') } else { @('stable', 'preview', 'experimental') }
    $componentMaturity = @{}
    if ($Entry.Contains('x-hve') -and $Entry['x-hve'] -is [System.Collections.IDictionary]) {
        $overlay = $Entry['x-hve']
        if ($overlay.Contains('componentMaturity') -and $overlay['componentMaturity'] -is [System.Collections.IDictionary]) {
            foreach ($key in $overlay['componentMaturity'].Keys) {
                $componentMaturity[[string]$key] = [string]$overlay['componentMaturity'][$key]
            }
        }
    }

    $items = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($field in (Get-MarketplaceComponentFieldMap).Keys) {
        if (-not $Entry.Contains($field) -or $null -eq $Entry[$field]) {
            continue
        }

        $declared = @($Entry[$field]) | Sort-Object -Unique
        foreach ($packagePath in $declared) {
            $component = Resolve-MarketplaceComponentSource -PackagePath ([string]$packagePath) -Field $field
            $maturity = if ($componentMaturity.ContainsKey($component.PackagePath)) {
                Resolve-StrictSafeMaturity -Maturity $componentMaturity[$component.PackagePath] -Source "marketplace entry '$($Entry['name'])' component '$($component.PackagePath)'"
            }
            else {
                'stable'
            }

            if ($allowed -notcontains $maturity) {
                Write-Verbose "Skipping '$($component.PackagePath)' with maturity '$maturity' for channel '$Channel'."
                continue
            }

            $items.Add(@{
                    Kind        = $component.Kind
                    Field       = $field
                    PackagePath = $component.PackagePath
                    SourcePath  = $component.SourcePath
                    Maturity    = $maturity
                })
        }
    }

    return [hashtable[]]$items.ToArray()
}

function Get-MarketplaceEntryMaturity {
    <#
    .SYNOPSIS
    Returns the package-level maturity declared by an entry overlay.

    .PARAMETER Entry
    One marketplace plugin entry.

    .OUTPUTS
    [string] Package maturity, defaulting to stable.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Entry
    )

    if ($Entry.Contains('x-hve') -and $Entry['x-hve'] -is [System.Collections.IDictionary]) {
        $overlay = $Entry['x-hve']
        if ($overlay.Contains('maturity') -and -not [string]::IsNullOrWhiteSpace([string]$overlay['maturity'])) {
            return [string]$overlay['maturity']
        }
    }

    return 'stable'
}

function Get-MarketplaceEntryOverlayValue {
    <#
    .SYNOPSIS
    Reads one x-hve overlay value from an entry.

    .PARAMETER Entry
    One marketplace plugin entry.

    .PARAMETER Key
    Overlay key to read.

    .OUTPUTS
    [object] Overlay value, or $null when absent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Entry,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Key
    )

    if (-not $Entry.Contains('x-hve') -or $Entry['x-hve'] -isnot [System.Collections.IDictionary]) {
        return $null
    }

    $overlay = $Entry['x-hve']
    if (-not $overlay.Contains($Key)) {
        return $null
    }

    return $overlay[$Key]
}

function Resolve-MarketplaceComponentPath {
    <#
    .SYNOPSIS
    Normalizes and validates a package-relative component path.

    .DESCRIPTION
    Component paths are both public manifest data and the internal build
    recipe, so they must be portable relative paths that stay inside the
    package. Absolute paths, backslashes, escaping or relative segments,
    empty segments, and control characters are rejected. A single trailing
    slash is normalized away so directory and file forms compare equal.

    .PARAMETER Path
    The candidate component path.

    .OUTPUTS
    [hashtable] Path with the normalized value and Error with the failure reason.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Path
    )

    $candidate = if ($null -eq $Path) { '' } else { $Path.Trim() }

    if ([string]::IsNullOrWhiteSpace($candidate)) {
        return @{ Path = ''; Error = 'component path must be a non-empty string' }
    }

    if ($candidate -match '\p{C}') {
        return @{ Path = ''; Error = "component path '$candidate' must not contain control characters" }
    }

    if ($candidate -match '\\') {
        return @{ Path = ''; Error = "component path '$candidate' must use forward slashes" }
    }

    if ($candidate -match '^/' -or $candidate -match '^[A-Za-z]:') {
        return @{ Path = ''; Error = "component path '$candidate' must be relative to the package root" }
    }

    $normalized = $candidate.TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return @{ Path = ''; Error = 'component path must be a non-empty string' }
    }

    foreach ($segment in ($normalized -split '/')) {
        if ([string]::IsNullOrEmpty($segment)) {
            return @{ Path = ''; Error = "component path '$candidate' must not contain empty path segments" }
        }

        if ($segment -eq '..') {
            return @{ Path = ''; Error = "component path '$candidate' must not escape the package root" }
        }

        if ($segment -eq '.') {
            return @{ Path = ''; Error = "component path '$candidate' must not contain relative path segments" }
        }
    }

    return @{ Path = $normalized; Error = '' }
}

function Test-MarketplaceEntryContract {
    <#
    .SYNOPSIS
    Validates the standard component membership and x-hve overlay of one entry.

    .DESCRIPTION
    Enforces the marketplace-centered data contract: standard fields own all
    component membership, and x-hve carries entry-level metadata only. Each
    declared component path is normalized and checked for portability,
    duplicate membership within a field, and duplicate membership across
    kinds. The x-hve overlay is closed to its documented keys, maturity
    values follow repository policy, and componentMaturity keys are normalized
    component paths.

    .PARAMETER Entry
    One marketplace plugin entry.

    .OUTPUTS
    [string[]] Error messages, empty when the entry satisfies the contract.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Entry
    )

    $entryErrors = @()
    $fieldMap = Get-MarketplaceComponentFieldMap
    $declaredPaths = @{}

    foreach ($field in $fieldMap.Keys) {
        if (-not $Entry.Contains($field)) {
            continue
        }

        $value = $Entry[$field]
        if ($null -eq $value) {
            $entryErrors += "component field '$field' must be a path string or an array of path strings"
            continue
        }

        if ($field -eq 'hooks' -and $value -isnot [string]) {
            $entryErrors += "component field 'hooks' must be a single path string"
            continue
        }

        $values = if ($value -is [string]) { @($value) } else { @($value) }
        if ($value -isnot [string] -and $value -isnot [System.Collections.IEnumerable]) {
            $entryErrors += "component field '$field' must be a path string or an array of path strings"
            continue
        }

        if ($values.Count -eq 0) {
            $entryErrors += "component field '$field' must declare at least one path"
            continue
        }

        $seenInField = @{}
        foreach ($item in $values) {
            if ($item -isnot [string]) {
                $entryErrors += "component field '$field' must contain only path strings"
                continue
            }

            $resolved = Resolve-MarketplaceComponentPath -Path $item
            if ($resolved.Error) {
                $entryErrors += "component field '$field': $($resolved.Error)"
                continue
            }

            $normalized = $resolved.Path
            if ($seenInField.ContainsKey($normalized)) {
                $entryErrors += "component field '$field' declares duplicate path '$normalized'"
                continue
            }

            $seenInField[$normalized] = $true

            if ($declaredPaths.ContainsKey($normalized)) {
                $entryErrors += "component path '$normalized' is declared in both '$($declaredPaths[$normalized])' and '$field'"
                continue
            }

            $declaredPaths[$normalized] = $field
        }
    }

    if ($Entry.Contains('author')) {
        $author = $Entry['author']
        if ($author -isnot [System.Collections.IDictionary]) {
            $entryErrors += 'author must be an object containing name and optional email or url'
        }
        else {
            if (-not $author.Contains('name') -or [string]::IsNullOrWhiteSpace([string]$author['name'])) {
                $entryErrors += 'author.name must be a non-empty string'
            }
            if ($author.Contains('email') -and [string]::IsNullOrWhiteSpace([string]$author['email'])) {
                $entryErrors += 'author.email must be a non-empty string when provided'
            }
            if ($author.Contains('url') -and ([string]$author['url'] -notmatch '^https://\S+$')) {
                $entryErrors += 'author.url must be an absolute https URL when provided'
            }
        }
    }

    if (-not $Entry.Contains('x-hve')) {
        return [string[]]$entryErrors
    }

    $overlay = $Entry['x-hve']
    if ($overlay -isnot [System.Collections.IDictionary]) {
        $entryErrors += 'x-hve must be an object'
        return [string[]]$entryErrors
    }

    $permittedKeys = Get-MarketplaceMetadataKey
    foreach ($key in $overlay.Keys) {
        if ($permittedKeys -notcontains $key) {
            $entryErrors += "x-hve contains unsupported key '$key'"
        }
    }

    $vocabulary = Get-CollectionMaturityVocabulary

    if ($overlay.Contains('maturity')) {
        $maturity = $overlay['maturity']
        if ($maturity -isnot [string] -or $vocabulary -notcontains $maturity) {
            $entryErrors += "x-hve.maturity '$maturity' must be one of: $($vocabulary -join ', ')"
        }
    }

    if ($overlay.Contains('componentMaturity')) {
        $componentMaturity = $overlay['componentMaturity']
        if ($componentMaturity -isnot [System.Collections.IDictionary]) {
            $entryErrors += 'x-hve.componentMaturity must be an object keyed by component path'
        }
        else {
            foreach ($key in $componentMaturity.Keys) {
                $resolved = Resolve-MarketplaceComponentPath -Path ([string]$key)
                if ($resolved.Error) {
                    $entryErrors += "x-hve.componentMaturity: $($resolved.Error)"
                    continue
                }

                if ($resolved.Path -ne [string]$key) {
                    $entryErrors += "x-hve.componentMaturity key '$key' must be a normalized component path"
                    continue
                }

                $itemMaturity = $componentMaturity[$key]
                if ($itemMaturity -isnot [string] -or $vocabulary -notcontains $itemMaturity) {
                    $entryErrors += "x-hve.componentMaturity['$key'] value '$itemMaturity' must be one of: $($vocabulary -join ', ')"
                }
            }
        }
    }

    if ($overlay.Contains('documentation')) {
        $documentation = $overlay['documentation']
        if ($documentation -isnot [string]) {
            $entryErrors += 'x-hve.documentation must be a repository-relative path string'
        }
        else {
            $resolved = Resolve-MarketplaceComponentPath -Path $documentation
            if ($resolved.Error) {
                $entryErrors += "x-hve.documentation: $($resolved.Error)"
            }
            elseif ($resolved.Path -ne $documentation) {
                $entryErrors += "x-hve.documentation '$documentation' must be a normalized repository-relative path"
            }
        }
    }

    if ($overlay.Contains('aggregate')) {
        $aggregate = $overlay['aggregate']
        if ($aggregate -isnot [bool]) {
            $entryErrors += 'x-hve.aggregate must be a boolean'
        }
    }

    return [string[]]$entryErrors
}

function New-PluginManifestContent {
    <#
    .SYNOPSIS
    Generates root plugin.json content as an ordered hashtable.

    .DESCRIPTION
    Creates the runtime manifest mirroring the standard catalog recipe: name,
    description, version, provenance, and component path declarations for
    agents, commands, rules, skills, and hooks. The x-hve metadata overlay is
    catalog-only and never reaches a generated manifest.

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
    Optional. Array of package-relative directory paths containing agent files.

    .PARAMETER CommandPaths
    Optional. Array of package-relative directory paths containing prompt files.

    .PARAMETER RulePaths
    Optional. Array of package-relative directory paths containing instruction files.

    .PARAMETER SkillPaths
    Optional. Array of package-relative directory paths containing skill subdirs.

    .PARAMETER HookPaths
    Optional. Array of package-relative file paths to hook JSON files.

    .OUTPUTS
    [hashtable] Plugin manifest with name, description, version, provenance,
    and component path keys.
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

    # Emit explicit path arrays when provided; the CLI does not recurse
    # into subdirectories, so each leaf directory must be declared.
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

function Split-PluginDocumentationSource {
    <#
    .SYNOPSIS
    Separates a package document into title, notice, and overview content.

    .DESCRIPTION
    The durable package document owns the hand-authored prose that the
    generated README embeds. Its frontmatter title supplies the README heading,
    an optional marker-delimited notice block is emitted immediately after the
    description, and the remaining body becomes the Overview section.

    .PARAMETER Content
    Raw document content.

    .OUTPUTS
    [hashtable] Title, Notice, and Body.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Content
    )

    $result = @{ Title = ''; Notice = ''; Body = '' }
    if ([string]::IsNullOrWhiteSpace($Content)) {
        return $result
    }

    $body = $Content -replace "`r`n", "`n"

    if ($body -match '(?s)\A---\s*\n(.*?)\n---\s*\n') {
        $frontmatterText = $Matches[1]
        $body = $body.Substring($Matches[0].Length)
        try {
            $frontmatter = ConvertFrom-Yaml -Yaml $frontmatterText
            if ($frontmatter -is [System.Collections.IDictionary] -and $frontmatter.Contains('title')) {
                $result.Title = [string]$frontmatter['title']
            }
        }
        catch {
            Write-Verbose "Failed to parse package document frontmatter: $_"
        }
    }

    # Legacy companion prose leads with an H1; the frontmatter title replaces it.
    if ($body -match '(?m)\A#\s+([^\r\n]+)\r?\n') {
        if ([string]::IsNullOrWhiteSpace($result.Title)) {
            $result.Title = $Matches[1].Trim()
        }
        $body = $body -replace '(?m)\A#\s+[^\r\n]+\r?\n(\r?\n)?', ''
    }

    if ($body -match "(?s)$([regex]::Escape($script:PluginNoticeBeginMarker))\s*\n(.*?)\n\s*$([regex]::Escape($script:PluginNoticeEndMarker))\s*\n?") {
        $result.Notice = $Matches[1].Trim()
        $body = $body.Replace($Matches[0], '')
    }

    $result.Body = $body.Trim()
    return $result
}

function New-PluginReadmeContent {
    <#
    .SYNOPSIS
    Generates README.md markdown for a plugin.

    .DESCRIPTION
    Builds a complete README.md string with a markdownlint-disable header,
    title, description, install command, and tables for each artifact kind
    that has items. Only sections with items are included.

    .PARAMETER Collection
    Hashtable with id, name, and description keys for the package.
    An optional 'notice' key injects a custom blockquote after the description.

    .PARAMETER Items
    Array of processed item objects. Each object must have Name, Description,
    and Kind properties.

    .PARAMETER Maturity
        Optional package maturity string. When 'experimental', an
        experimental notice is injected after the description. When 'preview',
        a preview notice is injected.

    .PARAMETER CollectionContent
        Optional markdown content from the durable package document. Injected as
        an Overview section between the description and the Install section.

    .OUTPUTS
    [string] Complete README markdown content.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Collection,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$Items,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Maturity,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$CollectionContent
    )

    $parsedDocument = Split-PluginDocumentationSource -Content $CollectionContent
    $title = if (-not [string]::IsNullOrWhiteSpace($parsedDocument.Title)) {
        $parsedDocument.Title
    }
    else {
        [string]$Collection.name
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<!-- markdownlint-disable-file -->')
    [void]$sb.AppendLine("# $title")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine($Collection.description)

    # Inject maturity notice when the package is not stable
    $effectiveMaturity = if ([string]::IsNullOrWhiteSpace($Maturity)) { 'stable' } else { $Maturity }
    if ($effectiveMaturity -eq 'experimental') {
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("> **`u{26A0}`u{FE0F} Experimental** `u{2014} This collection is experimental. Contents and behavior may change or be removed without notice.")
    }
    elseif ($effectiveMaturity -eq 'preview') {
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("> **`u{1F50D} Preview** `u{2014} This collection is in preview. Core features are complete and functional but refinements may follow.")
    }

    # Inject the package notice declared by the durable package document
    $notice = if ($Collection.ContainsKey('notice') -and -not [string]::IsNullOrWhiteSpace($Collection.notice)) {
        [string]$Collection.notice
    }
    else {
        $parsedDocument.Notice
    }
    if (-not [string]::IsNullOrWhiteSpace($notice)) {
        [void]$sb.AppendLine()
        [void]$sb.AppendLine($notice.TrimEnd())
    }

    # Inject the package document body as an Overview section. Frontmatter, a
    # legacy leading H1, and the notice block are already removed because the
    # title and notice are emitted above.
    $overviewText = $parsedDocument.Body

    if (-not [string]::IsNullOrWhiteSpace($overviewText)) {
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('## Overview')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine($overviewText)
    }

    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Install')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('```bash')
    [void]$sb.AppendLine("copilot plugin install $($Collection.id)@hve-core")
    [void]$sb.AppendLine('```')

    $sectionMap = [ordered]@{
        agent       = @{ Title = 'Agents'; Header = 'Agent' }
        prompt      = @{ Title = 'Commands'; Header = 'Command' }
        instruction = @{ Title = 'Instructions'; Header = 'Instruction' }
        skill       = @{ Title = 'Skills'; Header = 'Skill' }
        hook        = @{ Title = 'Hooks'; Header = 'Hook' }
    }

    $hasCollectionArtifactContent = -not [string]::IsNullOrWhiteSpace($CollectionContent) -and (
        $CollectionContent -match '(?m)^##\s+Included Artifacts\s*$' -or
        (
            $CollectionContent -match '<!-- BEGIN AUTO-GENERATED ARTIFACTS -->' -and
            $CollectionContent -match '<!-- END AUTO-GENERATED ARTIFACTS -->'
        )
    )

    if (-not $hasCollectionArtifactContent) {
        foreach ($entry in $sectionMap.GetEnumerator()) {
            $kind = $entry.Key
            $meta = $entry.Value
            $kindItems = @($Items | Where-Object { $_.Kind -eq $kind })
            if ($kindItems.Count -eq 0) {
                continue
            }

            [void]$sb.AppendLine()
            [void]$sb.AppendLine("## $($meta.Title)")
            [void]$sb.AppendLine()

            # Calculate column widths for aligned table output
            $col1Width = $meta.Header.Length
            $col2Width = 'Description'.Length
            foreach ($item in $kindItems) {
                if ($item.Name.Length -gt $col1Width) { $col1Width = $item.Name.Length }
                if ($item.Description.Length -gt $col2Width) { $col2Width = $item.Description.Length }
            }

            [void]$sb.AppendLine("| $($meta.Header.PadRight($col1Width)) | $('Description'.PadRight($col2Width)) |")
            [void]$sb.AppendLine('|' + ('-' * ($col1Width + 2)) + '|' + ('-' * ($col2Width + 2)) + '|')
            foreach ($item in $kindItems) {
                [void]$sb.AppendLine("| $($item.Name.PadRight($col1Width)) | $($item.Description.PadRight($col2Width)) |")
            }
        }
    }

    [void]$sb.AppendLine()
    [void]$sb.AppendLine('---')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('> Source: [microsoft/hve-core](https://github.com/microsoft/hve-core)')
    [void]$sb.AppendLine()

    return $sb.ToString()
}

function New-PluginReleaseLocator {
    <#
    .SYNOPSIS
    Builds a validated immutable release locator for marketplace object sources.

    .DESCRIPTION
    Produces the repository, immutable ref, and package path prefix used to emit
    object-form marketplace sources. Accepts an explicit 'plugins-v<version>' tag
    or derives one from a package version.

    Commit-SHA catalog locators are not part of the production contract.

    .PARAMETER Tag
    Explicit immutable release tag in 'plugins-v<version>' form.

    .PARAMETER Version
    Semantic version from which the 'plugins-v<version>' tag is derived.

    .PARAMETER Repo
    Source repository in 'owner/name' form.

    .PARAMETER PathPrefix
    Repository-relative directory holding generated packages.

    .OUTPUTS
    [hashtable] Locator with Repo, Ref, and PathPrefix keys.

    .EXAMPLE
    New-PluginReleaseLocator -Version '1.2.3'
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

        [Parameter(Mandatory = $false)]
        [string]$Repo = 'microsoft/hve-core',

        [Parameter(Mandatory = $false)]
        [string]$PathPrefix = 'plugins'
    )

    $semVerPattern = '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$'

    if ($PSCmdlet.ParameterSetName -eq 'Version') {
        if ($Version -notmatch $semVerPattern) {
            throw "Release version '$Version' is not a semantic version."
        }
        $Tag = "plugins-v$Version"
    }

    if ($Tag -match '^[0-9a-fA-F]{40}$') {
        throw "Release locator '$Tag' is a commit sha. Sha-pinned catalog sources are not supported; use the immutable 'plugins-v<version>' tag."
    }

    if ($Tag -notmatch "^plugins-v$($semVerPattern.TrimStart('^'))") {
        throw "Release locator '$Tag' must use the immutable 'plugins-v<version>' tag form."
    }

    if ($Repo -notmatch '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$') {
        throw "Release repository '$Repo' must use 'owner/name' form."
    }

    $normalizedPrefix = $PathPrefix.Trim('/')
    if ([string]::IsNullOrWhiteSpace($normalizedPrefix) -or $normalizedPrefix -match '\\' -or $normalizedPrefix -match '(^|/)\.\.?(/|$)') {
        throw "Release path prefix '$PathPrefix' must be a relative forward-slash path inside the repository."
    }

    return @{
        Repo       = $Repo
        Ref        = $Tag
        PathPrefix = $normalizedPrefix
    }
}

function New-MarketplaceManifestContent {
    <#
    .SYNOPSIS
    Projects a marketplace catalog, optionally rewriting entry sources.

    .DESCRIPTION
    Produces a marketplace manifest from the catalog metadata and entries.
    Standard entry fields and the x-hve overlay are preserved verbatim, because
    the catalog is the package-definition authority. Supplying a release locator
    replaces each object source with a package locator at the selected immutable
    ref in the source repository.

    .PARAMETER RepoName
    Repository name used as the marketplace name.

    .PARAMETER Description
    Short description of the repository.

    .PARAMETER Version
    Semantic version string from package.json.

    .PARAMETER OwnerName
    Organization or individual owning the repository.

    .PARAMETER Plugins
    Catalog entries to project.

    .PARAMETER ReleaseLocator
    Optional. Locator from New-PluginReleaseLocator. When supplied, entry object
    sources are rewritten to the selected immutable package reference.

    .OUTPUTS
    [hashtable] Marketplace manifest with name, metadata, owner, and plugins keys.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$OwnerName,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$Plugins,

        [Parameter(Mandatory = $false)]
        [hashtable]$ReleaseLocator
    )

    $useLocator = $null -ne $ReleaseLocator -and $ReleaseLocator.Count -gt 0

    $pluginEntries = @()
    foreach ($plugin in ($Plugins | Sort-Object { $_['name'] })) {
        $projected = [ordered]@{}
        foreach ($key in $plugin.Keys) {
            $projected[$key] = $plugin[$key]
        }

        if ($useLocator) {
            $projected['source'] = [ordered]@{
                source = 'github'
                repo   = $ReleaseLocator.Repo
                path   = "$($ReleaseLocator.PathPrefix)/$($plugin['name'])"
                ref    = $ReleaseLocator.Ref
            }
        }
        elseif ($plugin['source'] -isnot [System.Collections.IDictionary]) {
            throw "Plugin '$($plugin['name'])' source must be an immutable object locator. Bare package sources are not supported."
        }

        $pluginEntries += $projected
    }

    return [ordered]@{
        name     = $RepoName
        metadata = [ordered]@{
            description = $Description
            version     = $Version
            pluginRoot  = './plugins'
        }
        owner    = [ordered]@{
            name = $OwnerName
        }
        plugins  = $pluginEntries
    }
}

function Write-MarketplaceManifest {
    <#
    .SYNOPSIS
    Writes a projected marketplace snapshot to an explicit destination.

    .DESCRIPTION
    The production catalog at .github/plugin/marketplace.json is the
    package-definition input, so generation never rewrites it. This projects
    that catalog to a separate destination, optionally pinning every entry
    source to an immutable release locator for snapshot publication.

    .PARAMETER RepoRoot
    Absolute path to the repository root directory.

    .PARAMETER Catalog
    Parsed marketplace catalog to project.

    .PARAMETER ReleaseLocator
    Optional. Locator from New-PluginReleaseLocator. Emits object sources and
    requires an explicit OutputPath so the production catalog is never rewritten
    by generation; catalog cutover is a separate reviewed change.

    .PARAMETER OutputPath
    Destination path, absolute or relative to RepoRoot. The production catalog
    is rejected as a destination.

    .PARAMETER DryRun
    When specified, logs the action without writing to disk.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Catalog,

        [Parameter(Mandatory = $false)]
        [hashtable]$ReleaseLocator,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [switch]$DryRun
    )

    $useLocator = $null -ne $ReleaseLocator -and $ReleaseLocator.Count -gt 0

    $productionPath = Join-Path -Path $RepoRoot -ChildPath '.github' -AdditionalChildPath 'plugin', 'marketplace.json'
    $resolvedOutputPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
        $OutputPath
    }
    else {
        Join-Path -Path $RepoRoot -ChildPath $OutputPath
    }

    if ([System.IO.Path]::GetFullPath($resolvedOutputPath) -eq [System.IO.Path]::GetFullPath($productionPath)) {
        throw "Marketplace projection must not write the production catalog at $productionPath. The catalog is the package-definition input."
    }

    $packageJsonPath = Join-Path -Path $RepoRoot -ChildPath 'package.json'
    $packageJson = Get-Content -Path $packageJsonPath -Raw | ConvertFrom-Json

    $manifestArgs = @{
        RepoName    = $packageJson.name
        Description = $packageJson.description
        Version     = $packageJson.version
        OwnerName   = $packageJson.author
        Plugins     = @($Catalog['plugins'])
    }
    if ($useLocator) {
        $manifestArgs['ReleaseLocator'] = $ReleaseLocator
    }

    $manifest = New-MarketplaceManifestContent @manifestArgs

    $outputDir = Split-Path -Path $resolvedOutputPath -Parent

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would write marketplace snapshot at $resolvedOutputPath" -ForegroundColor Yellow
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path -Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $manifestJson = ($manifest | ConvertTo-Json -Depth 12) + "`n"
    Set-ContentIfChanged -Path $resolvedOutputPath -Value $manifestJson | Out-Null
    Write-Host "  Marketplace snapshot: $resolvedOutputPath" -ForegroundColor Green
}

function Test-PluginGitRefName {
    <#
    .SYNOPSIS
    Tests whether a string is a usable git reference name.

    .PARAMETER Name
    Candidate branch or tag name.

    .OUTPUTS
    [bool] True when the name is a valid git reference.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }

    if ($Name -match '[\s~^:?*\[\\]' -or $Name -match '\.\.' -or $Name -match '@\{') {
        return $false
    }

    if ($Name.StartsWith('-') -or $Name.StartsWith('/') -or $Name.EndsWith('/') -or $Name.EndsWith('.')) {
        return $false
    }

    foreach ($segment in ($Name -split '/')) {
        if ([string]::IsNullOrEmpty($segment) -or $segment.StartsWith('.') -or $segment.EndsWith('.lock')) {
            return $false
        }
    }

    return $true
}

function Assert-PluginSnapshotTarget {
    <#
    .SYNOPSIS
    Validates the disposable branch and tag a snapshot publish may write.

    .DESCRIPTION
    Snapshot publication is only permitted against disposable references. The
    moving release branch, immutable 'plugins-v<version>' tags, and the default
    branch are protected and can never be named as targets. Tags are immutable,
    so an existing tag is refused rather than overwritten.

    .PARAMETER Branch
    Target branch for the snapshot commit.

    .PARAMETER Tag
    Target tag for the snapshot commit.

    .PARAMETER ExistingRefs
    Reference names that already exist on the remote, short or fully qualified.

    .PARAMETER DisposablePrefix
    Required prefix identifying a disposable reference.

    .OUTPUTS
    [hashtable] Validated target with Branch, Tag, and RefSpecs keys.

    .EXAMPLE
    Assert-PluginSnapshotTarget -Branch 'plugins-snapshot/run-42' -Tag 'plugins-snapshot/run-42-tag'
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Branch,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Tag,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$ExistingRefs = @(),

        [Parameter(Mandatory = $false)]
        [string]$DisposablePrefix = 'plugins-snapshot/'
    )

    $protectedBranches = @('main', 'release/plugins')
    $productionTagPattern = '^plugins-v\d+\.\d+\.\d+'

    foreach ($target in @(@{ Kind = 'branch'; Value = $Branch }, @{ Kind = 'tag'; Value = $Tag })) {
        if (-not (Test-PluginGitRefName -Name $target.Value)) {
            throw "Snapshot $($target.Kind) '$($target.Value)' is not a valid git reference name."
        }

        if ($protectedBranches -contains $target.Value -or $target.Value -match $productionTagPattern) {
            throw "Snapshot $($target.Kind) '$($target.Value)' targets a protected production reference and is refused."
        }

        if (-not $target.Value.StartsWith($DisposablePrefix)) {
            throw "Snapshot $($target.Kind) '$($target.Value)' must start with the disposable prefix '$DisposablePrefix'."
        }
    }

    if ($Branch -eq $Tag) {
        throw "Snapshot branch and tag must differ; both are '$Branch'."
    }

    $normalizedExisting = @($ExistingRefs | ForEach-Object { ($_ -replace '^refs/(heads|tags)/', '').Trim() })
    if ($normalizedExisting -contains $Tag) {
        throw "Snapshot tag '$Tag' already exists. Tags are immutable and are never overwritten."
    }

    return @{
        Branch   = $Branch
        Tag      = $Tag
        RefSpecs = @("HEAD:refs/heads/$Branch", "refs/tags/$Tag")
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

function Get-PluginTrackedPathIndex {
    <#
    .SYNOPSIS
    Builds the git-tracked path allowlist for a repository working tree.

    .DESCRIPTION
    Reads the repository-relative paths recorded in the git index. Plugin
    materialization copies only these paths, so untracked working-tree content
    such as virtual environments, dependency directories, and bytecode caches
    can never be ingested into a generated plugin. Throws when the directory is
    not a git working tree, because materializing without the allowlist would
    silently copy that residue.

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

function Copy-PluginFileIfChanged {
    <#
    .SYNOPSIS
    Copies a file only when the destination content differs.

    .DESCRIPTION
    Compares length then SHA256 before writing, preserving the git stat cache
    for unchanged files so repeat generations stay idempotent.

    .PARAMETER SourcePath
    Absolute path to the source file.

    .PARAMETER DestinationPath
    Absolute path to the destination file.

    .OUTPUTS
    [bool] True when the file was written, false when skipped.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    if (Test-Path -LiteralPath $DestinationPath -PathType Leaf) {
        $sourceLength = (Get-Item -LiteralPath $SourcePath -Force).Length
        $destinationLength = (Get-Item -LiteralPath $DestinationPath -Force).Length
        if ($sourceLength -eq $destinationLength) {
            $sourceHash = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash
            $destinationHash = (Get-FileHash -LiteralPath $DestinationPath -Algorithm SHA256).Hash
            if ($sourceHash -eq $destinationHash) {
                return $false
            }
        }
    }

    Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
    return $true
}

function Copy-PluginSource {
    <#
    .SYNOPSIS
    Materializes git-tracked source content into a plugin destination.

    .DESCRIPTION
    Copies current working-tree bytes for every git-tracked path at or beneath
    SourcePath, so locally modified tracked files are included and untracked
    files are excluded. A file source produces exactly one destination file; a
    directory source reconstructs its tracked subtree beneath DestinationPath.
    Returns every destination written so callers can record complete generated
    path bookkeeping for orphan cleanup.

    .PARAMETER SourcePath
    Absolute path to the repository file or directory being materialized.

    .PARAMETER DestinationPath
    Absolute destination path: the file itself for a file source, or the
    subtree root for a directory source.

    .PARAMETER RepoRoot
    Absolute path to the repository working tree.

    .PARAMETER TrackedIndex
    Optional index from Get-PluginTrackedPathIndex. Resolved on demand when
    omitted; callers in per-item loops should supply a shared index.

    .OUTPUTS
    [string[]] Absolute destination paths written.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [hashtable]$TrackedIndex
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($RepoRoot)
    $resolvedSource = [System.IO.Path]::GetFullPath($SourcePath)
    $relativeSource = [System.IO.Path]::GetRelativePath($resolvedRoot, $resolvedSource) -replace '\\', '/'

    if ($relativeSource -eq '..' -or $relativeSource.StartsWith('../') -or [System.IO.Path]::IsPathRooted($relativeSource)) {
        throw "Source path '$SourcePath' resolves outside the repository root '$resolvedRoot'."
    }

    if (-not $TrackedIndex) {
        $TrackedIndex = Get-PluginTrackedPathIndex -RepoRoot $resolvedRoot
    }

    $isFileSource = $TrackedIndex.Lookup.Contains($relativeSource)
    $matched = [System.Collections.Generic.List[string]]::new()

    if ($isFileSource) {
        $matched.Add($relativeSource)
    }
    else {
        $prefix = "$relativeSource/"
        foreach ($tracked in $TrackedIndex.Paths) {
            if ($tracked.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                $matched.Add($tracked)
            }
        }
    }

    if ($matched.Count -eq 0) {
        Write-Warning "No git-tracked content found for source: $relativeSource"
        return @()
    }

    $written = [System.Collections.Generic.List[string]]::new()

    foreach ($tracked in $matched) {
        $trackedSource = Join-Path -Path $resolvedRoot -ChildPath $tracked

        if ($isFileSource) {
            $destination = $DestinationPath
        }
        else {
            $suffix = $tracked.Substring($relativeSource.Length + 1)
            $destination = [System.IO.Path]::GetFullPath(
                [System.IO.Path]::Combine($DestinationPath, $suffix)
            )
        }

        # A path can be staged while absent from the working tree; skip it
        # rather than failing the whole generation run.
        if (-not (Test-Path -LiteralPath $trackedSource -PathType Leaf)) {
            Write-Warning "Tracked source missing from the working tree: $tracked"
            continue
        }

        $destinationDir = Split-Path -Parent $destination
        if ($destinationDir -and -not (Test-Path -LiteralPath $destinationDir -PathType Container)) {
            New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        }

        Copy-PluginFileIfChanged -SourcePath $trackedSource -DestinationPath $destination | Out-Null
        $written.Add($destination)
    }

    return $written.ToArray()
}

function Write-PluginHookArtifact {
    <#
    .SYNOPSIS
    Materializes a hook manifest and its sibling script directory into a plugin.

    .DESCRIPTION
    Hook command paths in the source manifest are repository-root relative
    (for example .github/hooks/shared/telemetry/telemetry-collector.sh) so they resolve
    when the hook is auto-loaded from a checked-out repository. Inside an
    installed plugin the same scripts live under the plugin root, so this
    function writes a transformed copy of the manifest with those paths
    rewritten to the ${PLUGIN_ROOT} placeholder, then materializes the sibling
    script directory (the manifest path without its .json extension).

    .PARAMETER SourceManifest
    Absolute path to the source hook .json manifest in the repository.

    .PARAMETER DestinationManifest
    Absolute path where the transformed manifest is written in the plugin.

    .PARAMETER GeneratedFiles
    Set tracking generated paths for orphan cleanup; every materialized script
    file is added to it.

    .PARAMETER RepoRoot
    Absolute path to the repository working tree.

    .PARAMETER TrackedIndex
    Optional git-tracked path index shared across a generation run.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceManifest,

        [Parameter(Mandatory = $true)]
        [string]$DestinationManifest,

        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.HashSet[string]]$GeneratedFiles,

        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [hashtable]$TrackedIndex
    )

    # Degrade gracefully when the manifest is missing, matching how other kinds
    # warn rather than throw and fail the entire generation run.
    if (-not (Test-Path -LiteralPath $SourceManifest)) {
        Write-Warning "Hook manifest not found: $SourceManifest"
        return
    }

    # Rewrite repo-root-relative hook script paths to plugin-relative paths so
    # commands resolve from the installed plugin directory. Literal string
    # replacement avoids regex interpretation of the path and the $ placeholder.
    $manifestText = Get-Content -LiteralPath $SourceManifest -Raw -Encoding utf8
    $manifestText = $manifestText.Replace('.github/hooks/', '${PLUGIN_ROOT}/hooks/')
    Set-ContentIfChanged -Path $DestinationManifest -Value $manifestText | Out-Null

    # Materialize the sibling script directory (manifest path without .json).
    $scriptSrc = $SourceManifest -replace '\.json$', ''
    if (Test-Path -LiteralPath $scriptSrc) {
        $scriptDest = $DestinationManifest -replace '\.json$', ''
        $materialized = @(Copy-PluginSource -SourcePath $scriptSrc -DestinationPath $scriptDest `
                -RepoRoot $RepoRoot -TrackedIndex $TrackedIndex)
        foreach ($file in $materialized) {
            [void]$GeneratedFiles.Add($file)
        }
    }
}

function ConvertTo-MarketplaceAgentKey {
    <#
    .SYNOPSIS
    Normalizes an agent handoff target to a comparable lookup key.

    .DESCRIPTION
    Handoff targets are authored as display names ("ADR Creation") while
    declared component paths carry file stems ("adr-creation"). Lowercasing and
    collapsing every non-alphanumeric run to a single hyphen makes both forms
    comparable without inventing aliases.

    .PARAMETER Name
    Display name or file stem to normalize.

    .OUTPUTS
    [string] Normalized lookup key.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Name
    )

    $key = ($Name -replace '[^A-Za-z0-9]+', '-').Trim('-')
    return $key.ToLowerInvariant()
}

function Get-MarketplaceAgentIndex {
    <#
    .SYNOPSIS
    Builds the handoff resolution index from catalog-declared agent paths.

    .DESCRIPTION
    Only agent components declared by a catalog entry enter the index, so
    dependency closure can never pull in an artifact the catalog does not
    publish. Each declared agent contributes its file stem and, when present,
    its frontmatter display name. A key that resolves to two different source
    paths is recorded as ambiguous and fails only when a handoff requests it.

    .PARAMETER Catalog
    Parsed marketplace catalog.

    .PARAMETER RepoRoot
    Absolute path to the repository root.

    .OUTPUTS
    [hashtable] Lookup (key to descriptor), Ambiguous (key to source paths).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Catalog,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot
    )

    $lookup = @{}
    $ambiguous = @{}
    $seenSources = @{}

    $addKey = {
        param([string]$Key, [hashtable]$Descriptor)

        if ([string]::IsNullOrWhiteSpace($Key)) {
            return
        }

        if (-not $lookup.ContainsKey($Key)) {
            $lookup[$Key] = $Descriptor
            return
        }

        if ($lookup[$Key].SourcePath -eq $Descriptor.SourcePath) {
            return
        }

        if (-not $ambiguous.ContainsKey($Key)) {
            $ambiguous[$Key] = @($lookup[$Key].SourcePath)
        }
        $ambiguous[$Key] = @($ambiguous[$Key] + $Descriptor.SourcePath | Sort-Object -Unique)
    }

    foreach ($entry in @($Catalog['plugins'])) {
        if (-not $entry.Contains('agents') -or $null -eq $entry['agents']) {
            continue
        }

        foreach ($packagePath in @($entry['agents'])) {
            $component = Resolve-MarketplaceComponentSource -PackagePath ([string]$packagePath) -Field 'agents'
            if ($seenSources.ContainsKey($component.SourcePath)) {
                continue
            }

            $absolute = Join-Path -Path $RepoRoot -ChildPath $component.SourcePath
            $handoffs = @()
            $displayName = ''

            if (Test-Path -LiteralPath $absolute -PathType Leaf) {
                $content = Get-Content -LiteralPath $absolute -Raw -Encoding utf8
                if ($content -match '(?s)^---\s*\r?\n(.*?)\r?\n---') {
                    $yaml = $Matches[1] -replace '\r\n', "`n" -replace '\r', "`n"
                    try {
                        $frontmatter = ConvertFrom-Yaml -Yaml $yaml
                        if ($frontmatter -is [System.Collections.IDictionary]) {
                            if ($frontmatter.Contains('name') -and $frontmatter['name'] -is [string]) {
                                $displayName = [string]$frontmatter['name']
                            }
                            if ($frontmatter.Contains('handoffs') -and $frontmatter['handoffs'] -is [System.Collections.IEnumerable] -and $frontmatter['handoffs'] -isnot [string]) {
                                foreach ($handoff in $frontmatter['handoffs']) {
                                    if ($handoff -is [string]) {
                                        $handoffs += $handoff
                                    }
                                    elseif ($handoff -is [System.Collections.IDictionary] -and $handoff.Contains('agent')) {
                                        $handoffs += [string]$handoff['agent']
                                    }
                                }
                            }
                        }
                    }
                    catch {
                        Write-Warning "Failed to parse frontmatter from $($component.SourcePath): $_"
                    }
                }
            }
            else {
                Write-Warning "Declared agent source not found: $($component.SourcePath)"
            }

            $stem = (Split-Path -Leaf $component.SourcePath) -replace '\.agent\.md$', ''
            $descriptor = @{
                PackagePath = $component.PackagePath
                SourcePath  = $component.SourcePath
                Handoffs    = @($handoffs)
            }
            $seenSources[$component.SourcePath] = $descriptor

            & $addKey (ConvertTo-MarketplaceAgentKey -Name $stem) $descriptor
            if ($displayName) {
                & $addKey (ConvertTo-MarketplaceAgentKey -Name $displayName) $descriptor
            }
        }
    }

    return @{
        Lookup    = $lookup
        Ambiguous = $ambiguous
    }
}

function Expand-MarketplaceAgentDependency {
    <#
    .SYNOPSIS
    Closes transitive agent handoff dependencies over declared components.

    .DESCRIPTION
    Performs breadth-first traversal from the agents a package declares,
    following frontmatter handoff targets until the set is closed. Duplicates
    collapse on the canonical source path. An unresolved or ambiguous target
    fails, because publishing a package whose handoff cannot be satisfied is a
    silent runtime break.

    .PARAMETER Index
    Index from Get-MarketplaceAgentIndex.

    .PARAMETER SeedPackagePaths
    Agent component paths declared by the package.

    .PARAMETER PackageName
    Package name used in failure messages.

    .OUTPUTS
    [string[]] Sorted agent component paths including transitive dependencies.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Index,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$SeedPackagePaths,

        [Parameter(Mandatory = $false)]
        [string]$PackageName = 'unknown'
    )

    $resolved = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $queue = [System.Collections.Generic.Queue[hashtable]]::new()

    foreach ($seed in $SeedPackagePaths) {
        $component = Resolve-MarketplaceComponentSource -PackagePath $seed -Field 'agents'
        $key = ConvertTo-MarketplaceAgentKey -Name ((Split-Path -Leaf $component.SourcePath) -replace '\.agent\.md$', '')
        $descriptor = $Index.Lookup[$key]
        if (-not $descriptor) {
            throw "Package '$PackageName' declares agent '$seed', which is absent from the catalog agent index."
        }
        if ($resolved.Add($descriptor.PackagePath)) {
            $queue.Enqueue($descriptor)
        }
    }

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        foreach ($target in $current.Handoffs) {
            $key = ConvertTo-MarketplaceAgentKey -Name $target
            if ($Index.Ambiguous.ContainsKey($key)) {
                throw "Package '$PackageName': handoff target '$target' in '$($current.SourcePath)' is ambiguous across $($Index.Ambiguous[$key] -join ', ')."
            }

            $descriptor = $Index.Lookup[$key]
            if (-not $descriptor) {
                throw "Package '$PackageName': handoff target '$target' in '$($current.SourcePath)' does not resolve to a catalog-declared agent."
            }

            if ($resolved.Add($descriptor.PackagePath)) {
                $queue.Enqueue($descriptor)
            }
        }
    }

    return [string[]]@($resolved | Sort-Object)
}

function Write-PluginDirectory {
    <#
    .SYNOPSIS
    Creates a complete plugin directory structure from a catalog entry.

    .DESCRIPTION
    Builds the full plugin layout under the specified plugins directory using
    the resolved catalog recipe. Every declared component is materialized from
    its canonical git-tracked repository source into the package-relative path
    the catalog declares, so the manifest, the catalog, and the package tree
    describe the same membership. Generates the root plugin.json and README.md.

    .PARAMETER Entry
    Marketplace catalog entry describing package identity and provenance.

    .PARAMETER Items
    Resolved recipe items with Kind, Field, PackagePath, and SourcePath keys.

    .PARAMETER PluginsDir
    Absolute path to the root plugins output directory.

    .PARAMETER RepoRoot
    Absolute path to the repository root.

    .PARAMETER Version
    Semantic version string from the repository package.json.

    .PARAMETER Maturity
        Optional package maturity string. Forwarded to
        New-PluginReadmeContent for maturity notice injection.

    .PARAMETER DocumentPath
        Optional absolute path to the durable package document supplying the
        README title, notice, and Overview content.

    .PARAMETER DryRun
    When specified, logs actions without creating files or directories.

    .OUTPUTS
    [hashtable] Result with Success, AgentCount, CommandCount, InstructionCount,
    SkillCount, HookCount, and GeneratedFiles keys.
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
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Maturity,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$DocumentPath,

        [Parameter(Mandatory = $false)]
        [switch]$DryRun
    )

    $packageName = [string]$Entry['name']
    $pluginRoot = Join-Path -Path $PluginsDir -ChildPath $packageName

    # One index per plugin bounds git invocations while staying current for
    # callers that stage content between generations.
    $trackedIndex = if ($DryRun) { $null } else { Get-PluginTrackedPathIndex -RepoRoot $RepoRoot }

    $counts = @{
        AgentCount       = 0
        CommandCount     = 0
        InstructionCount = 0
        SkillCount       = 0
        HookCount        = 0
    }

    # Track unique directories per kind for plugin.json path arrays
    $agentDirs = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $commandDirs = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $ruleDirs = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $skillDirs = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $hookFiles = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    $readmeItems = @()
    $generatedFiles = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    foreach ($item in $Items) {
        $kind = [string]$item.Kind
        $sourcePath = Join-Path -Path $RepoRoot -ChildPath $item.SourcePath
        $destPath = Join-Path -Path $pluginRoot -ChildPath ($item.PackagePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $itemName = Split-Path -Leaf $item.PackagePath

        if ($kind -eq 'skill') {
            # Read frontmatter from SKILL.md for description; fall back to directory name
            $skillMdPath = Join-Path -Path $sourcePath -ChildPath 'SKILL.md'
            if (Test-Path -Path $skillMdPath) {
                $frontmatter = Get-ArtifactFrontmatter -FilePath $skillMdPath -FallbackDescription $itemName
                $description = $frontmatter.description
            }
            else {
                $description = $itemName
            }
        }
        else {
            # Read description from the source file. Hook manifests are JSON
            # with no frontmatter, so read their top-level description field.
            $fallback = $itemName -replace '\.(md|json)$', ''
            if (-not (Test-Path -Path $sourcePath)) {
                $description = $fallback
                Write-Warning "Source file not found: $sourcePath"
            }
            elseif ($kind -eq 'hook') {
                $hookDesc = Get-ArtifactDescription -FilePath $sourcePath
                $description = if ($hookDesc) { $hookDesc } else { $fallback }
            }
            else {
                $frontmatter = Get-ArtifactFrontmatter -FilePath $sourcePath -FallbackDescription $fallback
                $description = $frontmatter.description
            }
        }

        $readmeItems += @{
            Name        = ($itemName -replace '\.md$', '') -replace '\.json$', ''
            Description = $description
            Kind        = $kind
        }

        $relativeParent = (Split-Path -Parent $item.PackagePath) -replace '\\', '/'

        # Update counts and collect parent directories for manifest paths
        switch ($kind) {
            'agent' {
                $counts.AgentCount++
                [void]$agentDirs.Add("$relativeParent/")
            }
            'prompt' {
                $counts.CommandCount++
                [void]$commandDirs.Add("$relativeParent/")
            }
            'instruction' {
                $counts.InstructionCount++
                [void]$ruleDirs.Add("$relativeParent/")
            }
            'skill' {
                $counts.SkillCount++
                [void]$skillDirs.Add("$($item.PackagePath)/")
            }
            'hook' {
                $counts.HookCount++
                [void]$hookFiles.Add($item.PackagePath)
            }
        }

        [void]$generatedFiles.Add($destPath)

        if ($DryRun) {
            Write-Verbose "DryRun: Would materialize $destPath from $sourcePath"
            continue
        }

        # Hooks bundle a sibling script directory and need plugin-relative
        # command paths; other kinds materialize their source directly.
        if ($kind -eq 'hook') {
            Write-PluginHookArtifact -SourceManifest $sourcePath -DestinationManifest $destPath `
                -GeneratedFiles $generatedFiles -RepoRoot $RepoRoot -TrackedIndex $trackedIndex
        }
        else {
            $materialized = @(Copy-PluginSource -SourcePath $sourcePath -DestinationPath $destPath `
                    -RepoRoot $RepoRoot -TrackedIndex $trackedIndex)
            foreach ($file in $materialized) {
                [void]$generatedFiles.Add($file)
            }
        }
    }

    # Materialize shared resource directories (unconditional, all plugins)
    $sharedDirs = @(
        @{ Source = 'docs/templates';    Destination = 'docs/templates' }
        @{ Source = 'scripts/lib';       Destination = 'scripts/lib' }
    )

    foreach ($dir in $sharedDirs) {
        $sourcePath = Join-Path -Path $RepoRoot -ChildPath $dir.Source
        $destPath = Join-Path -Path $pluginRoot -ChildPath $dir.Destination

        if (-not (Test-Path -Path $sourcePath)) {
            Write-Warning "Shared directory not found: $sourcePath"
            continue
        }

        [void]$generatedFiles.Add($destPath)

        if ($DryRun) {
            Write-Verbose "DryRun: Would materialize shared directory $destPath from $sourcePath"
            continue
        }

        $materialized = @(Copy-PluginSource -SourcePath $sourcePath -DestinationPath $destPath `
                -RepoRoot $RepoRoot -TrackedIndex $trackedIndex)
        foreach ($file in $materialized) {
            [void]$generatedFiles.Add($file)
        }
    }

    # Generate the single root plugin.json with explicit path arrays for
    # client discovery. Provenance mirrors the catalog entry; x-hve does not.
    $manifestPath = Join-Path -Path $pluginRoot -ChildPath 'plugin.json'
    $manifestArgs = @{
        PackageName  = $packageName
        Description  = [string]$Entry['description']
        Version      = $Version
        AgentPaths   = @($agentDirs)
        CommandPaths = @($commandDirs)
        RulePaths    = @($ruleDirs)
        SkillPaths   = @($skillDirs)
        HookPaths    = @($hookFiles)
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
    [void]$generatedFiles.Add($manifestPath)

    if ($DryRun) {
        Write-Verbose "DryRun: Would write plugin.json at $manifestPath"
    }
    else {
        if (-not (Test-Path -Path $pluginRoot)) {
            New-Item -ItemType Directory -Path $pluginRoot -Force | Out-Null
        }
        $jsonContent = $manifest | ConvertTo-Json -Depth 10
        Set-ContentIfChanged -Path $manifestPath -Value $jsonContent | Out-Null
    }

    # Generate README.md
    $readmePath = Join-Path -Path $pluginRoot -ChildPath 'README.md'
    $documentContent = if (-not [string]::IsNullOrWhiteSpace($DocumentPath) -and (Test-Path -LiteralPath $DocumentPath -PathType Leaf)) {
        Get-Content -LiteralPath $DocumentPath -Raw -Encoding utf8
    } else { $null }
    $readmeCollection = @{
        id          = $packageName
        name        = $packageName
        description = [string]$Entry['description']
    }
    $readmeContent = New-PluginReadmeContent -Collection $readmeCollection -Items $readmeItems -Maturity $Maturity -CollectionContent $documentContent
    [void]$generatedFiles.Add($readmePath)

    if ($DryRun) {
        Write-Verbose "DryRun: Would write README.md at $readmePath"
    }
    else {
        Set-ContentIfChanged -Path $readmePath -Value $readmeContent | Out-Null
    }

    return @{
        Success          = $true
        AgentCount       = $counts.AgentCount
        CommandCount     = $counts.CommandCount
        InstructionCount = $counts.InstructionCount
        SkillCount       = $counts.SkillCount
        HookCount        = $counts.HookCount
        GeneratedFiles   = $generatedFiles
    }
}

Export-ModuleMember -Function @(
    'Assert-PluginSnapshotTarget',
    'ConvertTo-MarketplaceAgentKey',
    'Copy-PluginSource',
    'Expand-MarketplaceAgentDependency',
    'Get-MarketplaceAgentIndex',
    'Get-MarketplaceCatalog',
    'Get-MarketplaceComponentField',
    'Get-MarketplaceComponentFieldMap',
    'Get-MarketplaceComponentSourceRoot',
    'Get-MarketplaceEntryMaturity',
    'Get-MarketplaceEntryOverlayValue',
    'Get-MarketplaceMetadataKey',
    'Get-MarketplacePackagePath',
    'Get-MarketplacePackageRecipe',
    'Get-PluginItemName',
    'Get-PluginItemSubpath',
    'Get-PluginSubdirectory',
    'Get-PluginTrackedPathIndex',
    'New-GenerateResult',
    'New-MarketplaceManifestContent',
    'New-PluginManifestContent',
    'New-PluginReadmeContent',
    'New-PluginReleaseLocator',
    'Resolve-MarketplaceComponentPath',
    'Resolve-MarketplaceComponentSource',
    'Split-PluginDocumentationSource',
    'Test-MarketplaceEntryContract',
    'Write-MarketplaceManifest',
    'Write-PluginDirectory'
)
