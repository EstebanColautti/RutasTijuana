import json
import os
import re
import subprocess


def select(paths, event='pull_request', mode='full'):
    if event == 'workflow_dispatch':
        return {'web': mode != 'native', 'native': True, 'reason': 'Ejecución manual: ' + mode}
    if event != 'pull_request' or paths is None:
        return {'web': True, 'native': True, 'reason': 'Comprobación completa'}
    web = native = False
    for path in paths:
        parts = path.split('/')
        filename = parts[-1]
        if any(part.lower() in ('tests', '__tests__', 'rutastijuanauitests') for part in parts) or re.search(r'\.(test|spec)\.', filename) or filename in ('package.json', 'pnpm-lock.yaml', 'pnpm-workspace.yaml', 'Package.swift', 'Package.resolved'):
            return {'web': True, 'native': True, 'reason': 'Pruebas o dependencias'}
        if path.endswith('.md'):
            continue
        if path.startswith(('admin/', 'preview/', 'shared/')):
            web = True
        elif path.startswith(('RutasTijuana/', 'NavigationWidget/', 'Config/', 'RutasTijuana.xcodeproj/', 'RutasTijuanaUITests/')):
            native = True
        else:
            return {'web': True, 'native': True, 'reason': 'Cambios compartidos o configuración'}
    return {'web': web, 'native': native, 'reason': 'Cambios web y nativos' if web and native else 'Cambios nativos' if native else 'Cambios web' if web else 'Documentación'}


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
    result = select(paths, os.environ.get('EVENT_NAME', ''), os.environ.get('CHECK_MODE', 'full'))
    print(json.dumps(result, ensure_ascii=False))
    with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
        for key, value in result.items():
            output.write(f'{key}={str(value).lower() if isinstance(value, bool) else value}\n')


if __name__ == '__main__':
    main()
