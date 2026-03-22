# Nemo Architecture

## Monorepo

- **`backend/`** — Zig sources (`backend/src/`), built with root `build.zig` → `nemo` binary.
- **`frontend/`** — React (Vite) app (`nemo-frontend`); production assets in `frontend/dist/`, served by the backend via `WEB_DIST`.

## High-Level Flow

```
┌─────────────────┐     HTTP (JSON/SSZ)      ┌─────────────────┐      HTTP + static      ┌──────────┐
│  leanSpec node  │ ◄─────────────────────────│  Nemo (Zig)     │ ───────────────────────► │  Browser │
│  (Python, :5052)│                            │  backend        │   HTML / JSON / assets  │          │
└─────────────────┘                            └────────┬────────┘                         └──────────┘
                                                       │
                                                       │ optional
                                                       ▼
                                              ┌─────────────────┐
                                              │  Cache / DB     │  (e.g. in-memory, or SQLite/Postgres later)
                                              └─────────────────┘
```

- **leanSpec** exposes `/lean/v0/*` (health, fork_choice, checkpoints, states).
- **Nemo** (Zig) calls that API, optionally caches or reshapes responses, and serves the explorer UI and any extra REST endpoints.

## Components

### 1. Zig HTTP server

- Listen on a configurable port (e.g. 5053 to avoid clashing with leanSpec’s 5052).
- Routes:
  - **Static**: `/` and `/static/*` → serve HTML, CSS, JS (and optionally prebuilt UI package).
  - **Proxy/API**: e.g. `/api/fork_choice`, `/api/health` → HTTP client calls to leanSpec, return JSON (and optionally cached).

### 2. Lean API client (Zig)

- Minimal HTTP client (e.g. `std.http.Client` or a small Zig HTTP library).
- Config: base URL (e.g. `http://localhost:5052`), timeouts.
- Fetch:
  - `GET /lean/v0/health`
  - `GET /lean/v0/fork_choice`
  - `GET /lean/v0/checkpoints/justified`
  - `GET /lean/v0/states/finalized` (SSZ; optional for MVP—can be “raw download” or skipped for UI).
- Parse JSON for fork_choice and checkpoints; expose to handlers as structs (or opaque JSON string for simplicity in v1).

### 3. Optional cache layer

- **Implemented**: SQLite in the **backend** stores fork-choice snapshots and block rows; background sync plus live `/api/fork_choice` refresh upstream when reachable.

### 4. Frontend (`frontend/`)

- React + Vite package **`nemo-frontend`**: fetches `/api/*` from the backend; production build output is **`frontend/dist/`** (served as static files, same origin). Pattern is similar to Dora’s separate `ui-package`.

### 5. Configuration

- **Environment or config file**: `LEAN_API_URL` (default `http://127.0.0.1:5052`), `NEMO_PORT` (default `5053`), optional `CACHE_TTL_SEC`, optional DB path.
- No beacon chain secrets; read-only consumer of the leanSpec API.

## Zig-Only Backend: Feasibility

- **HTTP server**: `std.http.Server` or a small dependency (e.g. `zig-httpz`, `h11e`) for routing and responses.
- **HTTP client**: `std.http.Client` for outbound calls to leanSpec.
- **JSON**: `std.json` for parsing fork_choice and checkpoints; no need for full SSZ in Zig for MVP (we can show “finalized state” as “available / download link”).
- **Build**: single `zig build` artifact; optional `build.zig.zon` if we add a Zig HTTP or JSON helper dependency.

## Deployment

- Run leanSpec node (e.g. via lean-quickstart) so `/lean/v0/*` is available.
- Run Nemo binary with `LEAN_API_URL` pointing at that node.
- Open browser at `http://localhost:5053` (or configured port).

Containers: [Dockerfile](../Dockerfile) builds the Zig binary plus the React UI. Release images are **multi-arch** (`linux/amd64`, `linux/arm64`) via [docker-bake.hcl](../docker-bake.hcl) and `docker buildx bake --push`. Same network as the consensus client container so `LEAN_API_URL=http://zeam:5052` (or lean-spec-node) works.

## Security Notes

- Nemo does not need to trust the leanSpec node cryptographically for “explorer” use: it displays what the node reports (same trust as opening the API in a browser).
- CORS: if the UI is on a different origin, Nemo’s API responses may need CORS headers when fetched from the browser.
- No authentication in MVP; explorer is assumed to be internal or devnet.
