param([Parameter(ValueFromRemainingArguments = $true)][string[]]$TaskArgs = @('dev'))
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$tools = Join-Path $projectRoot 'local-data/tools'
$node = Join-Path $tools 'node/node.exe'
if (-not (Test-Path -LiteralPath $node)) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $node) | Out-Null
    $installed = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($installed -and [int]((& $installed.Source --version).TrimStart('v').Split('.')[0]) -ge 22) {
        Copy-Item -LiteralPath $installed.Source -Destination $node
    } else {
        $version = '24.22.1'
        $archive = Join-Path $tools 'node.zip'
        $name = "node-v$version-win-x64.zip"
        $sums = (Invoke-WebRequest "https://nodejs.org/dist/v$version/SHASUMS256.txt").Content
        $expected = (($sums -split "`n" | Where-Object { $_.Trim().EndsWith($name) }) -split '\s+')[0]
        Invoke-WebRequest "https://nodejs.org/dist/v$version/$name" -OutFile $archive
        if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLower() -ne $expected) { throw 'La descarga de Node no coincide.' }
        Expand-Archive -LiteralPath $archive -DestinationPath $tools -Force
        Copy-Item -LiteralPath (Join-Path $tools "node-v$version-win-x64/node.exe") -Destination $node
    }
}
$pnpm = Join-Path $tools 'pnpm/bin/pnpm.cjs'
if (-not (Test-Path -LiteralPath $pnpm)) {
    $package = Invoke-RestMethod 'https://registry.npmjs.org/pnpm/11.25.0'
    if ([Uri]$package.dist.tarball -and ([Uri]$package.dist.tarball).Host -ne 'registry.npmjs.org') { throw 'Origen de paquete incorrecto.' }
    $archive = Join-Path $tools 'pnpm.tgz'
    Invoke-WebRequest $package.dist.tarball -OutFile $archive
    $sha = [System.Security.Cryptography.SHA512]::Create()
    try { $integrity = 'sha512-' + [Convert]::ToBase64String($sha.ComputeHash([IO.File]::ReadAllBytes($archive))) } finally { $sha.Dispose() }
    if ($integrity -ne $package.dist.integrity) { throw 'La descarga de pnpm no coincide.' }
    $directory = Join-Path $tools 'pnpm'
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    & tar.exe -xf $archive -C $directory --strip-components 1
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo preparar pnpm.' }
}
$env:Path = (Split-Path -Parent $node) + ';' + $env:Path
& $node $pnpm @TaskArgs
exit $LASTEXITCODE
