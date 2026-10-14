#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$project_root/build"
swiftc "$project_root/RutasTijuana/TransitRoute.swift" "$project_root/tests/main.swift" -o "$project_root/build/route-tests"
"$project_root/build/route-tests"
