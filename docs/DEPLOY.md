# Deployment Guide / 部署指南

Self-hosted DaySpark sync server (Docker + Docker Compose, e.g. on a NAS).
自托管 DaySpark 同步后端（Docker + Docker Compose，适用于 NAS 等常开设备）。

All state lives in **one SQLite file** at `/data/dayspark.db` inside the `dayspark-data` volume — backup and restore are that file.
全部数据就是 `dayspark-data` 卷里的**一个 SQLite 文件** `/data/dayspark.db` —— 备份与恢复即拷贝该文件。

---

## 1. Generate a JWT secret / 生成 JWT 密钥

The container refuses to start without `JWT_SECRET` (`REQUIRE_JWT_SECRET=1` → `Config.fromEnv` throws).
容器启动时强制要求 `JWT_SECRET`（缺失即快速失败退出）。

```bash
openssl rand -hex 32
```

Put it in `server/.env` (gitignored — never commit it):
写入 `server/.env`（已被 gitignore，切勿提交）：

```bash
cd server
cp .env.example .env
# edit .env → JWT_SECRET=<output of openssl rand -hex 32>
```

Rotating the secret later invalidates every access/refresh token — all users just log in again.
后续更换密钥会使所有令牌失效 —— 用户重新登录即可。

---

## 2. Deploy with Compose / 用 Compose 部署（NAS）

Prerequisites / 前置条件： Docker with the Compose plugin（`docker compose version` 可用），and the DaySpark repo on the device / 并将仓库放到设备上：

```bash
git clone https://github.com/liuchangchxy/dayspark.git
cd dayspark/server
cp .env.example .env   # fill JWT_SECRET (section 1) / 填入第 1 节的密钥
docker compose up -d --build
```

Verify / 验证：

```bash
curl http://<nas-ip>:8787/health
# {"ok":true,"version":"0.1.0"}
docker compose ps        # STATUS should show (healthy) / 应显示 (healthy)
```

Then in the app: **Settings → Server URL** = `http://<nas-ip>:8787`（局域网内）, log in / register.
应用内：**设置 → 服务器地址** 填 `http://<nas-ip>:8787`，登录或注册。

`docker-compose.yml` exposes port **8787**, mounts the `dayspark-data` volume at `/data`, and injects `JWT_SECRET` from `server/.env` — compose itself errors out if the variable is missing.
`docker-compose.yml` 映射 **8787** 端口、挂载 `dayspark-data` 卷到 `/data`，并从 `server/.env` 注入 `JWT_SECRET`（缺失时 compose 直接报错）。

---

## 3. Reverse proxy + SSE / 反向代理与 SSE

The client keeps an SSE stream open (`GET /sync/stream`) for invalidation push. Any buffering reverse proxy would delay or batch those events — nginx must be told not to buffer.
客户端通过 SSE 长连接（`GET /sync/stream`）接收失效推送；反代若缓冲会导致推送延迟/合并 —— nginx 必须关闭缓冲。

The server already sends `X-Accel-Buffering: no` on the SSE response, which nginx honors per-response; belt-and-braces, also disable buffering in the site config:
服务端已在 SSE 响应上发送 `X-Accel-Buffering: no`（nginx 会按响应遵守）；保险起见站点配置里再关一次缓冲：

```nginx
server {
    server_name sync.example.com;

    location / {
        proxy_pass http://127.0.0.1:8787;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection "";

        # SSE: never buffer the invalidation stream / SSE 失效流禁止缓冲
        proxy_buffering off;
        proxy_cache off;
        chunked_transfer_encoding on;

        # heartbeat every 25s; generous read timeout for the open stream
        # / 心跳 25s 一次，长连接读超时放宽
        proxy_read_timeout 1h;
        proxy_send_timeout 1h;
    }
}
```

If a health check or monitor probes `/health` through the proxy it works unchanged; only `/sync/stream` needs the settings above（`/health` 经反代照常可用，仅 `/sync/stream` 需要上述配置）.
Put TLS in front (section 4's `tailscale serve`, or certbot + the block above).
TLS 终止见第 4 节（`tailscale serve`）或 certbot + 上面的配置。

---

## 4. Access from outside the home (Tailscale) / 出门访问（Tailscale）

Do **not** port-forward 8787 to the public internet. Use a tailnet instead:
**不要**把 8787 直接映射到公网；用 tailnet（WireGuard 全 mesh）访问：

1. Install Tailscale on the NAS and on every client device（NAS 与每台客户端设备安装 Tailscale）, `tailscale up`, all in the same tailnet / 加入同一 tailnet.
2. Pick one / 二选一：
   - **Plain（局域网式）**: app Server URL = `http://100.x.y.z:8787`（NAS 的 tailnet IP）— traffic is encrypted by WireGuard / 流量由 WireGuard 加密，应用填 http 即可。
   - **TLS + stable hostname（推荐）**: on the NAS run `tailscale serve --bg http://127.0.0.1:8787`, then the app uses `https://<nas-machine>.<tailnet>.ts.net` — automatic证书, works through any NAT / 自动签证书、穿 NAT。
3. `tailscale serve` terminates TLS and forwards to the container on loopback — the compose port mapping can then stay LAN-only if you also firewall 8787（可选加固）。

Clients outside the home just keep Tailscale connected; sync behaves exactly as on the LAN.
出门时保持 Tailscale 连接即可，同步行为与局域网一致。

---

## 5. Backup / 备份

Stop → copy → start（停服拷贝最稳妥，包含可能存在的 `-wal`/`-shm` 文件）:

```bash
cd server
docker compose stop
docker run --rm -v dayspark-data:/data -v "$PWD":/backup alpine \
  tar czf "/backup/dayspark-db-$(date +%Y%m%d-%H%M).tar.gz" -C /data .
docker compose start
```

The archive holds `dayspark.db` (+ `-wal`/`-shm`) — that is the entire server state（压缩包里的 `dayspark.db` 即服务端全部状态）. Copy it off-device（再拷到别处做异地备份）.

## 6. Restore / 恢复

```bash
cd server
docker compose stop
docker run --rm -v dayspark-data:/data -v "$PWD":/backup alpine \
  tar xzf /backup/dayspark-db-YYYYMMDD-HHMM.tar.gz -C /data
docker compose start
curl http://<nas-ip>:8787/health   # {"ok":true,...}
```

Clients converge automatically on their next round — pull is watermark-based and will replay anything newer than the restored state.
客户端会在下一轮同步自动收敛 —— pull 按水位线增量拉取，会补齐恢复点之后的变更。

## 7. Update / 升级

```bash
cd dayspark && git pull         # or rsync new sources / 或同步新源码
cd server && docker compose up -d --build
```

Rebuild replaces the image; the `dayspark-data` volume is untouched, so data survives（重建只换镜像，`dayspark-data` 卷不受影响，数据保留）. Schema migrations run automatically at startup（schema 迁移在启动时自动执行）.

