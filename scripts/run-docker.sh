#!/usr/bin/env sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FG=0
for arg in "$@"; do
  case "$arg" in
    --fg | --foreground) FG=1 ;;
  esac
done

if [ "$FG" -eq 1 ]; then
  docker compose up --build
else
  docker compose up --build -d
  echo "Nemo: http://127.0.0.1:5053"
  echo "Upstream in container: LEAN_API_URL (default host.docker.internal:5052)"
  echo "Logs: docker compose logs -f nemo"
fi
