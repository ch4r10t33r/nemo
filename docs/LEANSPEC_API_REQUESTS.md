# leanSpec API: New Endpoints for Nemo

This document lists **new API endpoints** that would need to be added in **leanSpec** (in a separate PR) to support the Nemo block explorer. No changes are made to leanSpec in this repo; this is a specification for a future PR.

It also documents **current** endpoints and **response types** (JSON vs binary), and how Nemo can work around non-JSON or existing behaviour.

---

## Current leanSpec API and response types

| Method | Path | Response type | Content-Type | Notes |
|--------|------|---------------|--------------|--------|
| GET | `/lean/v0/health` | JSON | `application/json` | `status`, `service` |
| GET | `/lean/v0/fork_choice` | JSON | `application/json` | Includes `nodes`, `head`, **`justified`**, **`finalized`**, `safe_target`, `validator_count` |
| GET | `/lean/v0/checkpoints/justified` | JSON | `application/json` | `slot`, `root` |
| GET | `/lean/v0/states/finalized` | **Binary (SSZ)** | `application/octet-stream` | Raw SSZ-encoded State; not JSON |

So: **finalized checkpoint is already available** inside `GET /lean/v0/fork_choice` as `response.finalized`. The **finalized state** exists but is SSZ only; there is no JSON summary today.

---

## How Nemo works with existing responses

- **JSON endpoints:** Nemo’s client parses the body as JSON (e.g. with `std.json`) and uses the fields as needed. Always check `Content-Type: application/json` (or parse and handle parse errors) before assuming JSON.
- **Non-JSON (e.g. SSZ):** Do not parse as JSON. Use `Content-Type` to branch:
  - `application/octet-stream` (or other binary type): treat as opaque bytes. Options:
    - **Proxy as-is:** Return the same bytes and `Content-Type` to the browser (e.g. “Download finalized state” link).
    - **Do not expose in UI as structured data:** e.g. don’t try to show “finalized state” fields in the dashboard unless leanSpec adds a JSON summary endpoint; for now, only offer “Download state (SSZ)” that hits leanSpec and streams the response.
- **Accept header (optional):** If leanSpec later supports e.g. `Accept: application/json` for an endpoint that can return either SSZ or JSON, Nemo can send `Accept: application/json` and only then parse JSON. Until then, Nemo should not assume JSON for any endpoint that currently returns something else.
- **Summary:** Nemo should **never assume all responses are JSON**. Branch on `Content-Type` (or response header inspection); handle JSON where present and proxy or offer download for binary responses.

---

## New endpoints to add in leanSpec

**Response format:** All endpoints listed below are proposed to return **JSON** so Nemo can parse them without SSZ support. If leanSpec adds an endpoint that returns SSZ or another format instead, Nemo will handle it by checking `Content-Type` and either proxying the bytes or documenting the format (see “How Nemo works with existing responses” above).

---

### 1. Block by root

**Method:** `GET`  
**Path:** `/lean/v0/blocks/{block_root}`  

**Description:** Return a single block’s metadata (and optionally body) by its tree hash root. Enables “block detail” pages and deep links without Nemo having to filter the full fork_choice response.

**Path parameter:** `block_root` — 0x-prefixed hex, 66 characters (32 bytes).

**Response (200):** JSON, e.g.:

```json
{
  "root": "0x...",
  "slot": 5,
  "parent_root": "0x...",
  "proposer_index": 2,
  "body_root": "0x...",
  "state_root": "0x...",
  "weight": 10
}
```

Optional: include `attestations` (or `attestation_count`) for the block body if useful for the explorer. If the node does not have the block (e.g. pruned or never received), return **404**.

**Implementation note:** Look up `store.blocks.get(root)`; if missing, 404. `weight` can be derived from `store.compute_block_weights()` for the block’s root.

---

### 2. Blocks at slot

**Method:** `GET`  
**Path:** `/lean/v0/slots/{slot}`  
or alternatively: `GET /lean/v0/blocks?slot={slot}`  

**Description:** Return all blocks known at a given slot (there may be multiple in case of forks). Enables “slot detail” and “blocks at slot N” pages.

**Path/query parameter:** `slot` — non-negative integer.

**Response (200):** JSON array of block summaries, e.g.:

```json
[
  {
    "root": "0x...",
    "slot": 5,
    "parent_root": "0x...",
    "proposer_index": 2,
    "weight": 10
  }
]
```

If no blocks at that slot, return **200** with `[]`. If slot is invalid (e.g. negative), return **400**.

**Implementation note:** Iterate `store.blocks` and filter by `block.slot == slot`; optionally include weight from `store.compute_block_weights()`.

---

### 3. Finalized checkpoint (optional — already available)

**Method:** `GET`  
**Path:** `/lean/v0/checkpoints/finalized`  

**Description:** Symmetric with justified checkpoint. Returns the latest finalized checkpoint.

**Workaround:** Nemo does **not** need this for MVP. The finalized checkpoint is already in `GET /lean/v0/fork_choice` as `response.finalized` (same shape: `slot`, `root`). Nemo can use that and avoid an extra request. This endpoint is only useful if you want a dedicated, lightweight checkpoint URL (e.g. for monitoring) or parity with `checkpoints/justified`.

