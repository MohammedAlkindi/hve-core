# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# MarketplaceHelpers.psm1
# Purpose: Shared marketplace catalog contract, projection, indexing, and closure utilities.

#Requires -Version 7.4
#Requires -Modules @{ ModuleName='PowerShell-Yaml'; RequiredVersion='0.4.7' }

Import-Module (Join-Path $PSScriptRoot 'ArtifactHelpers.psm1') -Force

function Get-PluginItemName {
    <#
    .SYNOPSIS
    Returns an artifact filename in package form.
    .PARAMETER FileName
    Source filename.
    .PARAMETER Kind
    Artifact kind.
    .OUTPUTS
    [string] Package filename.
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
        'agent' { return $FileName -replace '\.agent\.md$', '.md' }
        'prompt' { return $FileName -replace '\.prompt\.md$', '.md' }
        default { return $FileName }
    }
}

function Get-PluginItemSubpath {
    <#
    .SYNOPSIS
    Returns the path between an artifact root and leaf.
    .PARAMETER Path
    Repository-relative source path.
    .PARAMETER Kind
    Artifact kind.
    .OUTPUTS
    [string] Intermediate path or an empty string.
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
        agent       = '.github/agents/'
        prompt      = '.github/prompts/'
        instruction = '.github/instructions/'
        skill       = '.github/skills/'
        hook        = '.github/hooks/'
    }
    $normalized = $Path -replace '\\', '/'
    $prefix = $prefixMap[$Kind]
    if (-not $normalized.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
        return ''
    }

    $parts = $normalized.Substring($prefix.Length) -split '/'
    if ($parts.Count -gt 1) {
        return $parts[0..($parts.Count - 2)] -join '/'
    }

    return ''
}

function Get-PluginSubdirectory {
    <#
    .SYNOPSIS
    Returns the package directory for an artifact kind.
    .PARAMETER Kind
    Artifact kind.
    .OUTPUTS
    [string] Standard component directory.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('agent', 'prompt', 'instruction', 'skill', 'hook')]
        [string]$Kind
    )

    return @{
        agent       = 'agents'
        prompt      = 'commands'
        instruction = 'rules'
        skill       = 'skills'
        hook        = 'hooks'
    }[$Kind]
}

function Get-MarketplaceComponentFieldMap {
    <#
    .SYNOPSIS
    Returns standard marketplace fields and artifact kinds.
    .OUTPUTS
    [System.Collections.Specialized.OrderedDictionary] Field-to-kind map.
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
    Returns the closed x-hve metadata key set.
    .OUTPUTS
    [string[]] Permitted metadata keys.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return , @('displayName', 'maturity', 'componentMaturity', 'documentation', 'aggregate')
}

