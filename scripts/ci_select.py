import json
import os
import re
import subprocess


# Archivos que usan ambos trabajos: el web los prueba con Python y el nativo los ejecuta al compilar.
SHARED_SCRIPTS = {'scripts/install_catalog.py', 'scripts/check_app_bundle.py', 'scripts/build_catalog.py',
                  'scripts/prepare_catalog.py', 'scripts/catalog_information.py', 'tests/catalog_http.py'}
NATIVE_PREFIXES = ('RutasTijuana/', 'NavigationWidget/', 'Config/', 'RutasTijuana.xcodeproj/', 'RutasTijuanaUITests/', 'Catalog/')
WEB_PREFIXES = ('admin/', 'preview/', 'shared/', 'supabase/')


def area(path):
    """Devuelve (web, nativo) para un archivo modificado."""
    filename = path.rsplit('/', 1)[-1]
    if path.endswith('.md'):
        return False, False
    if path in SHARED_SCRIPTS or path.startswith('Catalog/') or path.startswith('.github/'):
        return True, True
    if filename in ('Package.swift', 'Package.resolved'):
        return False, True
    if filename in ('package.json', 'pnpm-lock.yaml', 'pnpm-workspace.yaml', 'tsconfig.json', 'vite.config.ts'):
        return True, False
    if path in ('tests/main.swift', 'scripts/test-logic.sh') or path.startswith(NATIVE_PREFIXES):
        return False, True
    if path.startswith(WEB_PREFIXES) or path.startswith(('tests/', 'scripts/')):
        return True, False
    return True, True


def select(paths, event='pull_request', mode='full', draft=False):
    """Elige trabajos. Las pruebas de iPhone esperan a que el PR deje de ser borrador."""
    if event == 'workflow_dispatch':
        return {'web': mode != 'native', 'native': True, 'ui': True, 'reason': 'Ejecución manual: ' + mode}
    if event != 'pull_request' or paths is None:
        return {'web': True, 'native': True, 'ui': True, 'reason': 'Comprobación completa'}
    web = native = False
    for path in paths:
        needs_web, needs_native = area(path)
        web, native = web or needs_web, native or needs_native
    reason = 'Cambios web y nativos' if web and native else 'Cambios nativos' if native else 'Cambios web' if web else 'Documentación'
    if native and draft:
        reason += '; iPhone al marcar el PR como listo'
    return {'web': web, 'native': native, 'ui': native and not draft, 'reason': reason}


def main():
    paths = None
    try:
        base, head = os.environ.get('BASE_SHA', ''), os.environ.get('HEAD_SHA', '')
        if not re.fullmatch(r'[a-fA-F0-9]{40}', base) or not re.fullmatch(r'[a-fA-F0-9]{40}', head):
            raise ValueError('SHA')
        names = subprocess.check_output(['git', 'diff', '--name-only', '--no-renames', '-z', base, head]).decode('utf-8').split('\0')
        paths = [p for p in names if p]
    except (ValueError, subprocess.SubprocessError, UnicodeError):
        pass
    result = select(paths, os.environ.get('EVENT_NAME', ''), os.environ.get('CHECK_MODE', 'full'),
                    os.environ.get('DRAFT', '') == 'true')
    print(json.dumps(result, ensure_ascii=False))
    with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
        for key, value in result.items():
            output.write(f'{key}={str(value).lower() if isinstance(value, bool) else value}\n')


if __name__ == '__main__':
    main()
