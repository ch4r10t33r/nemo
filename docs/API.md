# API: leanSpec Surface and Nemo Endpoints

## leanSpec API (consumed by Nemo)

Nemo calls the existing leanSpec node API. Base URL is configurable (e.g. `http://127.0.0.1:5052`).

**New endpoints needed in leanSpec** (for a separate PR) are listed in [LEANSPEC_API_REQUESTS.md](LEANSPEC_API_REQUESTS.md). That doc also lists **response types** (JSON vs SSZ) and how Nemo works around non-JSON (e.g. proxy binary as-is, branch on `Content-Type`). The table below is the **current** surface.

| Method | Path | Response | Description |
|--------|------|----------|-------------|
| GET | `/lean/v0/health` | JSON | Health check. |
| GET | `/lean/v0/fork_choice` | JSON | Fork choice tree: nodes (blocks with root, slot, parent_root, proposer_index, weight), head, justified, finalized, safe_target, validator_count. |
| GET | `/lean/v0/checkpoints/justified` | JSON | Latest justified checkpoint: `slot`, `root` (0x-prefixed hex). |
| GET | `/lean/v0/states/finalized` | **SSZ (binary)** | Finalized beacon state as raw SSZ (`application/octet-stream`). Nemo: proxy as download or use fork_choice for summary; do not parse as JSON. Optional for MVP. |

### Fork choice response (reference)

```json
{
  "nodes": [
    {
      "root": "0x...",
      "slot": 1,
      "parent_root": "0x...",
      "proposer_index": 0,
      "weight": 42
    }
  ],
  "head": "0x...",
  "justified": { "slot": 0, "root": "0x..." },
  "finalized": { "slot": 0, "root": "0x..." },
  "safe_target": "0x...",
  "validator_count": 4
}
```

Nemo’s Zig client will parse this JSON (e.g. with `std.json`) and optionally reshape it for the UI or cache.

## Nemo’s own endpoints (proposed)

These are served by the Zig backend. They can proxy leanSpec and optionally add caching or aggregation.

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | Explorer index (HTML). |
| GET | `/static/*` | Static assets (CSS, JS, images). |
| GET | `/api/health` | Proxy to `GET /lean/v0/health` or return 503 if leanSpec unreachable. |
| GET | `/api/fork_choice` | Proxy to `GET /lean/v0/fork_choice`; optional short TTL cache. |
| GET | `/api/checkpoints/justified` | Proxy to `GET /lean/v0/checkpoints/justified`. |
| GET | `/api/slots` | Derived from fork_choice nodes: list of slots (and maybe head block per slot) for a “slot list” page. |
| GET | `/api/slot/:slot` | Block(s) at slot (from fork_choice nodes); 404 if none. |
| GET | `/api/block/:root` | Block by root (0x-prefixed hex); from fork_choice nodes. 404 if unknown. |

Later (optional):

- `GET /api/validators` — if leanSpec adds a validator list endpoint or we derive from state.
- `GET /api/states/finalized` — proxy or redirect to leanSpec’s SSZ endpoint for “download finalized state”.

All Nemo API responses that return JSON should use `Content-Type: application/json`. CORS headers can be added for browser clients if the UI is on a different origin.

## Error handling

- If leanSpec is down or returns 5xx: Nemo’s proxy endpoints should return 503 or 502 with a short JSON body (e.g. `{"error": "lean node unavailable"}`).
- If a requested slot or root is not in the current fork_choice snapshot: 404 with a clear message (e.g. `{"error": "slot not found"}`).