function Get-MarketplaceComponentSourceRoot {
    <#
    .SYNOPSIS
    Returns canonical source roots and suffixes by marketplace field.
    .OUTPUTS
    [System.Collections.Specialized.OrderedDictionary] Field descriptors.
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
    Returns the marketplace field for an artifact kind.
    .PARAMETER Kind
    Artifact kind.
    .OUTPUTS
    [string] Marketplace field.
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

function Resolve-MarketplaceComponentPath {
    <#
    .SYNOPSIS
    Normalizes and validates a package-relative component path.
    .PARAMETER Path
    Candidate component path.
    .OUTPUTS
    [hashtable] Normalized Path and Error.
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

function Get-MarketplacePackagePath {
    <#
    .SYNOPSIS
    Projects a canonical source path to a package component path.
    .PARAMETER SourcePath
    Repository-relative source path.
    .PARAMETER Kind
    Artifact kind.
    .OUTPUTS
    [string] Package-relative path.
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
    $descriptor = (Get-MarketplaceComponentSourceRoot)[$field]
    $expectedRoot = "$($descriptor.SourceRoot)/"
    if (-not $normalized.StartsWith($expectedRoot, [System.StringComparison]::Ordinal)) {
        throw "Source path '$SourcePath' is not under the canonical '$($descriptor.SourceRoot)' root for kind '$Kind'."
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
    Resolves a package component path to its canonical source.
    .PARAMETER PackagePath
    Package-relative component path.
    .PARAMETER Field
    Standard component field.
    .OUTPUTS
    [hashtable] Kind, PackagePath, and SourcePath.
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

    $prefix = "$Field/"
    if (-not $resolved.Path.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
        throw "Component path '$PackagePath' must start with the '$Field/' package directory."
    }

    $descriptor = (Get-MarketplaceComponentSourceRoot)[$Field]
    $relative = $resolved.Path.Substring($prefix.Length)
    if ($descriptor.PackageSuffix) {
        if (-not $relative.EndsWith($descriptor.PackageSuffix, [System.StringComparison]::Ordinal)) {
            throw "Component path '$PackagePath' must end with '$($descriptor.PackageSuffix)'."
        }
        $relative = "$($relative.Substring(0, $relative.Length - $descriptor.PackageSuffix.Length))$($descriptor.SourceSuffix)"
    }

    return @{ Kind = $descriptor.Kind; PackagePath = $resolved.Path; SourcePath = "$($descriptor.SourceRoot)/$relative" }
}

function Get-MarketplaceCatalog {
    <#
    .SYNOPSIS
    Loads the marketplace catalog.
    .PARAMETER Path
    Catalog path.
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

function Get-MarketplaceEntryMaturity {
    <#
    .SYNOPSIS
    Returns package maturity.
    .PARAMETER Entry
    Marketplace entry.
    .OUTPUTS
    [string] Effective package maturity.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Entry
    )

    $value = Get-MarketplaceEntryOverlayValue -Entry $Entry -Key 'maturity'
    if ([string]::IsNullOrWhiteSpace([string]$value)) {
        return 'stable'
    }
    return [string]$value
}

function Get-MarketplaceEntryOverlayValue {
    <#
    .SYNOPSIS
    Reads an x-hve overlay value.
    .PARAMETER Entry
    Marketplace entry.
    .PARAMETER Key
    Overlay key.
    .OUTPUTS
    [object] Overlay value or null.
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
    if ($Entry['x-hve'].Contains($Key)) {
        return $Entry['x-hve'][$Key]
    }
    return $null
}

function Test-MarketplaceEntryEligible {
    <#
    .SYNOPSIS
    Checks package eligibility for a release channel.
    .PARAMETER Entry
    Marketplace entry.
    .PARAMETER Channel
    Stable or PreRelease channel.
    .OUTPUTS
    [bool] True when the package is eligible.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Entry,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Stable', 'PreRelease')]
        [string]$Channel
    )

    $maturity = Get-MarketplaceEntryMaturity -Entry $Entry
    if ($maturity -in @('deprecated', 'removed')) {
        return $false
    }
    return ($Channel -eq 'PreRelease' -or $maturity -ne 'experimental')
}

function Get-MarketplacePackageRecipe {
    <#
    .SYNOPSIS
    Projects a marketplace entry into a channel-filtered recipe.
    .PARAMETER Entry
    Marketplace entry.
    .PARAMETER Channel
    Stable or PreRelease channel.
    .OUTPUTS
    [hashtable[]] Component recipe.
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
    $overlayValue = Get-MarketplaceEntryOverlayValue -Entry $Entry -Key 'componentMaturity'
    if ($overlayValue -is [System.Collections.IDictionary]) {
        foreach ($key in $overlayValue.Keys) {
            $componentMaturity[[string]$key] = [string]$overlayValue[$key]
        }
    }

    $items = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($field in (Get-MarketplaceComponentFieldMap).Keys) {
        if (-not $Entry.Contains($field) -or $null -eq $Entry[$field]) {
            continue
        }
        foreach ($packagePath in @($Entry[$field]) | Sort-Object -Unique) {
            $component = Resolve-MarketplaceComponentSource -PackagePath ([string]$packagePath) -Field $field
            $maturity = if ($componentMaturity.ContainsKey($component.PackagePath)) {
                Resolve-StrictSafeMaturity -Maturity $componentMaturity[$component.PackagePath] -Source "marketplace entry '$($Entry['name'])' component '$($component.PackagePath)'"
            }
            else {
                'stable'
            }
            if ($allowed -contains $maturity) {
                $items.Add(@{ Kind = $component.Kind; Field = $field; PackagePath = $component.PackagePath; SourcePath = $component.SourcePath; Maturity = $maturity })
            }
        }
    }
    return [hashtable[]]$items.ToArray()
}

function Test-MarketplaceEntryContract {
    <#
    .SYNOPSIS
    Validates marketplace membership and x-hve metadata.
    .PARAMETER Entry
    Marketplace entry.
    .OUTPUTS
    [string[]] Contract errors.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Entry
    )

    $errors = @()
    $declared = @{}
    foreach ($field in (Get-MarketplaceComponentFieldMap).Keys) {
        if (-not $Entry.Contains($field)) {
            continue
        }
        $value = $Entry[$field]
        if ($null -eq $value) {
            $errors += "component field '$field' must be a path string or an array of path strings"
            continue
        }
        if ($field -eq 'hooks' -and $value -isnot [string]) {
            $errors += "component field 'hooks' must be a single path string"
            continue
        }
        if ($value -isnot [string] -and $value -isnot [System.Collections.IEnumerable]) {
            $errors += "component field '$field' must be a path string or an array of path strings"
            continue
        }
        $values = @($value)
        if ($values.Count -eq 0) {
            $errors += "component field '$field' must declare at least one path"
            continue
        }
        $seen = @{}
        foreach ($item in $values) {
            if ($item -isnot [string]) {
                $errors += "component field '$field' must contain only path strings"
                continue
            }
            $resolved = Resolve-MarketplaceComponentPath -Path $item
            if ($resolved.Error) {
                $errors += "component field '$field': $($resolved.Error)"
                continue
            }
            if ($seen.ContainsKey($resolved.Path)) {
                $errors += "component field '$field' declares duplicate path '$($resolved.Path)'"
                continue
            }
            $seen[$resolved.Path] = $true
            if ($declared.ContainsKey($resolved.Path)) {
                $errors += "component path '$($resolved.Path)' is declared in both '$($declared[$resolved.Path])' and '$field'"
            }
            else {
                $declared[$resolved.Path] = $field
            }
        }
    }

    if ($Entry.Contains('author')) {
        $author = $Entry['author']
        if ($author -isnot [System.Collections.IDictionary] -or -not $author.Contains('name') -or [string]::IsNullOrWhiteSpace([string]$author['name'])) {
            $errors += 'author must be an object containing a non-empty name'
        }
        elseif ($author.Contains('url') -and ([string]$author['url'] -notmatch '^https://\S+$')) {
            $errors += 'author.url must be an absolute https URL when provided'
        }
    }

    if (-not $Entry.Contains('x-hve')) {
        return [string[]]$errors
    }
    $overlay = $Entry['x-hve']
    if ($overlay -isnot [System.Collections.IDictionary]) {
        return [string[]]($errors + 'x-hve must be an object')
    }
    foreach ($key in $overlay.Keys) {
        if ((Get-MarketplaceMetadataKey) -notcontains $key) {
            $errors += "x-hve contains unsupported key '$key'"
        }
    }
    if ($overlay.Contains('displayName') -and [string]::IsNullOrWhiteSpace([string]$overlay['displayName'])) {
        $errors += 'x-hve.displayName must be a non-empty string'
    }

    $vocabulary = Get-MaturityVocabulary
    if ($overlay.Contains('maturity') -and ($overlay['maturity'] -isnot [string] -or $vocabulary -notcontains $overlay['maturity'])) {
        $errors += "x-hve.maturity '$($overlay['maturity'])' must be one of: $($vocabulary -join ', ')"
    }
    if ($overlay.Contains('componentMaturity')) {
        if ($overlay['componentMaturity'] -isnot [System.Collections.IDictionary]) {
            $errors += 'x-hve.componentMaturity must be an object keyed by component path'
        }
        else {
            foreach ($key in $overlay['componentMaturity'].Keys) {
                $resolved = Resolve-MarketplaceComponentPath -Path ([string]$key)
                if ($resolved.Error) {
                    $errors += "x-hve.componentMaturity: $($resolved.Error)"
                }
                elseif ($resolved.Path -ne [string]$key) {
                    $errors += "x-hve.componentMaturity key '$key' must be a normalized component path"
                }
                $maturity = $overlay['componentMaturity'][$key]
                if ($maturity -isnot [string] -or $vocabulary -notcontains $maturity) {
                    $errors += "x-hve.componentMaturity['$key'] value '$maturity' must be one of: $($vocabulary -join ', ')"
                }
            }
        }
    }
    if ($overlay.Contains('documentation')) {
        $documentation = $overlay['documentation']
        if ($documentation -isnot [string]) {
            $errors += 'x-hve.documentation must be a repository-relative path string'
        }
        else {
            $resolved = Resolve-MarketplaceComponentPath -Path $documentation
            if ($resolved.Error) {
                $errors += "x-hve.documentation: $($resolved.Error)"
            }
            elseif ($resolved.Path -ne $documentation) {
                $errors += "x-hve.documentation '$documentation' must be a normalized repository-relative path"
            }
        }
    }
    if ($overlay.Contains('aggregate') -and $overlay['aggregate'] -isnot [bool]) {
        $errors += 'x-hve.aggregate must be a boolean'
    }
    return [string[]]$errors
}

function ConvertTo-MarketplaceAgentKey {
    <#
    .SYNOPSIS
    Normalizes an agent handoff target.
    .PARAMETER Name
    Display name or file stem.
    .OUTPUTS
    [string] Comparable agent key.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Name
    )

    return (($Name -replace '[^A-Za-z0-9]+', '-').Trim('-')).ToLowerInvariant()
}

