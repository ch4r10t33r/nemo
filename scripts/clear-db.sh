#!/usr/bin/env sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
  echo "Usage: $0 [--docker]" >&2
  echo "  default: delete local SQLite (NEMO_DB_PATH or ${ROOT}/nemo.db)" >&2
  echo "  --docker: docker compose down -v (removes containers and the nemo-data volume)" >&2
}

case "${1:-}" in
  --docker | -d)
    cd "$ROOT"
    docker compose down -v
    echo "Docker stack stopped and named volumes removed."
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  "")
    db="${NEMO_DB_PATH:-nemo.db}"
    case "$db" in
      /*) ;;
      *) db="$ROOT/$db" ;;
    esac
    rm -f "$db"
    echo "Removed $db (if it existed)."
    ;;
  *)
    usage
    exit 1
    ;;
esac
