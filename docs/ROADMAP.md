# Nemo Roadmap

Phased plan to go from zero to a usable Lean beacon explorer with a Zig backend.

---

## Phase 1: MVP backend and proxy

**Goal**: Zig binary that talks to leanSpec and exposes the same data via simple API routes.

1. **Zig project setup**
   - `build.zig` (and optionally `build.zig.zon` if adding deps).
   - Config: `LEAN_API_URL`, `NEMO_PORT` (env or CLI).

2. **HTTP server**
   - Bind to `NEMO_PORT`; serve a minimal router (e.g. `GET /api/health`, `GET /api/fork_choice`, `GET /api/checkpoints/justified`).
   - Use `std.http.Server` or a small Zig HTTP library.

3. **Lean API client**
   - HTTP GET to `LEAN_API_URL + path` for `/lean/v0/health`, `/lean/v0/fork_choice`, `/lean/v0/checkpoints/justified`.
   - Parse JSON for fork_choice and checkpoints (e.g. `std.json`).
   - Return 502/503 if leanSpec is unreachable or returns error.

4. **Static file serving**
   - Serve `static/` (or `public/`) for `GET /` and `GET /static/*`.
   - One minimal `index.html` that shows “Nemo” and maybe calls `GET /api/health` or `GET /api/fork_choice` and prints JSON (proof of life).

**Deliverable**: Run leanSpec + Nemo; open browser to Nemo; see health/fork_choice JSON (or a minimal page that fetches and displays it).

---

## Phase 2: Explorer UI (slots and fork choice)

**Goal**: Human-readable pages for chain head, slots, and block tree.

1. **Dashboard (index)**
   - Head block root and slot.
   - Justified and finalized checkpoint (slot + root).
   - Safe target.
   - Validator count.
   - Link to “Fork choice tree” and “Slots”.

2. **Fork choice tree view**
   - List or tree of blocks from `nodes`: root, slot, parent_root, proposer_index, weight.
   - Optional: simple visual (indent by depth or small graph).

3. **Slot list**
   - Endpoint `GET /api/slots` derived from fork_choice nodes (unique slots, optionally with canonical block root per slot).
   - Page listing slots with links to `/slot/:slot`.

4. **Slot detail**
   - `GET /api/slot/:slot`: blocks at that slot (from nodes).
   - Page showing block root(s), proposer, weight, parent link.

5. **Block by root**
   - `GET /api/block/:root`: single block from nodes; 404 if unknown.
   - Page: root, slot, parent_root, proposer_index, weight, link to parent.

**Deliverable**: Navigate from dashboard to slots and blocks; all data from leanSpec via Nemo’s API.

---

## Phase 3: Caching and robustness

**Goal**: Reduce load on leanSpec and improve responsiveness.

1. **In-memory cache**
   - Short TTL (e.g. 2–5 s) for fork_choice and checkpoints.
   - Config: `CACHE_TTL_SEC`.

2. **Error handling and retries**
   - Retry leanSpec requests with backoff on failure.
   - Clear 502/503 and timeout handling in UI (e.g. “Node unavailable, retry in X s”).

3. **CORS**
   - Add CORS headers to Nemo’s API if the UI is served from another origin.

**Deliverable**: Same UI with snappier repeat loads and clearer errors when leanSpec is down.

---

## Phase 4 (optional): History and optional DB

**Goal**: Optional persistence for history and search (Dora-style).

1. **Design**
   - Decide scope: e.g. “last N fork_choice snapshots” or “all blocks seen.”
   - Choose storage: SQLite (single file, no extra daemon) vs PostgreSQL (if we want multi-instance or existing Postgres).

2. **Indexing**
   - Background task or per-request: when we fetch fork_choice, optionally write nodes/slots to DB.
   - Endpoints: e.g. “slots in range”, “block by root (historical)”.”

3. **UI**
   - “Slots in range” page, optional “search block by root” with history.

**Deliverable**: Optional DB; Nemo can run with or without it; history views when enabled.

---

## Out of scope (for this roadmap)

- Execution layer data (Lean consensus only).
- Validator management or key storage.
- Authentication/authorization (assume internal or devnet).
- Reimplementing consensus in Zig (leanSpec remains the authority).

---

## Dependencies (Zig)

- **MVP**: std only (HTTP server, client, JSON).
- **If needed**: one of `zig-httpz`, `h11e`, or similar for routing; or keep minimal with `std.http.Server` and manual path parsing.
- **Optional later**: SQLite C API via `@cImport` or a Zig SQLite wrapper for Phase 4.
