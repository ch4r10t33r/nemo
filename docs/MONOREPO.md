# Nemo monorepo

This repository is a **monorepo** with two named packages:

| Directory | Name | Role |
|-----------|------|------|
| **`backend/`** | **Nemo backend** | Zig HTTP server + SQLite (`backend/src/`). |
| **`frontend/`** | **Nemo frontend** | React UI, npm package **`nemo-frontend`**. |

Root **`build.zig`** / **`build.zig.zon`** build only the backend; the frontend is built with **`npm run build`** inside `frontend/`.

See the root [README.md](../README.md) for commands and [ARCHITECTURE.md](ARCHITECTURE.md) for the system view.
