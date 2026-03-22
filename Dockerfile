# frontend/ — React (Vite) UI
FROM node:22-alpine AS frontend
WORKDIR /frontend
COPY frontend/package.json ./
RUN npm install
COPY frontend/ ./
RUN npm run build

# backend/ — Zig HTTP server + SQLite
FROM alpine:3.21 AS zigbuild
# sqlite-dev: libsqlite3 for zig linkSystemLibrary("sqlite3") at build time
RUN apk add --no-cache wget tar xz sqlite-dev
ARG ZIG_VERSION=0.15.2
# Injected per slice by buildx; plain `docker build` may leave empty — default in shell.
ARG TARGETARCH
RUN set -e; \
    ARCH="${TARGETARCH:-amd64}"; \
    case "$ARCH" in \
      amd64) ZIG_ARCH=x86_64 ;; \
      arm64) ZIG_ARCH=aarch64 ;; \
      *) echo "unsupported TARGETARCH=$ARCH" >&2; exit 1 ;; \
    esac; \
    ZIG_PRE="zig-${ZIG_ARCH}-linux-${ZIG_VERSION}"; \
    wget -q -O /tmp/zig.tar.xz "https://ziglang.org/download/${ZIG_VERSION}/${ZIG_PRE}.tar.xz"; \
    tar -xJf /tmp/zig.tar.xz -C /opt; \
    ln -s "/opt/${ZIG_PRE}/zig" /usr/local/bin/zig
WORKDIR /src
COPY build.zig build.zig.zon ./
COPY backend ./backend
RUN zig build -Doptimize=ReleaseFast

FROM alpine:3.21
RUN apk add --no-cache sqlite-libs libgcc
COPY --from=zigbuild /src/zig-out/bin/nemo /usr/local/bin/nemo
COPY --from=frontend /frontend/dist /app/frontend/dist
ENV WEB_DIST=/app/frontend/dist
ENV NEMO_PORT=5053
ENV NEMO_DB_PATH=/data/nemo.db
WORKDIR /app
EXPOSE 5053
VOLUME ["/data"]
CMD ["/usr/local/bin/nemo"]
