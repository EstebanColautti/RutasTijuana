param([ValidateSet('start','api','stop')][string]$Action = 'start')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$wslArgs = @()
if ($env:RUTAS_WSL_DISTRO) { $wslArgs += @('--distribution', $env:RUTAS_WSL_DISTRO) }
$linuxRoot = & wsl.exe @wslArgs --exec wslpath -a $projectRoot
if ($LASTEXITCODE -ne 0) { throw 'No se pudo abrir el entorno Linux local.' }
$linuxRoot = $linuxRoot.Trim()
& wsl.exe @wslArgs --exec bash "$linuxRoot/scripts/local-stack.sh" $Action
if ($LASTEXITCODE -ne 0) { throw 'Revisa los registros locales en local-data.' }
if ($Action -eq 'start') {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'package.ps1') install --frozen-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'No se pudieron preparar las dependencias.' }
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'package.ps1') exec node scripts/local-config.mjs
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo preparar el acceso local.' }
}
