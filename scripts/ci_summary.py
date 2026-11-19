import json
import os


def successful(results):
    selection = results.get('changes', {})
    outputs = selection.get('outputs', {})
    if selection.get('result') != 'success' or any(outputs.get(key) not in ('true', 'false') for key in ('web', 'native')):
        return False
    for name in ('web', 'native', 'ui'):
        required = outputs['native' if name == 'ui' else name] == 'true'
        if results.get(name, {}).get('result') not in (('success',) if required else ('success', 'skipped')):
            return False
    return True


def main():
    results = json.loads(os.environ['JOB_RESULTS'])
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a', encoding='utf-8') as summary:
        summary.write('## Comprobaciones\n\n| Trabajo | Resultado | Duración |\n|---|---|---|\n')
        for name, value in results.items():
            duration = value.get('outputs', {}).get('seconds', '')
            summary.write(f"| {name} | {value['result']} | {duration + ' s' if duration else '—'} |\n")
        reason = results.get('changes', {}).get('outputs', {}).get('reason', '')
        summary.write('\nSelección: ' + reason + '\n\n')
        suites = {'web': 'Python, vista previa, TypeScript, panel y permisos de base de datos', 'native': 'Swift, SQLite, Release y paquete de la extensión', 'ui': 'Compilación de pruebas, instalación y suite completa de interfaz iPhone'}
        for job, description in suites.items():
            summary.write(f"- {description}: {results.get(job, {}).get('result', 'no ejecutado')}.\n")
        summary.write('\nLos trabajos omitidos corresponden a la selección de archivos o al modo manual. Una cancelación o fallo no se considera aprobación.\n')
    if not successful(results):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