function Get-MarketplaceAgentIndex {
    <#
    .SYNOPSIS
    Builds a handoff index from catalog-declared agents.
    .PARAMETER Catalog
    Parsed marketplace catalog.
    .PARAMETER RepoRoot
    Repository root.
    .OUTPUTS
    [hashtable] Lookup and ambiguous keys.
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
        if ([string]::IsNullOrWhiteSpace($Key)) { return }
        if (-not $lookup.ContainsKey($Key)) {
            $lookup[$Key] = $Descriptor
        }
        elseif ($lookup[$Key].SourcePath -ne $Descriptor.SourcePath) {
            if (-not $ambiguous.ContainsKey($Key)) {
                $ambiguous[$Key] = @($lookup[$Key].SourcePath)
            }
            $ambiguous[$Key] = @($ambiguous[$Key] + $Descriptor.SourcePath | Sort-Object -Unique)
        }
    }

    foreach ($entry in @($Catalog['plugins'])) {
        foreach ($packagePath in @($entry['agents'])) {
            if ([string]::IsNullOrWhiteSpace([string]$packagePath)) { continue }
            $component = Resolve-MarketplaceComponentSource -PackagePath ([string]$packagePath) -Field 'agents'
            if ($seenSources.ContainsKey($component.SourcePath)) { continue }
            $absolute = Join-Path -Path $RepoRoot -ChildPath $component.SourcePath
            $handoffs = @()
            $displayName = ''
            if (Test-Path -LiteralPath $absolute -PathType Leaf) {
                $content = Get-Content -LiteralPath $absolute -Raw -Encoding utf8
                if ($content -match '(?s)^---\s*\r?\n(.*?)\r?\n---') {
                    try {
                        $frontmatter = ConvertFrom-Yaml -Yaml ($Matches[1] -replace '\r\n', "`n" -replace '\r', "`n")
                        if ($frontmatter -is [System.Collections.IDictionary]) {
                            if ($frontmatter.Contains('name')) { $displayName = [string]$frontmatter['name'] }
                            foreach ($handoff in @($frontmatter['handoffs'])) {
                                if ($handoff -is [string]) { $handoffs += $handoff }
                                elseif ($handoff -is [System.Collections.IDictionary] -and $handoff.Contains('agent')) { $handoffs += [string]$handoff['agent'] }
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
            $descriptor = @{ PackagePath = $component.PackagePath; SourcePath = $component.SourcePath; Handoffs = @($handoffs) }
            $seenSources[$component.SourcePath] = $descriptor
            & $addKey (ConvertTo-MarketplaceAgentKey -Name $stem) $descriptor
            if ($displayName) { & $addKey (ConvertTo-MarketplaceAgentKey -Name $displayName) $descriptor }
        }
    }
    return @{ Lookup = $lookup; Ambiguous = $ambiguous }
}

function Expand-MarketplaceAgentDependency {
    <#
    .SYNOPSIS
    Closes transitive agent handoff dependencies.
    .PARAMETER Index
    Agent index.
    .PARAMETER SeedPackagePaths
    Declared package agent paths.
    .PARAMETER PackageName
    Package name for errors.
    .OUTPUTS
    [string[]] Closed sorted agent paths.
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
        if (-not $descriptor) { throw "Package '$PackageName' declares agent '$seed', which is absent from the catalog agent index." }
        if ($resolved.Add($descriptor.PackagePath)) { $queue.Enqueue($descriptor) }
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
            if ($resolved.Add($descriptor.PackagePath)) { $queue.Enqueue($descriptor) }
        }
    }
    return [string[]]@($resolved | Sort-Object)
}

function Get-MarketplaceResolvedPackageRecipe {
    <#
    .SYNOPSIS
    Returns the channel-filtered, handoff-closed package recipe.
    .PARAMETER Entry
    Marketplace entry.
    .PARAMETER Channel
    Stable or PreRelease channel.
    .PARAMETER AgentIndex
    Catalog agent index.
    .OUTPUTS
    [hashtable[]] Resolved package recipe.
    #>
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Entry,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Stable', 'PreRelease')]
        [string]$Channel,

        [Parameter(Mandatory = $true)]
        [hashtable]$AgentIndex
    )

    $items = @(Get-MarketplacePackageRecipe -Entry $Entry -Channel $Channel)
    $seedAgents = @($items | Where-Object { $_.Kind -eq 'agent' } | ForEach-Object { $_.PackagePath })
    foreach ($agentPath in Expand-MarketplaceAgentDependency -Index $AgentIndex -SeedPackagePaths $seedAgents -PackageName ([string]$Entry['name'])) {
        if ($seedAgents -contains $agentPath) { continue }
        $component = Resolve-MarketplaceComponentSource -PackagePath $agentPath -Field 'agents'
        $items += @{ Kind = $component.Kind; Field = 'agents'; PackagePath = $component.PackagePath; SourcePath = $component.SourcePath; Maturity = 'stable' }
    }
    return [hashtable[]]@($items | Sort-Object { $_.Field }, { $_.PackagePath })
}

function Get-MarketplaceSourceIndex {
    <#
    .SYNOPSIS
    Builds a source-to-package index from resolved marketplace recipes.
    .PARAMETER Catalog
    Parsed marketplace catalog.
    .PARAMETER RepoRoot
    Repository root.
    .PARAMETER Channel
    Stable or PreRelease channel.
    .OUTPUTS
    [hashtable] Source paths to package descriptors.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Catalog,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Stable', 'PreRelease')]
        [string]$Channel
    )

    $index = @{}
    $agentIndex = Get-MarketplaceAgentIndex -Catalog $Catalog -RepoRoot $RepoRoot
    foreach ($entry in @($Catalog['plugins']) | Sort-Object { $_['name'] }) {
        if (-not (Test-MarketplaceEntryEligible -Entry $entry -Channel $Channel)) { continue }
        foreach ($item in Get-MarketplaceResolvedPackageRecipe -Entry $entry -Channel $Channel -AgentIndex $agentIndex) {
            if (-not $index.ContainsKey($item.SourcePath)) {
                $index[$item.SourcePath] = @()
            }
            $index[$item.SourcePath] += @{
                PackageName = [string]$entry['name']
                PackagePath = $item.PackagePath
                Kind        = $item.Kind
                Maturity    = $item.Maturity
            }
        }
    }
    return $index
}

