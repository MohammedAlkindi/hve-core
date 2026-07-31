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
# this process is 64-bit so the assemblies can be loaded.
if ([Environment]::Is64BitProcess) {
    $wow = Join-Path $env:SystemRoot 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path $wow) {
        & $wow -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Path $Path
        exit $LASTEXITCODE
    }
}

function Find-LocalStorageDll {
    $roots = @(
        (Join-Path $env:LOCALAPPDATA 'Apps\2.0'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Threat Modeling Tool'),
        (Join-Path $env:ProgramFiles 'Microsoft Threat Modeling Tool')
    ) | Where-Object { $_ -and (Test-Path $_) }
    foreach ($root in $roots) {
        $dll = Get-ChildItem -Recurse -Path $root `
            -Filter 'ThreatModeling.ExternalStorage.Local.dll' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($dll) { return $dll.FullName }
    }
    return $null
}

$localDll = Find-LocalStorageDll
if (-not $localDll) {
    Write-Output 'TMT_ASSEMBLIES_NOT_FOUND'
    exit 3
}

$dir = Split-Path $localDll
[AppDomain]::CurrentDomain.add_AssemblyResolve({
        param($resolveSender, $resolveArgs)
        $name = ($resolveArgs.Name -split ',')[0]
        $candidate = Join-Path $dir ($name + '.dll')
        if (Test-Path $candidate) { [Reflection.Assembly]::LoadFrom($candidate) } else { $null }
    })
Add-Type -AssemblyName System.Runtime.Serialization

$serializableModelData = $null
foreach ($assemblyFile in Get-ChildItem $dir -Filter 'ThreatModeling*.dll') {
    try { $assembly = [Reflection.Assembly]::LoadFrom($assemblyFile.FullName) } catch { continue }
    try { $types = $assembly.GetTypes() }
    catch [System.Reflection.ReflectionTypeLoadException] { $types = $_.Exception.Types | Where-Object { $_ } }
    $hit = $types | Where-Object {
        $_ -and $_.FullName -eq 'ThreatModeling.ExternalStorage.OM.SerializableModelData'
    } | Select-Object -First 1
    if ($hit) { $serializableModelData = $hit; break }
}

if (-not $serializableModelData) {
    Write-Output 'TMT_ASSEMBLIES_NOT_FOUND'
    exit 3
}

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