**Response (200):** JSON, e.g. `{"slot": 0, "root": "0x..."}` — same as existing `checkpoints/justified`.

**Implementation note:** `store.latest_finalized`. Same pattern as existing `checkpoints/justified`.

---

### 4. Chain / node config (optional)

**Method:** `GET`  
**Path:** `/lean/v0/config`  
or `/lean/v0/node/config`  

**Description:** Read-only chain or node parameters useful for the explorer UI: e.g. genesis time, slot duration, network name, or other `Config` fields that are safe to expose. Allows the explorer to show “Genesis time”, “Slot duration”, etc., without hardcoding.

**Response (200):** JSON, e.g.:

```json
{
  "genesis_time": 1234567890,
  "slot_duration_seconds": 6,
  "network_name": "devnet"
}
```

Exact fields depend on what leanSpec’s `Config` and deployment expose. Optional for MVP; Nemo can work without it.

---

### 5. Validators (optional, later)

**Method:** `GET`  
**Path:** `/lean/v0/validators`  

**Description:** List validators from the head (or finalized) state so the explorer can show a “Validators” page and map `proposer_index` to validator info (e.g. index, balance, status if applicable in Lean).

**Response (200):** JSON array of validator objects. Exact shape depends on Lean’s `State.validators` and what is considered public (e.g. index, pubkey, balance).

**Note:** If the Lean spec does not expose a rich validator set or this is sensitive, this endpoint can be omitted or restricted. Nemo can still show proposer_index without it.

---

### 6. Finalized state summary (optional — workaround for SSZ-only state)

**Method:** `GET`  
**Path:** `/lean/v0/states/finalized/summary`  

**Description:** A small **JSON** summary of the finalized state (slot, root, validator_count, etc.). The **existing** `GET /lean/v0/states/finalized` returns **SSZ only** (`application/octet-stream`), so the explorer cannot show “Finalized state” as structured data without either parsing SSZ in Nemo or adding this JSON summary in leanSpec.

**Workaround today:** Nemo can (a) offer a “Download finalized state (SSZ)” link that proxies `GET /lean/v0/states/finalized` and streams the binary response as-is, and (b) show high-level finalized info (slot, root) from `GET /lean/v0/fork_choice` (field `finalized`). So this new endpoint is optional; it only avoids re-fetching fork_choice when you only need a small summary.

**Response (200):** JSON, e.g. `{"slot": 0, "root": "0x...", "validator_count": 4}`.

**Implementation note:** Use `store.latest_finalized` and the state at that root from `store.states`; return a small subset of fields.

---

## Summary table (for leanSpec PR)

| Priority | Method | Path | Purpose | Nemo workaround if not added |
|----------|--------|------|---------|-----------------------------|
| **1** | GET | `/lean/v0/blocks/{block_root}` | Block by root (block detail page) | Derive from `fork_choice.nodes` by root |
| **2** | GET | `/lean/v0/slots/{slot}` (or `/blocks?slot=`) | Blocks at slot (slot detail page) | Derive from `fork_choice.nodes` by slot |
| **3** | GET | `/lean/v0/checkpoints/finalized` | Finalized checkpoint (optional) | **Already in** `fork_choice.finalized` |
| **4** | GET | `/lean/v0/config` (or `/lean/v0/node/config`) | Chain/node config (optional) | Omit or hardcode in UI |
| **5** | GET | `/lean/v0/validators` | Validator list (optional) | Show only proposer_index from nodes |
| **6** | GET | `/lean/v0/states/finalized/summary` | Finalized state JSON summary (optional) | Use `fork_choice.finalized` + proxy SSZ for download |

Proposed new endpoints return **JSON** unless leanSpec documents otherwise; Nemo will branch on `Content-Type` and support non-JSON (e.g. SSZ) if an endpoint returns it.

**Error handling (suggested for new endpoints):**

- **404** — Resource not found (e.g. block root not in store, or no blocks at slot if you treat “no blocks” as 404).
- **503** — Store not initialized (same as existing endpoints).
- **400** — Bad request (e.g. invalid block_root format or invalid slot).

---

## What Nemo can do without these

- **MVP:** Nemo can derive “slots” and “block by root” from the existing `GET /lean/v0/fork_choice` response (filter `nodes` by slot or root). So the first two new endpoints are **nice-to-have** for cleaner API and for blocks that might not appear in the current fork choice tree (e.g. after pruning).
- **Finalized checkpoint:** Already in `fork_choice.finalized`; no new endpoint required.
- **Finalized state:** Existing endpoint is SSZ only; Nemo can proxy it as a download and use `fork_choice.finalized` for summary info until a JSON summary endpoint exists.
- **Config / validators / state summary:** Purely optional for a richer explorer UI; not required for Phase 1–2 of Nemo.

## If an endpoint returns something other than JSON

If leanSpec implements one of the “new” endpoints but returns SSZ or another format (e.g. for consistency with existing state APIs):

- Nemo will **check `Content-Type`** on every response and branch accordingly: parse JSON only when `Content-Type` indicates JSON; otherwise treat as binary and proxy or offer download.
- The “New endpoints” section above describes a desired **JSON** shape for explorer convenience; if the actual response is different, Nemo’s client will be implemented to match the documented (or discovered) response type for that path.

This file can be copied or linked in the leanSpec PR description when adding the new endpoints.
