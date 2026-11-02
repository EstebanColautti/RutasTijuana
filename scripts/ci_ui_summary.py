import json
import sys

with open(sys.argv[1], encoding='utf-8') as file:
    result = json.load(file)
with open(sys.argv[2], 'a', encoding='utf-8') as summary:
    summary.write('## Interfaz iPhone\n\n| Pruebas | Resultado |\n|---|---|\n')
    for key, label in [('totalTestCount', 'Ejecutadas'), ('passedTests', 'Correctas'), ('failedTests', 'Fallidas'), ('skippedTests', 'Omitidas')]:
        if key in result:
            summary.write(f'| {label} | {result[key]} |\n')
    summary.write('\nCapturas y diagnósticos disponibles en el artefacto `iPhone-tests`.\n')
