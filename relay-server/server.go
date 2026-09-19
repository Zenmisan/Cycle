package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

const (
	writeWait      = 10 * time.Second
	pongWait       = 60 * time.Second
	pingPeriod     = (pongWait * 9) / 10
	maxMessageSize = 10 * 1024 * 1024 // 10 MB maximum payload per message
)

// InboundMessage represents a client message to route to a peer.
type InboundMessage struct {
	Type     string          `json:"type,omitempty"`
	To       string          `json:"to,omitempty"`
	DeviceID string          `json:"device_id,omitempty"`
	Token    string          `json:"token,omitempty"`
	Payload  json.RawMessage `json:"payload,omitempty"`
}

// OutboundMessage represents a forwarded message to the recipient.
type OutboundMessage struct {
	Type    string          `json:"type"`
	From    string          `json:"from,omitempty"`
	PeerID  string          `json:"peer_id,omitempty"`
	Error   string          `json:"error,omitempty"`
	Message string          `json:"message,omitempty"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

// Client represents a connected device WebSocket session.
type Client struct {
	server        *RelayServer
	conn          *websocket.Conn
	deviceID      string
	send          chan []byte
	mu            sync.Mutex
	closed        bool
	authenticated bool
}

func (c *Client) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			w, err := c.conn.NextWriter(websocket.TextMessage)
			if err != nil {
				return
			}
			w.Write(message)
			if err := w.Close(); err != nil {
				return
			}
		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

func (c *Client) readPump() {
	defer func() {
		c.server.unregister(c)
		c.conn.Close()
	}()

	c.conn.SetReadLimit(maxMessageSize)
	c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		messageType, data, err := c.conn.ReadMessage()
		if err != nil {
			break
		}

		if messageType == websocket.BinaryMessage {
			c.handleBinaryMessage(data)
		} else {
			c.handleTextMessage(data)
		}
	}
}

func (c *Client) handleTextMessage(data []byte) {
	var in InboundMessage
	if err := json.Unmarshal(data, &in); err != nil {
		c.sendError("invalid_json", "Invalid JSON message syntax")
		return
	}

	// If client is not yet authenticated, require in-band authentication
	if !c.authenticated {
		if (in.Type == "connect" || in.Type == "identify") && (c.server.authToken == "" || in.Token == c.server.authToken) {
			c.authenticated = true
		} else {
			c.sendErrorAndClose("unauthorized", "Invalid or missing auth token")
			return
		}
	}

	// Handle deferred identification if not identified via query parameter
	if c.deviceID == "" {
		if (in.Type == "identify" || in.Type == "connect") && in.DeviceID != "" {
			c.deviceID = in.DeviceID
			c.server.register(c)
			if in.Type == "identify" {
				c.sendMessage(&OutboundMessage{
					Type:   "identified",
					PeerID: c.deviceID,
				})
			}
			return
		}
		c.sendError("unidentified", "Device must identify with device_id first")
		return
	}

	if in.To == "" {
		c.sendError("missing_recipient", "'to' field is required")
		return
	}

	// Route to target client
	target := c.server.getClient(in.To)
	if target == nil {
		c.sendErrorWithPeer("peer_offline", in.To)
		return
	}

	outType := "data"
	if in.Type == "send" || in.Type == "message" {
		outType = "message"
	}

	out := OutboundMessage{
		Type:    outType,
		From:    c.deviceID,
		Payload: in.Payload,
	}
	outBytes, err := json.Marshal(out)
	if err == nil {
		target.enqueue(outBytes)
	}
}

func (c *Client) handleBinaryMessage(data []byte) {
	if !c.authenticated || c.deviceID == "" {
		c.sendError("unidentified", "Device must authenticate and identify before sending binary messages")
		return
	}

	// Binary framing: [ToLen: 1 byte][ToID: ToLen bytes][Payload: rest...]
	if len(data) < 2 {
		c.sendError("invalid_binary_frame", "Binary frame too short")
		return
	}
	toLen := int(data[0])
	if len(data) < 1+toLen {
		c.sendError("invalid_binary_frame", "Binary frame header corrupted")
		return
	}

	toID := string(data[1 : 1+toLen])
	payload := data[1+toLen:]

	target := c.server.getClient(toID)
	if target == nil {
		c.sendErrorWithPeer("peer_offline", toID)
		return
	}

	// Construct forwarded binary frame: [FromLen: 1 byte][FromID: FromLen bytes][Payload: rest...]
	fromBytes := []byte(c.deviceID)
	var buf bytes.Buffer
	buf.WriteByte(byte(len(fromBytes)))
	buf.Write(fromBytes)
	buf.Write(payload)

	target.conn.SetWriteDeadline(time.Now().Add(writeWait))
	target.conn.WriteMessage(websocket.BinaryMessage, buf.Bytes())
}

func (c *Client) enqueue(msg []byte) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed {
		return
	}
	select {
	case c.send <- msg:
	default:
		// Queue full or client slow, drop to prevent blocking relay
	}
}

func (c *Client) sendMessage(msg *OutboundMessage) {
	bytes, err := json.Marshal(msg)
	if err == nil {
		c.enqueue(bytes)
	}
}

func (c *Client) sendError(errCode, message string) {
	c.sendMessage(&OutboundMessage{
		Type:    "error",
		Error:   errCode,
		Message: fmt.Sprintf("%s: %s", errCode, message),
	})
}

func (c *Client) sendErrorAndClose(errCode, message string) {
	c.sendError(errCode, message)
	time.AfterFunc(60*time.Millisecond, func() {
		c.conn.Close()
	})
}

func (c *Client) sendErrorWithPeer(errCode, peerID string) {
	c.sendMessage(&OutboundMessage{
		Type:    "error",
		Error:   errCode,
		PeerID:  peerID,
		Message: fmt.Sprintf("%s: %s", errCode, peerID),
	})
}

// RelayServer maintains concurrent active client connections and routes payloads.
type RelayServer struct {
	mu          sync.RWMutex
	clients     map[string]*Client
	authToken   string
	upgrader    websocket.Upgrader
	statsMu     sync.Mutex
	routesCount uint64
}

// NewRelayServer creates a new RelayServer instance.
func NewRelayServer(authToken string) *RelayServer {
	return &RelayServer{
		clients:   make(map[string]*Client),
		authToken: authToken,
		upgrader: websocket.Upgrader{
			ReadBufferSize:  1024,
			WriteBufferSize: 1024,
			CheckOrigin: func(r *http.Request) bool {
				return true // Permissive for native cross-platform clients
			},
		},
	}
}

func (s *RelayServer) authenticate(r *http.Request) bool {
	if s.authToken == "" {
		return true // No auth configured (public/local mode)
	}

	// 1. Check Authorization header: Bearer <token>
	authHeader := r.Header.Get("Authorization")
	if strings.HasPrefix(authHeader, "Bearer ") {
		token := strings.TrimPrefix(authHeader, "Bearer ")
		if token == s.authToken {
			return true
		}
	}

	// 2. Check query parameter: ?token=<token>
	queryToken := r.URL.Query().Get("token")
	if queryToken == s.authToken {
		return true
	}

	return false
}

func (s *RelayServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/health" || r.URL.Path == "/status" {
		s.handleHealth(w, r)
		return
	}

	authenticated := (s.authToken == "")
	if s.authToken != "" {
		hasAuthHeader := r.Header.Get("Authorization") != ""
		hasTokenQuery := r.URL.Query().Get("token") != ""
		hasDeviceQuery := r.URL.Query().Get("device_id") != ""

		if hasAuthHeader || hasTokenQuery {
			if !s.authenticate(r) {
				http.Error(w, "Unauthorized: invalid or missing auth token", http.StatusUnauthorized)
				return
			}
			authenticated = true
		} else if hasDeviceQuery {
			// Query parameter identification attempted without authentication
			http.Error(w, "Unauthorized: auth token required", http.StatusUnauthorized)
			return
		}
	}

	conn, err := s.upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[relay] WebSocket upgrade error: %v", err)
		return
	}

	deviceID := r.URL.Query().Get("device_id")

	client := &Client{
		server:        s,
		conn:          conn,
		deviceID:      deviceID,
		send:          make(chan []byte, 256),
		authenticated: authenticated,
	}

	if deviceID != "" && authenticated {
		s.register(client)
	}

	go client.writePump()
	client.readPump()
}

func (s *RelayServer) register(c *Client) {
	s.mu.Lock()
	defer s.mu.Unlock()

	// If old client exists with same deviceID, close it
	if old, exists := s.clients[c.deviceID]; exists && old != c {
		old.conn.Close()
	}
	s.clients[c.deviceID] = c
	log.Printf("[relay] Device registered: %s (active: %d)", c.deviceID, len(s.clients))
}

func (s *RelayServer) unregister(c *Client) {
	s.mu.Lock()
	defer s.mu.Unlock()

	c.mu.Lock()
	c.closed = true
	c.mu.Unlock()

	if current, exists := s.clients[c.deviceID]; exists && current == c {
		delete(s.clients, c.deviceID)
		log.Printf("[relay] Device unregistered: %s (active: %d)", c.deviceID, len(s.clients))
	}
}

func (s *RelayServer) getClient(deviceID string) *Client {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.clients[deviceID]
}

func (s *RelayServer) handleHealth(w http.ResponseWriter, r *http.Request) {
	s.mu.RLock()
	activeClients := len(s.clients)
	s.mu.RUnlock()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"status":         "ok",
		"service":        "cycles-relay-server",
		"active_clients": activeClients,
		"auth_enabled":   s.authToken != "",
	})
}
