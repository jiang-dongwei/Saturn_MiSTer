[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SdRoot,
    [ValidateSet('8.47', '16.93', '33.87', '50.80')]
    [string]$Frequency = '16.93',
    [string]$PackageRoot = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    $PackageRoot = $PSScriptRoot
}
function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $hasher.Dispose()
        $stream.Dispose()
    }
}
$coreName = 'Saturn_APS6408_Game_20261012.rbf'
$coreSha = '34031f562b05b7c49b33c9d33ed1f98f50883b7ee75ef60139755d859fc6f17b'
$diagnosticSha = '56aa111b2ed97d1d780ba4f139734501b0567c3e8641b1c1beb597bb8c640382'
$source = Join-Path $PackageRoot "SD/_Console/$coreName"
if (!(Test-Path -LiteralPath $source -PathType Leaf)) {
    throw 'Core file missing. Run the installer from the extracted game test package.'
}
if ((Get-Sha256 $source) -ne $coreSha) {
    throw 'Core SHA256 mismatch. Leave the SD card unchanged.'
}
$root = (Resolve-Path -LiteralPath $SdRoot).ProviderPath.TrimEnd('\') + '\'
if ($root -notmatch '^[A-Za-z]:\\$' -or $root.TrimEnd('\') -eq $env:SystemDrive) {
    throw 'Specify the root of a MiSTer SD card, for example -SdRoot H:\.'
}
foreach ($marker in @('MiSTer', 'menu.rbf')) {
    if (!(Test-Path -LiteralPath (Join-Path $root $marker) -PathType Leaf)) {
        throw "MiSTer SD card marker missing: $marker"
    }
}

$cfgPath = Join-Path $root 'config/Saturn.CFG'
$cfg = [byte[]]::new(16)
if (Test-Path -LiteralPath $cfgPath -PathType Leaf) {
    $cfg = [IO.File]::ReadAllBytes($cfgPath)
    if ($cfg.Length -ne 16) {
        throw 'Unexpected Saturn.CFG format. Leave the card unchanged.'
    }
}
$mode = @{ '33.87' = 0; '16.93' = 1; '8.47' = 2; '50.80' = 3 }[$Frequency]
$cfg[10] = [byte](($cfg[10] -band 0xF3) -bor ($mode -shl 2))
$bootPath = Join-Path $root 'games/Saturn/boot.rom'
$removeDiagnostic = (Test-Path -LiteralPath $bootPath -PathType Leaf) -and
    ((Get-Sha256 $bootPath) -eq $diagnosticSha)
$backup = Join-Path $root ('aps6408-game-backups/' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
$corePath = Join-Path $root "_Console/$coreName"

New-Item -ItemType Directory -Path $backup -Force | Out-Null
foreach ($directory in @('_Console', 'config', 'games/Saturn')) {
    New-Item -ItemType Directory -Path (Join-Path $root $directory) -Force | Out-Null
}
if (Test-Path -LiteralPath $cfgPath -PathType Leaf) {
    Copy-Item -LiteralPath $cfgPath -Destination (Join-Path $backup 'Saturn.CFG')
}
if (Test-Path -LiteralPath $corePath -PathType Leaf) {
    Copy-Item -LiteralPath $corePath -Destination (Join-Path $backup $coreName)
}
if ($removeDiagnostic) {
    $savedDiagnostic = Join-Path $backup 'boot.rom.diagnostic'
    Copy-Item -LiteralPath $bootPath -Destination $savedDiagnostic
    if ((Get-Sha256 $savedDiagnostic) -ne $diagnosticSha -or
        (Get-Sha256 $bootPath) -ne $diagnosticSha) {
        throw 'Diagnostic ROM changed during backup. Leave boot.rom unchanged.'
    }
    Remove-Item -LiteralPath $bootPath
}
Copy-Item -LiteralPath $source -Destination $corePath -Force
[IO.File]::WriteAllBytes($cfgPath, $cfg)
if ((Get-Sha256 $corePath) -ne $coreSha -or
    [Convert]::ToBase64String([IO.File]::ReadAllBytes($cfgPath)) -ne [Convert]::ToBase64String($cfg)) {
    throw "Installed file verification failed. Backups: $backup"
}
Write-Output "Installed $coreName; PSRAM clock $Frequency MHz."
Write-Output "Existing Saturn settings preserved except the PSRAM frequency. Backups: $backup"
if ($removeDiagnostic) {
    Write-Output 'Self-written diagnostic boot.rom backed up and removed. Load your Saturn BIOS before playing.'
}
if (!(Test-Path -LiteralPath $bootPath -PathType Leaf)) {
    Write-Output 'No boot.rom found. Use Load bios in the Saturn menu to load your BIOS BIN.'
}
Write-Output 'Safely eject the card. Changing PSRAM clock in the core menu resets the console.'
