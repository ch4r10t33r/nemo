#!/usr/bin/env sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> frontend"
cd frontend
if [ -f package-lock.json ]; then
  npm ci
else
  npm install
fi
npm run build
cd "$ROOT"

echo "==> zig (ReleaseFast)"
zig build -Doptimize=ReleaseFast

echo "OK: frontend/dist and zig-out/bin/nemo"
