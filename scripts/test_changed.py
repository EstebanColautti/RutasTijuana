"""Prueba rápida por iteración: corre solo lo que corresponde a los archivos modificados.

Uso:
    python3 scripts/test_changed.py              # cambios sin commit respecto a HEAD
    python3 scripts/test_changed.py --base main  # cambios respecto a otra referencia
    python3 scripts/test_changed.py --dry-run    # solo muestra el plan
    python3 scripts/test_changed.py --max 0      # sin límite de pruebas de interfaz
    python3 scripts/test_changed.py --test testListsLifecycle --device UUID

La lógica Swift y Python tardan segundos. Las pruebas de interfaz se limitan por defecto a
las 4 más relevantes en el iPhone 17. La matriz completa y el compacto quedan para el cierre
del lote y la CI (ver docs/DESARROLLO.md).
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Archivos que compila scripts/test-logic.sh.
LOGIC_FILES = {
    'FavoriteRoutes.swift', 'TransitRoute.swift', 'RouteCatalog.swift', 'CatalogPublic.swift',
    'CatalogPackage.swift', 'JourneyScenario.swift', 'CatalogSync.swift', 'CatalogCache.swift',
    'WalkingNavigation.swift', 'TransitProgress.swift', 'TripPlanner.swift', 'RouteAccess.swift',
}

# Área de la app → pruebas de interfaz, de la más a la menos representativa.
UI_AREAS = [
    (r'RutasTijuana/(AppDesign|RutasTijuanaApp)\.swift$|RutasTijuana/(Assets\.xcassets|Typography)/',
     ['testMainNavigation', 'testDockSelectionStaysPutWithKeyboard', 'testCurrentScreensAccessibilityAudit']),
    (r'RutasTijuana/(TripPlannerView|LocationService)\.swift$',
     ['testMainNavigation', 'testDockFinishesActiveTrip']),
    (r'RutasTijuana/(TripTravelView|TransitProgress|NavigationActivityController|NavigationAttributes)\.swift$',
     ['testDockFinishesActiveTrip', 'testHomeWalkingBadge']),
    (r'RutasTijuana/(TripPlanner|RouteAccess|TransitRoute)\.swift$',
     ['testDockFinishesActiveTrip']),
    (r'RutasTijuana/(WalkingNavigation|WalkingNavigationView|AppleWalkingNavigation)\.swift$',
     ['testHomeWalkingBadge']),
    (r'RutasTijuana/CatalogView\.swift$',
     ['testRoutesInlineSearchAndTools', 'testListsLifecycle', 'testFavoritesTabFromRouteCard', 'testRoutesServicesWithNotices']),
    (r'RutasTijuana/(RouteCatalog|CatalogRepository|CatalogPackage|CatalogPublic|CatalogCache|CatalogSync|CatalogPhoto|FavoriteRoutes)\.swift$',
     ['testRoutesTabAndLists', 'testCatalogPersistsAcrossLaunches']),
    (r'^Catalog/',
     ['testFullCatalogOffline']),
    (r'^(Config/|RutasTijuana\.xcodeproj/)',
     ['testMainNavigation']),
]

NATIVE = re.compile(r'^(RutasTijuana/|NavigationWidget/|Config/|RutasTijuana\.xcodeproj/|RutasTijuanaUITests/|Catalog/)')
PYTHON = re.compile(r'^(scripts/.*\.py|tests/.*\.py|Catalog/)')
WEB = re.compile(r'^(admin/|preview/|shared/|supabase/|tests/.*\.(ts|tsx|cjs)$|package\.json|pnpm-lock\.yaml)')


def changed_test_names(diff_text):
    """Pruebas XCTest añadidas o editadas, según el contexto de cada bloque del diff."""
    names = []
    for line in diff_text.splitlines():
        match = re.search(r'func (test\w+)\(', line) if line.startswith(('@@', '+')) else None
        if match and match.group(1) not in names:
            names.append(match.group(1))
    return names


def plan(paths, ui_diff='', limit=4):
    """Decide qué correr para una lista de archivos modificados."""
    result = {'logic': False, 'python': False, 'build': False, 'web': False, 'ui': [], 'skipped': []}
    tests = []
    for path in paths:
        name = path.rsplit('/', 1)[-1]
        if path.endswith('.md'):
            continue
        if path == 'tests/main.swift' or path == 'scripts/test-logic.sh' or (path.startswith('RutasTijuana/') and name in LOGIC_FILES):
            result['logic'] = True
        if PYTHON.search(path):
            result['python'] = True
        if WEB.search(path):
            result['web'] = True
        if NATIVE.search(path):
            result['build'] = True
        for pattern, area_tests in UI_AREAS:
            if re.search(pattern, path):
                tests += [t for t in area_tests if t not in tests]
    if any(p.startswith('RutasTijuanaUITests/') for p in paths):
        tests = [t for t in changed_test_names(ui_diff) if t not in tests] + tests
    if result['build'] and not tests:
        tests = ['testMainNavigation']
    result['ui'] = tests if limit <= 0 else tests[:limit]
    result['skipped'] = [] if limit <= 0 else tests[limit:]
    return result


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True)


def changed_paths(base):
    tracked = git('diff', '--name-only', '--no-renames', base).split('\n')
    untracked = git('ls-files', '--others', '--exclude-standard').split('\n')
    return sorted({p for p in tracked + untracked if p})


def default_device():
    devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j'], text=True))
    phones = [d for group in devices['devices'].values() for d in group if 'iPhone 17' in d['name'] and 'Pro' not in d['name']]
    booted = [d for d in phones if d['state'] == 'Booted']
    chosen = (booted or phones or [None])[0]
    return chosen['udid'] if chosen else None


def device_name(udid):
    devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '-j'], text=True))
    for group in devices['devices'].values():
        for device in group:
            if device['udid'] == udid:
                return device['name']
    return udid


def run_tests(step, command, captures=False):
    """Corre XCTest y muestra solo el resultado de cada caso y los errores."""
    print(f'\n▶ {step}', flush=True)
    env = dict(os.environ)
    if not captures:
        env['TEST_RUNNER_CAPTURE'] = '0'  # XCTest recibe CAPTURE=0: sin capturas de evidencia
    completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, env=env)
    for line in completed.stdout.splitlines():
        if re.search(r"Test Case .*(passed|failed)|error: .*JourneyTests|Executed \d+ tests|^\[[^]]+\] XCUIAccessibilityAuditType", line):
            print('  ' + line.strip())
    if completed.returncode != 0:
        print(f'✗ {step} falló', flush=True)
    return completed.returncode == 0


def run(step, command):
    print(f'\n▶ {step}', flush=True)
    completed = subprocess.run(command, cwd=ROOT)
    if completed.returncode != 0:
        print(f'✗ {step} falló', flush=True)
    return completed.returncode == 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--base', default='HEAD', help='Referencia de comparación (por defecto HEAD)')
    parser.add_argument('--device', help='UUID del simulador (por defecto el iPhone 17)')
    parser.add_argument('--max', type=int, default=4, help='Máximo de pruebas de interfaz (0 = todas)')
    parser.add_argument('--dry-run', action='store_true', help='Muestra el plan sin ejecutarlo')
    parser.add_argument('--test', action='append', default=[], help='Prueba de interfaz concreta (repetible); sustituye la selección')
    parser.add_argument('--captures', action='store_true', help='Guarda las capturas de evidencia (por defecto solo las de fallos)')
    args = parser.parse_args()

    paths = changed_paths(args.base)
    ui_diff = git('diff', '-U0', args.base, '--', 'RutasTijuanaUITests/') if any(p.startswith('RutasTijuanaUITests/') for p in paths) else ''
    steps = plan(paths, ui_diff, args.max)
    if args.test:
        steps.update(ui=args.test, skipped=[], build=True)
    print(f'Archivos modificados: {len(paths)}')
    print('Lógica Swift:', 'sí' if steps['logic'] else 'no', '· Python:', 'sí' if steps['python'] else 'no',
          '· Compilación:', 'sí' if steps['build'] else 'no')
    print('Interfaz:', ', '.join(steps['ui']) or 'ninguna')
    if steps['skipped']:
        print('Quedan para el cierre del lote (--max 0):', ', '.join(steps['skipped']))
    if steps['web']:
        print('Panel y web: corre «pnpm test» (requiere Node 22+ y pnpm).')
    if args.dry_run:
        return 0

    ok = True
    if steps['logic']:
        ok &= run('Lógica Swift', ['bash', 'scripts/test-logic.sh'])
    if steps['python']:
        ok &= run('Python', [sys.executable, '-m', 'unittest', 'discover', '-s', 'tests'])
    if steps['build']:
        device = args.device or default_device()
        if not device:
            print('No hay un iPhone 17 disponible en Simulator; indica --device.')
            return 1
        derived = ROOT / 'build' / 'test-changed'
        common = ['xcodebuild', '-project', 'RutasTijuana.xcodeproj', '-scheme', 'RutasTijuana',
                  '-destination', f'platform=iOS Simulator,id={device}', '-derivedDataPath', str(derived),
                  'CODE_SIGNING_ALLOWED=NO', 'COMPILER_INDEX_STORE_ENABLE=NO', '-quiet']
        subprocess.run(['xcrun', 'simctl', 'boot', device], cwd=ROOT, capture_output=True)
        subprocess.run(['xcrun', 'simctl', 'ui', device, 'appearance', 'light'], cwd=ROOT, capture_output=True)
        if not run('Compilación incremental', [*common, 'CATALOG_FIXTURE=YES', 'build-for-testing']):
            return 1
        app = derived / 'Build' / 'Products' / 'Debug-iphonesimulator' / 'RutasTijuana.app'
        executable = app / 'RutasTijuana.debug.dylib'
        if not executable.exists():
            executable = app / 'RutasTijuana'
        build_id = f'{executable.stat().st_mtime_ns}:{executable.stat().st_size}'
        stamp = derived / f'instalada-{device[:8]}.txt'
        container = subprocess.run(['xcrun', 'simctl', 'get_app_container', device, 'com.estebancolautti.rutastijuana'],
                                   capture_output=True, text=True).stdout.strip()
        installed = Path(container) / executable.name if container else None
        same_build = (installed is not None and installed.exists()
                      and installed.stat().st_size == executable.stat().st_size)
        if not same_build or not stamp.exists() or stamp.read_text() != build_id:
            subprocess.run([sys.executable, 'scripts/install_catalog.py', '--source', 'Catalog',
                            '--destination', str(app / 'Full' / 'Catalog.bundle')], cwd=ROOT, check=True, capture_output=True)
            subprocess.run(['xcrun', 'simctl', 'install', device, str(app)], cwd=ROOT, check=True)
            stamp.write_text(build_id)
        else:
            print('App sin cambios: se reutiliza la instalación.')
        if steps['ui']:
            result = derived / f'ultima-{device[:8]}.xcresult'
            subprocess.run(['rm', '-rf', str(result)])
            selected = [f'-only-testing:RutasTijuanaUITests/JourneyTests/{t}' for t in steps['ui']]
            testing = [c for c in common if c != '-quiet']
            ok &= run_tests('Interfaz en ' + device_name(device), [*testing, '-parallel-testing-enabled', 'NO', '-resultBundlePath', str(result),
                                                                  *selected, 'test-without-building'], args.captures)
            print(f'Resultados y capturas: {result}')
    print('\n' + ('✓ Todo correcto' if ok else '✗ Hay fallos'))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
