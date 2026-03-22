# Nemo frontend

React + Vite explorer UI. Consumes the backend’s `/api/*` JSON routes.

```sh
cd frontend
npm install
npm run dev    # dev server with API proxy to :5053
npm run build  # output: frontend/dist/
```

The backend serves `frontend/dist/` by default (`WEB_DIST`).
