# Nemo

Lightweight block/slot explorer for the **Lean Ethereum** consensus chain, inspired by [Dora the Explorer](https://github.com/ethpandaops/dora).

## Monorepo layout

| Path | Package | Description |
|------|---------|-------------|
| **`backend/`** | **Nemo backend** (Zig) | HTTP server, SQLite, Lean `/lean/v0/*` client. Sources: `backend/src/`. Build: `zig build` from repo root. See [backend/README.md](backend/README.md). |
| **`frontend/`** | **Nemo frontend** (React) | Vite + React UI; build output `frontend/dist/`. See [frontend/README.md](frontend/README.md). |
| Root | Integration | `build.zig`, `build.zig.zon`, Docker, Compose; long-form docs live in [`docs/`](docs/). |

- **Scope**: Consensus only (slots, blocks, fork choice, checkpoints)—no execution layer.
- **Upstream**: Any client that exposes `/lean/v0/*` (e.g. **zeam** or **lean-spec-node**).

## Docs

| Doc | Description |
|-----|-------------|
| [MONOREPO.md](docs/MONOREPO.md) | Backend vs frontend layout and naming. |
| [OVERVIEW.md](docs/OVERVIEW.md) | Goals, relationship to leanSpec, why Zig, inspiration from Dora. |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Components: backend server, lean API client, SQLite, frontend. |
| [API.md](docs/API.md) | leanSpec API surface we consume; Nemo’s own endpoints. |
| [ROADMAP.md](docs/ROADMAP.md) | Phased plan. |
| [LEANSPEC_API_REQUESTS.md](docs/LEANSPEC_API_REQUESTS.md) | Optional future leanSpec endpoints. |

## Requirements

- **Zig** 0.15.x (see `build.zig.zon` `minimum_zig_version`).
- **SQLite 3** dev library (`libsqlite3`) for linking the backend.
- **Node.js** 20+ for the frontend.

## Local build & run

```sh
cd frontend && npm install && npm run build && cd ..
zig build -Doptimize=ReleaseFast
LEAN_API_URL=http://127.0.0.1:5052 NEMO_PORT=5053 WEB_DIST=frontend/dist ./zig-out/bin/nemo
```

Open `http://127.0.0.1:5053`. Frontend dev (API proxied to :5053): `cd frontend && npm run dev`.

## Docker (multi-arch, always amd64 + arm64)

Images are built for **linux/amd64** and **linux/arm64** only (see [docker-bake.hcl](docker-bake.hcl)). Multi-arch manifests cannot be loaded into the local Docker engine with `--load`; you must **push** to a registry.

```sh
docker buildx create --name nemo-multiarch --driver docker-container --bootstrap 2>/dev/null || true
docker buildx use nemo-multiarch
IMAGE_NAME=your-registry/nemo:v1 docker buildx bake --push
# or: ./scripts/docker-build-multiarch.sh your-registry/nemo:v1
```

`docker compose build` also requests both platforms (BuildKit). Local single-arch test:

```sh
docker buildx build --platform linux/arm64 -t nemo:local --load .
```

## Environment

| Variable | Default | Meaning |
|----------|---------|---------|
| `LEAN_API_URL` | `http://127.0.0.1:5052` | Comma-separated upstream base URLs (no trailing slash). |
| `NEMO_PORT` | `5053` | Listen port. |
| `NEMO_DB_PATH` | `nemo.db` | SQLite file path. |
| `WEB_DIST` | `frontend/dist` | Directory with `index.html` and `assets/`. |
| `SYNC_INTERVAL_SEC` | `5` | Background fork-choice sync interval. |
