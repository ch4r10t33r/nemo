# Nemo

Lightweight block/slot explorer for the **Lean Ethereum** consensus chain, inspired by [Dora the Explorer](https://github.com/ethpandaops/dora).

## Monorepo layout

| Path | Package | Description |
|------|---------|-------------|
| **`backend/`** | **Nemo backend** (Zig) | HTTP server, SQLite, Lean `/lean/v0/*` client. Sources: `backend/src/`. Build: [`scripts/build.sh`](scripts/build.sh) or `zig build` from repo root. See [backend/README.md](backend/README.md). |
| **`frontend/`** | **Nemo frontend** (React) | Vite + React UI; build output `frontend/dist/`. See [frontend/README.md](frontend/README.md). |
| **`config/`** | **Examples** | [`quickstart.env.example`](config/quickstart.env.example) — copy to `.env` for quick start. |
| Root | Integration | `build.zig`, `build.zig.zon`, [`scripts/`](scripts/), Docker Compose; long-form docs in [`docs/`](docs/). |

- **Scope**: Consensus only (slots, blocks, fork choice, checkpoints)—no execution layer.
- **Upstream**: Any client that exposes `/lean/v0/*` (e.g. **zeam** or **lean-spec-node**).

## Quick start

You need a **running Lean consensus HTTP API** (usually port **5052**) before Nemo can show data.

1. **Install tooling** — See [Requirements](#requirements) (Zig, Node, SQLite dev libs). For Docker only, you still need Docker; the image builds Zig and Node inside the Dockerfile.

2. **Configure** — Copy the example env file to `.env` in the **repo root** and edit `LEAN_API_URL` if your node is not at the default URL:

   ```sh
   cp config/quickstart.env.example .env
   ```

   Example file: [`config/quickstart.env.example`](config/quickstart.env.example) (all tunables are documented there). The repo [ignores `.env`](.gitignore) so your local settings are not committed.

3. **Run a Lean node** — Start **zeam**, **lean-spec-node**, or a devnet from **lean-quickstart** so something serves `/lean/v0/*` on the host/port you put in `LEAN_API_URL`.

4. **Start Nemo** — pick one:

   **Binary (native Zig server + built UI)**

   ```sh
   set -a && . ./.env && set +a   # bash/zsh: export variables from .env
   ./scripts/build.sh
   ./zig-out/bin/nemo
   ```

   Open **http://127.0.0.1:5053** (or your `NEMO_PORT`).

   **Docker**

   ```sh
   ./scripts/run-docker.sh
   ```

   Compose uses `.env` for `LEAN_API_URL` (defaults to `host.docker.internal:5052` if unset). Same URL in the browser: **http://127.0.0.1:5053**.

5. **Optional** — Reset SQLite if you changed chains or want a clean cache: `./scripts/clear-db.sh` (binary) or `./scripts/clear-db.sh --docker` (container volume).

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

## Scripts (`scripts/`)

These are the supported entry points for building, resetting state, and running in Docker.

| Script | Purpose |
|--------|---------|
| [`scripts/build.sh`](scripts/build.sh) | Production-style build: `npm ci` (or `npm install`) and `npm run build` in `frontend/`, then `zig build -Doptimize=ReleaseFast` at repo root. Produces `frontend/dist/` and `zig-out/bin/nemo`. |
| [`scripts/clear-db.sh`](scripts/clear-db.sh) | **Local binary:** removes SQLite at `NEMO_DB_PATH` or repo-root `nemo.db` (relative paths are resolved from the repo root). **`--docker`:** `docker compose down -v` — stops the stack and deletes the `nemo-data` volume. |
| [`scripts/run-docker.sh`](scripts/run-docker.sh) | **`docker compose up --build`** from the repo root. Default: **detached** (`-d`); prints URL and `docker compose logs -f nemo`. Pass **`--fg`** (or **`--foreground`**) to stay attached. Compose builds a **single-platform** image for your machine (see Docker below). |
| [`scripts/docker-build-multiarch.sh`](scripts/docker-build-multiarch.sh) | Release workflow: **`docker buildx bake`** for **linux/amd64** and **linux/arm64**, **push** to a registry (see [docker-bake.hcl](docker-bake.hcl)). |

## Local build & run (binary)

**Recommended:** run [`scripts/build.sh`](scripts/build.sh), then start the server:

```sh
./scripts/build.sh
LEAN_API_URL=http://127.0.0.1:5052 NEMO_PORT=5053 WEB_DIST=frontend/dist ./zig-out/bin/nemo
```

Open `http://127.0.0.1:5053`.

**Reset cached fork-choice data** before a fresh run: `./scripts/clear-db.sh`.

**Frontend dev** (hot reload; API proxied to Nemo on `:5053`): `cd frontend && npm install && npm run dev`.

**Manual build** (equivalent to `build.sh` without the script):

```sh
cd frontend && npm install && npm run build && cd ..
zig build -Doptimize=ReleaseFast
```

## Docker

**Run Nemo in a container** (builds the image if needed, publishes **5053**):

```sh
./scripts/run-docker.sh
```

Set the Lean API the container should use (defaults in [docker-compose.yml](docker-compose.yml) point at **`host.docker.internal:5052`** so a node on the host is reachable):

```sh
LEAN_API_URL=http://host.docker.internal:5052 ./scripts/run-docker.sh
```

**Wipe container DB and stop:** `./scripts/clear-db.sh --docker` (then start again with `run-docker.sh` if you want a clean volume).

**Two build paths:**

| Use case | Command |
|----------|---------|
| Local / dev on this machine | `./scripts/run-docker.sh` or `docker compose up --build` — **one platform** (host), image loads into the local engine. |
| Registry release (**amd64** + **arm64**) | `./scripts/docker-build-multiarch.sh your-registry/nemo:v1` (or `IMAGE_NAME=... docker buildx bake --push` with a `nemo-multiarch` builder). Multi-arch manifests are **push-only**, not `--load`. |

Setup for bake (once per machine):

```sh
docker buildx create --name nemo-multiarch --driver docker-container --bootstrap 2>/dev/null || true
docker buildx use nemo-multiarch
```

## Environment

| Variable | Default | Meaning |
|----------|---------|---------|
| `LEAN_API_URL` | `http://127.0.0.1:5052` | Comma-separated upstream base URLs (no trailing slash), **first to last**. Each request tries URLs in order until one succeeds (HTTP failure, bad JSON, or DB write failure skips to the next). |
| `NEMO_PORT` | `5053` | Listen port. |
| `NEMO_DB_PATH` | `nemo.db` | SQLite file path. |
| `WEB_DIST` | `frontend/dist` | Directory with `index.html` and `assets/`. |
| `SYNC_INTERVAL_SEC` | `4` | Background fork-choice sync interval (matches leanSpec `SECONDS_PER_SLOT`). |
