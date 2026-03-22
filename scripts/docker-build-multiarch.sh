#!/usr/bin/env sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export IMAGE_NAME="${1:-nemo:latest}"
cd "$ROOT"

GIT_COMMIT="${GIT_COMMIT:-$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)}"
export GIT_COMMIT

if ! docker buildx inspect nemo-multiarch >/dev/null 2>&1; then
  docker buildx create --name nemo-multiarch --driver docker-container --bootstrap
fi

exec docker buildx bake -f docker-bake.hcl --builder nemo-multiarch --push
