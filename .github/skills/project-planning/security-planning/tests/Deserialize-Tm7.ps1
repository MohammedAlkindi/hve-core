# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
    Deserialize a generated .tm7 file with the Microsoft Threat Modeling Tool's
    own DataContract serializer to prove format fidelity.

.DESCRIPTION
    Locates the installed ThreatModeling assemblies, obtains the exact
    DataContractSerializer via SerializableModelData.GetSerializer(), and calls
    ReadObject on the target file. The TMT assemblies are 32-bit, so this script
    re-launches itself under the 32-bit Windows PowerShell host when started from
    a 64-bit process.

    Exit codes:
      0  Deserialization succeeded (prints DESERIALIZE_OK).
      1  Deserialization failed    (prints DESERIALIZE_FAIL: <message>).
      3  TMT assemblies not found  (prints TMT_ASSEMBLIES_NOT_FOUND); callers
         should treat this as "skip" rather than "fail".

.PARAMETER Path
    Path to the .tm7 file to deserialize.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'

# The TMT assemblies are x86. Re-launch under the 32-bit PowerShell host when
# this process is 64-bit so the assemblies can be loaded. Windows PowerShell
# defaults to Restricted, so a policy flag is required for the child to load
# this file at all. RemoteSigned is the narrowest policy that works: it still
# enforces signature checks on files carrying mark-of-the-web, unlike Bypass.
if ([Environment]::Is64BitProcess) {
    $wow = Join-Path $env:SystemRoot 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path $wow) {
        & $wow -NoProfile -ExecutionPolicy RemoteSigned -File $PSCommandPath -Path $Path
        exit $LASTEXITCODE
    }
}

function Get-CandidateAssemblyDirectory {
    <#
    .SYNOPSIS
        Return TMT assembly directories in a deterministic order.
    .DESCRIPTION
        Roots must be absolute so an unset environment variable cannot produce
        a relative path that lets a directory beside the working directory
        contribute assemblies. Directories are ordered by path rather than by
        write time: newest modification is not a trust signal, and the two
        ClickOnce payload directories share a timestamp, so ordering by time
        selected between them arbitrarily.
    #>
    $roots = @(
        (Join-Path $env:LOCALAPPDATA 'Apps\2.0'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Threat Modeling Tool'),
        (Join-Path $env:ProgramFiles 'Microsoft Threat Modeling Tool')
    ) | Where-Object {
        $_ -and [System.IO.Path]::IsPathRooted($_) -and (Test-Path $_)
    }
    $directories = @()
    foreach ($root in $roots) {
        $found = Get-ChildItem -Recurse -Path $root `
            -Filter 'ThreatModeling.ExternalStorage.Local.dll' -ErrorAction SilentlyContinue |
            Sort-Object FullName
        foreach ($dll in $found) { $directories += $dll.Directory.FullName }
    }
    return $directories
}

$candidateDirectories = Get-CandidateAssemblyDirectory
if (-not $candidateDirectories) {
    Write-Output 'TMT_ASSEMBLIES_NOT_FOUND'
    exit 3
}

# A directory is selected because it actually resolves the required type, not
# because it sorted first. One ClickOnce payload directory carries only the
# local-storage assembly, so choosing by order alone picks a directory that
# cannot deserialize anything.
$serializableModelData = $null
foreach ($candidate in $candidateDirectories) {
    $resolved = [System.IO.Path]::GetFullPath($candidate)
    $script:assemblyDirectory = $resolved
    foreach ($assemblyFile in Get-ChildItem $resolved -Filter 'ThreatModeling*.dll') {
        try { $assembly = [Reflection.Assembly]::LoadFrom($assemblyFile.FullName) } catch { continue }
        try { $types = $assembly.GetTypes() }
        catch [System.Reflection.ReflectionTypeLoadException] { $types = $_.Exception.Types | Where-Object { $_ } }
        $hit = $types | Where-Object {
            $_ -and $_.FullName -eq 'ThreatModeling.ExternalStorage.OM.SerializableModelData'
        } | Select-Object -First 1
        if ($hit) { $serializableModelData = $hit; break }
    }
    if ($serializableModelData) { break }
}

if (-not $serializableModelData) {
    Write-Output 'TMT_ASSEMBLIES_NOT_FOUND'
    exit 3
}

# Resolution is confined to the selected installation directory. The requested
# assembly name is reduced to its file name and the resolved candidate is
# re-checked against the directory, so a name carrying path separators or
# traversal cannot escape to load an assembly from elsewhere.
[AppDomain]::CurrentDomain.add_AssemblyResolve({
        param($resolveSender, $resolveArgs)
        $name = ($resolveArgs.Name -split ',')[0]
        if ([string]::IsNullOrWhiteSpace($name)) { return $null }
        $leaf = [System.IO.Path]::GetFileName($name)
        if ($leaf -ne $name) { return $null }
        $base = $script:assemblyDirectory
        $candidate = [System.IO.Path]::GetFullPath((Join-Path $base ($leaf + '.dll')))
        if (-not $candidate.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) {
            return $null
        }
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            [Reflection.Assembly]::LoadFrom($candidate)
        }
        else { $null }
    })
Add-Type -AssemblyName System.Runtime.Serialization

$bindingFlags = [Reflection.BindingFlags]'Public,NonPublic,Static'
$getSerializer = $serializableModelData.GetMethod(
    'GetSerializer', $bindingFlags, $null, [Type]::EmptyTypes, $null)
$serializer = $getSerializer.Invoke($null, @())

$stream = $null
try {
    $stream = [System.IO.File]::OpenRead($Path)
    $null = $serializer.ReadObject($stream)
    $stream.Close()
    Write-Output 'DESERIALIZE_OK'
    exit 0
}
catch {
    if ($stream) { $stream.Close() }
    $inner = $_.Exception
    while ($inner.InnerException) { $inner = $inner.InnerException }
    Write-Output ("DESERIALIZE_FAIL: {0}" -f $inner.Message)
    exit 1
}