function Get-MarketplaceSourcePolicyIndex {
    <#
    .SYNOPSIS
    Builds a source-to-package policy index including maturity tombstones.
    .PARAMETER Catalog
    Parsed marketplace catalog.
    .OUTPUTS
    [hashtable] Source paths to package, component, and maturity records.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Catalog
    )

    $index = @{}
    foreach ($entry in @($Catalog['plugins']) | Sort-Object { $_['name'] }) {
        $componentMaturity = Get-MarketplaceEntryOverlayValue -Entry $entry -Key 'componentMaturity'
        if ($componentMaturity -isnot [System.Collections.IDictionary]) {
            $componentMaturity = @{}
        }

        $packagePaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($field in (Get-MarketplaceComponentFieldMap).Keys) {
            foreach ($packagePath in @($entry[$field])) {
                if (-not [string]::IsNullOrWhiteSpace([string]$packagePath)) {
                    [void]$packagePaths.Add([string]$packagePath)
                }
            }
        }
        foreach ($packagePath in $componentMaturity.Keys) {
            [void]$packagePaths.Add([string]$packagePath)
        }

        foreach ($packagePath in $packagePaths) {
            $field = ([string]$packagePath -split '/', 2)[0]
            if ((Get-MarketplaceComponentFieldMap).Keys -notcontains $field) {
                continue
            }
            $component = Resolve-MarketplaceComponentSource -PackagePath $packagePath -Field $field
            $maturity = if ($componentMaturity.Contains($component.PackagePath)) {
                Resolve-StrictSafeMaturity -Maturity ([string]$componentMaturity[$component.PackagePath]) -Source "marketplace entry '$($entry['name'])' component '$($component.PackagePath)'"
            }
            else {
                'stable'
            }
            if (-not $index.ContainsKey($component.SourcePath)) {
                $index[$component.SourcePath] = @()
            }
            $index[$component.SourcePath] += @{
                PackageName = [string]$entry['name']
                PackagePath = $component.PackagePath
                Kind        = $component.Kind
                Maturity    = $maturity
            }
        }
    }
    return $index
}

