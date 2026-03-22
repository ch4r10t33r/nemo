# Nemo: Lean Ethereum Beacon Explorer

A lightweight slot/block explorer for the Lean Ethereum consensus chain, inspired by [Dora the Explorer](https://github.com/ethpandaops/dora) (ethpandaops/dora).

## Goals

- **Explore consensus data**: slots, blocks, fork choice tree, checkpoints, validators—no execution layer.
- **Lightweight**: no mandatory external DB; can run against a single leanSpec node API.
- **Zig backend**: single binary, low footprint, good fit for tooling alongside the Zig ecosystem (zeam, leanpoint, etc.).

## Relationship to leanSpec

- **leanSpec** (Python) is the source of truth: it runs the consensus node, maintains the fork choice store, and exposes a minimal HTTP API on port 5052.
- **Nemo** is a separate service that consumes that API and presents a human-friendly explorer UI (and optionally caches or enriches data).

We do not reimplement consensus in Zig; we talk to the existing leanSpec API.

## Inspiration: Dora

Dora is a lightweight beacon explorer that:

- Loads most data directly from a standard beacon node API (no Bigtable-style DB required).
- Can run in-memory only; PostgreSQL is optional for performance.
- Focuses on beacon/slot/validator exploration rather than execution transactions.

Nemo follows the same idea for the **Lean** chain: one config (the leanSpec API base URL), minimal dependencies, and an optional cache/DB layer for speed.

## Why Zig for the Backend?

- **Single binary**: easy deploy alongside lean-quickstart devnets (e.g. next to zeam/leanspec containers).
- **No runtime**: no Python/Node on the explorer host if we want to ship only the explorer binary.
- **Ecosystem fit**: same language as zeam, leanpoint, and other Zig tooling in the Lean stack.
- **Performance**: efficient HTTP client and JSON handling for proxying and optional aggregation.

The frontend can remain HTML/CSS/JS (static or with minimal templating) served by the Zig server—same as Dora’s approach with Go + templates + static assets.

## Out of Scope (for now)

- Execution layer blocks/transactions (Lean consensus only).
- Validator key management or signing.
- Running the consensus node itself (that stays in leanSpec).

## Next Steps

- [ARCHITECTURE.md](ARCHITECTURE.md) — components and data flow
- [API.md](API.md) — leanSpec API surface and Nemo’s own endpoints
- [ROADMAP.md](ROADMAP.md) — phased implementation plan
