import os
import re
from pathlib import Path


def selected_tests(value, source):
    methods = [part.strip() for part in value.split(",")]
    available = set(re.findall(r"^\s*func (test\w+)\(\)", source.split("#if LIVE_MAP_CAPTURE", 1)[0], re.M))
    if not all(methods) or any(method not in available for method in methods):
        raise ValueError("Indica nombres de pruebas existentes separados por comas.")
    return list(dict.fromkeys(methods))


if __name__ == "__main__":
    source = Path("RutasTijuanaUITests/JourneyTests.swift").read_text(encoding="utf-8")
    try:
        for method in selected_tests(os.environ.get("UI_TESTS", ""), source):
            print(method)
    except ValueError as error:
        raise SystemExit(str(error))
