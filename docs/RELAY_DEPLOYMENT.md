# Cycles: Relay Server Deployment Guide

The Cycles Relay Server is an optional, lightweight, self-hosted Go service designed to facilitate synchronization when devices are separated by distance and cannot connect via Wi-Fi Direct, Local LAN, or BLE.

---

## 1. Architectural Role & Privacy Guarantees

- **Zero-Knowledge**: The relay server never inspects, decrypts, or understands Automerge CRDT documents or task data.
- **No Persistent State**: It does not store user data or message history in a database. It functions as an ephemeral store-and-forward routing router.
- **Resource Footprint**: Consumes under 15 MB of RAM and minimal CPU under load.

---

## 2. Docker & Docker Compose Deployment (Recommended)

### 2.1. `docker-compose.yml`
```yaml
version: '3.8'

services:
  cycles-relay:
    build:
      context: ./relay-server
      dockerfile: Dockerfile
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      - PORT=8080
      - RELAY_AUTH_TOKEN=your-strong-random-secret-token-here
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 5s
      retries: 3
```

### 2.2. Launching
```bash
docker compose up -d
```

Verify health:
```bash
curl http://localhost:8080/health
```

Expected response:
```json
{"active_clients":0,"auth_enabled":true,"service":"cycles-relay-server","status":"ok"}
```

---

## 3. Reverse Proxy Configuration with TLS

Because WebSocket connections carry sensitive metadata (device IDs), running behind TLS (`wss://`) is strongly recommended.

### 3.1. Caddy (Automatic HTTPS)
```caddy
relay.example.com {
    reverse_proxy localhost:8080
}
```

### 3.2. Nginx
```nginx
server {
    server_name relay.example.com;
    listen 443 ssl http2;

    ssl_certificate /etc/letsencrypt/live/relay.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/relay.example.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
```

---

## 4. Configuring Cycles Clients to Use the Relay

1. In the Cycles app, open **Settings** → **Remote Relay**.
2. Toggle **Enable Remote Relay**.
3. Set **Relay URL**: `wss://relay.example.com/ws`
4. Set **Auth Token**: Enter matching `RELAY_AUTH_TOKEN`.
5. Tap **Test Connection & Save**.
