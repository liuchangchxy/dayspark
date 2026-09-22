# Build from the repo root: docker build -f server/Dockerfile .
FROM dart:stable AS build
WORKDIR /app
COPY packages/dayspark_contracts packages/dayspark_contracts
COPY server/pubspec.yaml server/pubspec.lock server/
WORKDIR /app/server
RUN dart pub get
COPY server/ .
RUN dart run build_runner build && \
    dart compile exe bin/server.dart -o /app/dayspark_server

FROM debian:bookworm-slim
RUN apt-get update && \
    apt-get install -y --no-install-recommends libsqlite3-0 ca-certificates && \
    rm -rf /var/lib/apt/lists/*
COPY --from=build /app/dayspark_server /usr/local/bin/dayspark_server
WORKDIR /data
ENV DB_PATH=/data/dayspark.db \
    PORT=8787
EXPOSE 8787
# JWT_SECRET must be provided at runtime before any non-local deployment.
CMD ["dayspark_server"]
