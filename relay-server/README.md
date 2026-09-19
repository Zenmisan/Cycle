# Cycles Relay Server

Standalone, zero-knowledge WebSocket relay server for **Cycles** (Phase 6 Out-of-Proximity Transport).

---

## 🎯 Architectural Philosophy: The Dumb Pipe

Per [PLAN.md](file:///home/zenmi/Projects/Cycle/PLAN.md), the Cycles relay server is intentionally **dumb**:

- **Zero CRDT Knowledge**: The server has no concept of Automerge, tasks, projects, or sync logs.
- **Zero Content Storage**: The server never persists task payloads or message contents. It is a live store-and-forward relay.
- **Privacy-First**: The server routes opaque bytes between two connected `device_id` endpoints.
- **Self-Hosted & Opt-In**: Used only when two devices are out of physical proximity (no BLE, no local LAN, no Wi-Fi Direct), and only when explicitly configured by the user.

---

## 🔌 Wire Protocol

### 1. Connecting & Authentication

Clients establish a standard WebSocket connection to `/` or `/ws`:

```
ws://<host>:<port>/ws?device_id=<my_device_id>&token=<shared_secret>
```

- **Authentication**: Checked against `RELAY_AUTH_TOKEN`. Can be passed via:
  - **In-band handshake** (used by Rust `relay_client_20260919`):
    Immediately after WebSocket connection, send:
    ```json
    { "type": "connect", "device_id": "<my_device_id>", "token": "<shared_secret>" }
    ```
  - **Query parameter**: `?token=<secret>`
  - **HTTP Header**: `Authorization: Bearer <secret>`
  If authentication fails, the server responds with `401 Unauthorized` (HTTP upgrade) or `{ "type": "error", "message": "unauthorized: ..." }` (WebSocket).

- **Identification**:
  - In-band `connect` message: `{ "type": "connect", "device_id": "<id>", "token": "<secret>" }`
  - Query parameter: `?device_id=<my_device_id>`
  - Identify message: `{ "type": "identify", "device_id": "<my_device_id>" }`

### 2. Message Routing (JSON)

The wire protocol supports both `type: "data"` (Rust client default) and `type: "send"` / `type: "message"`:

#### Sending data to a peer:
```json
{
  "type": "data",
  "to": "<peer_device_id>",
  "payload": "<base64_crdt_bytes>"
}
```

#### Forwarded data received by peer:
```json
{
  "type": "data",
  "from": "<sender_device_id>",
  "payload": "<base64_crdt_bytes>"
}
```

#### Recipient offline error:
If the target peer is not connected, the server replies back to the sender:
```json
{
  "type": "error",
  "error": "peer_offline",
  "peer_id": "<peer_device_id>",
  "message": "peer_offline: <peer_device_id>"
}
```

### 3. Binary Message Routing

For low-overhead binary frames, the relay accepts raw binary frames:
- **Client to Relay**: `[ToLength: 1 byte][ToDeviceID: ToLength bytes][Payload: N bytes]`
- **Relay to Peer**: `[FromLength: 1 byte][FromDeviceID: FromLength bytes][Payload: N bytes]`

---

## 🚀 Building & Running

### Prerequisites
- Go 1.22+ (tested with Go 1.27)

### 1. Build
```bash
cd relay-server
go build -o cycles-relay
```

### 2. Run
```bash
# Run with default port 8080 and optional auth token
export PORT=8080
export RELAY_AUTH_TOKEN="your-shared-secret-key"

./cycles-relay
```

### 3. Health Check
```bash
curl http://localhost:8080/health
```
Response:
```json
{
  "active_clients": 0,
  "auth_enabled": true,
  "service": "cycles-relay-server",
  "status": "ok"
}
```

---

## 🐳 Docker Deployment

A lightweight Dockerfile is included:

```bash
cd relay-server
docker build -t cycles-relay .
docker run -d -p 8080:8080 -e RELAY_AUTH_TOKEN="secret" cycles-relay
```

---

## 🧪 Testing

Run the full automated test suite (covers authentication, routing, deferred identification, offline peer handling, binary frames, and clean disconnects):

```bash
cd relay-server
go test -v ./...
```