function Get-MarketplaceSourceMaturity {
    <#
    .SYNOPSIS
    Returns the most restrictive maturity for one canonical source path.
    .PARAMETER Index
    Source policy index from Get-MarketplaceSourcePolicyIndex.
    .PARAMETER SourcePath
    Canonical repository source path.
    .OUTPUTS
    [string] Most restrictive maturity, or null when the source is undeclared.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Index,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourcePath
    )

    if (-not $Index.ContainsKey($SourcePath)) {
        return $null
    }
    $rank = Get-MaturityRank
    return @($Index[$SourcePath] | Sort-Object { $rank[$_.Maturity] } -Descending | Select-Object -First 1)[0].Maturity
}

Export-ModuleMember -Function @(
    'ConvertTo-MarketplaceAgentKey',
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
    'Get-MarketplaceResolvedPackageRecipe',
    'Get-MarketplaceSourceIndex',
    'Get-MarketplaceSourceMaturity',
    'Get-MarketplaceSourcePolicyIndex',
    'Get-PluginItemName',
    'Get-PluginItemSubpath',
    'Get-PluginSubdirectory',
    'Resolve-MarketplaceComponentPath',
    'Resolve-MarketplaceComponentSource',
    'Test-MarketplaceEntryContract',
    'Test-MarketplaceEntryEligible'
)
