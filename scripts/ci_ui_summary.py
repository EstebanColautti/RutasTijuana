import html
import json
from pathlib import Path
import sys


def inline(value):
    return html.escape(str(value).replace("\r", "").replace("\n", " · ")).replace("|", "&#124;")


def render(result, profile):
    lines = [f"### iPhone ({inline(profile)})", ""]
    if not result:
        return "\n".join(lines + ["Sin resultado de XCTest. Revisa el arranque o la compilación.", ""])
    counts = [("totalTestCount", "Ejecutadas"), ("passedTests", "Correctas"),
              ("failedTests", "Fallidas"), ("skippedTests", "Omitidas")]
    lines += [" · ".join(f"{label}: {result.get(key, 0)}" for key, label in counts), ""]
    failures = result.get("testFailures", [])
    if failures:
        lines += ["| Caso | Diagnóstico |", "| --- | --- |"]
        for failure in failures:
            case = failure.get("testIdentifierString") or failure.get("testName") or "Sin identificador"
            message = failure.get("failureText") or "Consulta el resultado de XCTest."
            lines.append(f"| {inline(case)} | {inline(message)} |")
        lines.append("")
    return "\n".join(lines)


def load(path):
    return json.loads(path.read_text(encoding="utf-8")) if path.is_file() else None


def main():
    source, output = map(Path, sys.argv[1:3])
    with output.open("a", encoding="utf-8") as summary:
        summary.write("\n## Diagnóstico de interfaz\n\n")
        if len(sys.argv) == 4:
            summary.write(render(load(source), sys.argv[3]))
        else:
            for profile in ("standard", "compact"):
                result = load(source / f"iPhone-summary-{profile}" / "ui-summary.json")
                summary.write(render(result, profile) + "\n")
        summary.write("\nRegistros, capturas, jerarquías y resultados de XCTest en los artefactos `iPhone-tests`.\n")


if __name__ == "__main__":
    main()
