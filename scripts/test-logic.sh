#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$project_root/build"
sources=("$project_root/RutasTijuana/FavoriteRoutes.swift" "$project_root/RutasTijuana/TransitRoute.swift" "$project_root/RutasTijuana/RouteCatalog.swift" "$project_root/RutasTijuana/CatalogPublic.swift" "$project_root/RutasTijuana/CatalogPackage.swift" "$project_root/RutasTijuana/JourneyScenario.swift" "$project_root/RutasTijuana/CatalogSync.swift" "$project_root/RutasTijuana/CatalogCache.swift" "$project_root/RutasTijuana/WalkingNavigation.swift" "$project_root/RutasTijuana/TransitProgress.swift" "$project_root/RutasTijuana/TripPlanner.swift" "$project_root/RutasTijuana/RouteAccess.swift" "$project_root/tests/main.swift")
# Reutiliza el binario si las fuentes y el compilador no cambiaron.
fingerprint="$( (swiftc --version 2>&1; cat "${sources[@]}") | shasum -a 256 | cut -d' ' -f1)"
stamp="$project_root/build/route-tests.sha256"
if [ ! -x "$project_root/build/route-tests" ] || [ "$(cat "$stamp" 2>/dev/null)" != "$fingerprint" ]; then
  swiftc "${sources[@]}" -o "$project_root/build/route-tests"
  echo "$fingerprint" > "$stamp"
fi
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
