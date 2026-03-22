import { execSync } from "node:child_process";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

function resolveGitSha(): string {
  const fromEnv = process.env.VITE_APP_GIT_SHA;
  if (fromEnv != null && fromEnv.length > 0) return fromEnv.trim();
  try {
    return execSync("git rev-parse HEAD", { encoding: "utf8" }).trim();
  } catch {
    return "unknown";
  }
}

const gitSha = resolveGitSha();

export default defineConfig({
  plugins: [react()],
  define: {
    "import.meta.env.VITE_APP_GIT_SHA": JSON.stringify(gitSha),
  },
  server: {
    port: 5173,
    proxy: {
      "/api": { target: "http://127.0.0.1:5053", changeOrigin: true },
    },
  },
  build: {
    outDir: "dist",
    emptyOutDir: true,
  },
});
