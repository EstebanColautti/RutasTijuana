$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
$sdkRoot = [Environment]::GetEnvironmentVariable('SDKROOT', 'User')
if (-not $sdkRoot) { $sdkRoot = [Environment]::GetEnvironmentVariable('SDKROOT', 'Machine') }
if ($sdkRoot) { $env:SDKROOT = $sdkRoot }
$compiler = Get-Command swiftc -ErrorAction SilentlyContinue
if (-not $compiler) { throw 'No se encontro Swift en PATH. Reinicia VS Code despues de instalarlo.' }
$buildPath = Join-Path $projectRoot 'build'
New-Item -ItemType Directory -Force -Path $buildPath | Out-Null
$executable = Join-Path $buildPath 'route-tests.exe'
& $compiler.Source (Join-Path $projectRoot 'RutasTijuana\TransitRoute.swift') (Join-Path $projectRoot 'RutasTijuana\RouteCatalog.swift') (Join-Path $projectRoot 'RutasTijuana\JourneyScenario.swift') (Join-Path $projectRoot 'RutasTijuana\CatalogSync.swift') (Join-Path $projectRoot 'RutasTijuana\CatalogCache.swift') (Join-Path $projectRoot 'tests\main.swift') -o $executable
if ($LASTEXITCODE -ne 0) { throw 'No se pudieron compilar las pruebas.' }
& $executable
if ($LASTEXITCODE -ne 0) { throw 'Fallaron las pruebas de lógica.' }
