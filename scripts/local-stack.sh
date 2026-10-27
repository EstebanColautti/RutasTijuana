#!/usr/bin/env bash
set -euo pipefail
umask 077
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
mkdir -p local-data
version=2.122.0
tools="$HOME/.local/share/rutastijuana/tools"
cli="$tools/supabase"
if [ ! -x "$cli" ]; then
  mkdir -p "$tools"
  case "$(uname -s)" in Linux) platform=linux ;; Darwin) platform=darwin ;; *) exit 1 ;; esac
  case "$(uname -m)" in x86_64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; *) exit 1 ;; esac
  archive="supabase_${version}_${platform}_${arch}.tar.gz"
  curl -fsSL --retry 2 "https://github.com/supabase/cli/releases/download/v${version}/${archive}" -o "$tools/cli.tar.gz"
  curl -fsSL --retry 2 "https://github.com/supabase/cli/releases/download/v${version}/checksums.txt" -o "$tools/checksums.txt"
  expected=''
  while read -r sum name; do
    if [ "$name" = "$archive" ]; then expected="$sum"; break; fi
  done < "$tools/checksums.txt"
  test -n "$expected"
  if command -v sha256sum >/dev/null; then actual="$(sha256sum "$tools/cli.tar.gz")"; else actual="$(shasum -a 256 "$tools/cli.tar.gz")"; fi
  test "${actual%% *}" = "$expected"
  tar -xzf "$tools/cli.tar.gz" -C "$tools" supabase
fi
if [ -z "${DOCKER_HOST:-}" ] && command -v podman >/dev/null; then
  systemctl --user start podman.socket
  export DOCKER_HOST="unix:///run/user/$(id -u)/podman/podman.sock"
fi
case "${1:-start}" in
 start)
  "$cli" start --exclude realtime,storage-api,imgproxy,postgres-meta,studio,logflare,vector,supavisor > local-data/stack-start.log 2>&1
  python3 scripts/loopback-containers.py
  for attempt in {1..20}; do
    if "$cli" status -o env > local-data/supabase.env.tmp 2> local-data/stack-status.log; then
      mv local-data/supabase.env.tmp local-data/supabase.env
      break
    fi
    sleep 2
  done
  test -s local-data/supabase.env
  "$cli" db push --local > local-data/stack-migrations.log 2>&1
  printf 'Servicios locales preparados.\n'
  ;;
 api)
  "$cli" functions serve --env-file local-data/functions.env > local-data/edge.log 2>&1
  ;;
 stop)
  "$cli" stop --project-id rutastijuana > local-data/stack-stop.log 2>&1
  printf 'Servicios locales detenidos; los datos se conservan.\n'
  ;;
 *) exit 1 ;;
esac
