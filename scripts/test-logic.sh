#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$project_root/build"
swiftc "$project_root/RutasTijuana/TransitRoute.swift" "$project_root/RutasTijuana/RouteCatalog.swift" "$project_root/RutasTijuana/JourneyScenario.swift" "$project_root/RutasTijuana/CatalogSync.swift" "$project_root/RutasTijuana/CatalogCache.swift" "$project_root/tests/main.swift" -o "$project_root/build/route-tests"
port_file="$(mktemp "$project_root/build/http-port.XXXXXX")"
python3 "$project_root/tests/catalog_http.py" "$port_file" &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true; rm -f "$port_file"' EXIT
for attempt in {1..600}; do
  if [ -s "$port_file" ]; then break; fi
  kill -0 "$server_pid"
  sleep 0.1
done
test -s "$port_file"
export CATALOG_HTTP_TEST_URL="http://127.0.0.1:$(cat "$port_file")"
"$project_root/build/route-tests"
