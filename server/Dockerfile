# Build from the repo root: docker build -f server/Dockerfile .
#
# Stage 1: AOT-compile the server. `dart compile exe` links against the
# build image's glibc (it is NOT a fully static ELF — the build prints
# `ldd` output below), so the runtime base must be the same-or-newer
# Debian release as dart:stable. Stage 2 therefore matches it, and
# provides libsqlite3-0: package:sqlite3 loads the system libsqlite3.so.0
# at runtime (no bundled copy on native targets) — distro SQLite is
# audited and patched, costs ~1 MB, and beats carrying our own build.
# Keep the two FROM lines in sync: the build-stage `head /etc/os-release`
# line tells you which Debian release dart:stable currently tracks.
FROM dart:stable AS build
WORKDIR /app
COPY packages/dayspark_contracts packages/dayspark_contracts
COPY server/pubspec.yaml server/pubspec.lock server/
WORKDIR /app/server
RUN dart pub get
COPY server/ .
RUN dart run build_runner build && \
    dart compile exe bin/server.dart -o /app/dayspark_server
# Introspection for operators/report: glibc linkage + build base release.
RUN head -2 /etc/os-release && \
    (ldd /app/dayspark_server || echo "static? ldd unavailable")

# Same Debian release as dart:stable (trixie / Debian 13 as of 2026-09).
FROM debian:trixie-slim
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates curl libsqlite3-0 && \
    rm -rf /var/lib/apt/lists/*
COPY --from=build /app/dayspark_server /usr/local/bin/dayspark_server

# REQUIRE_JWT_SECRET makes startup fail fast when JWT_SECRET is missing
# or empty (Config.fromEnv throws) — never bake secrets into the image.
ENV DB_PATH=/data/dayspark.db \
    PORT=8787 \
    REQUIRE_JWT_SECRET=1

VOLUME ["/data"]
EXPOSE 8787

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${PORT}/health" || exit 1

CMD ["dayspark_server"]
