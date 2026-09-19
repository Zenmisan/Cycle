package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

func newTestServer(token string) (*httptest.Server, *RelayServer) {
	relay := NewRelayServer(token)
	mux := http.NewServeMux()
	mux.Handle("/ws", relay)
	server := httptest.NewServer(mux)
	return server, relay
}

func TestAuthRejection(t *testing.T) {
	server, _ := newTestServer("secret123")
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/ws"

	// 1. No token -> 401
	_, resp, err := websocket.DefaultDialer.Dial(wsURL+"?device_id=node-a", nil)
	if err == nil {
		t.Fatalf("expected error connecting without token, got nil")
	}
	if resp != nil && resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expected 401 Unauthorized, got %d", resp.StatusCode)
	}

	// 2. Wrong token -> 401
	_, resp, err = websocket.DefaultDialer.Dial(wsURL+"?device_id=node-a&token=wrong-secret", nil)
	if err == nil {
		t.Fatalf("expected error connecting with wrong token, got nil")
	}
	if resp != nil && resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expected 401 Unauthorized, got %d", resp.StatusCode)
	}

	// 3. Correct token query parameter -> Success (101)
	conn, resp, err := websocket.DefaultDialer.Dial(wsURL+"?device_id=node-a&token=secret123", nil)
	if err != nil {
		t.Fatalf("failed to connect with valid token: %v", err)
	}
	defer conn.Close()
	if resp.StatusCode != http.StatusSwitchingProtocols {
		t.Fatalf("expected 101 Switching Protocols, got %d", resp.StatusCode)
	}

	// 4. Correct token Authorization header -> Success (101)
	header := http.Header{}
	header.Set("Authorization", "Bearer secret123")
	conn2, _, err := websocket.DefaultDialer.Dial(wsURL+"?device_id=node-b", header)
	if err != nil {
		t.Fatalf("failed to connect with Bearer header: %v", err)
	}
	defer conn2.Close()
}

func TestMessageRoutingBetweenTwoPeers(t *testing.T) {
	server, relay := newTestServer("")
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/ws"

	// Connect Client A
	connA, _, err := websocket.DefaultDialer.Dial(wsURL+"?device_id=node-a", nil)
	if err != nil {
		t.Fatalf("failed to connect client A: %v", err)
	}
	defer connA.Close()

	// Connect Client B
	connB, _, err := websocket.DefaultDialer.Dial(wsURL+"?device_id=node-b", nil)
	if err != nil {
		t.Fatalf("failed to connect client B: %v", err)
	}
	defer connB.Close()

	// Wait for both to be registered
	time.Sleep(50 * time.Millisecond)
	if relay.getClient("node-a") == nil || relay.getClient("node-b") == nil {
		t.Fatalf("clients not registered in server map")
	}

	// Client A sends message to Client B
	payloadMsg := map[string]string{"sync": "automerge-vector-clock-data"}
	payloadBytes, _ := json.Marshal(payloadMsg)

	msgToSend := InboundMessage{
		Type:    "send",
		To:      "node-b",
		Payload: payloadBytes,
	}
	if err := connA.WriteJSON(msgToSend); err != nil {
		t.Fatalf("Client A failed to write message: %v", err)
	}

	// Client B reads message
	connB.SetReadDeadline(time.Now().Add(2 * time.Second))
	var received OutboundMessage
	if err := connB.ReadJSON(&received); err != nil {
		t.Fatalf("Client B failed to read message: %v", err)
	}

	if received.Type != "message" {
		t.Fatalf("expected message type 'message', got %s", received.Type)
	}
	if received.From != "node-a" {
		t.Fatalf("expected from 'node-a', got %s", received.From)
	}
	if !strings.Contains(string(received.Payload), "automerge-vector-clock-data") {
		t.Fatalf("payload mismatch, got: %s", string(received.Payload))
	}
}

func TestMessageToOfflinePeerReturnsError(t *testing.T) {
	server, _ := newTestServer("")
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/ws"

	connA, _, err := websocket.DefaultDialer.Dial(wsURL+"?device_id=node-a", nil)
	if err != nil {
		t.Fatalf("failed to connect client A: %v", err)
	}
	defer connA.Close()

	// Send message to non-existent node-offline
	msg := InboundMessage{
		Type:    "send",
		To:      "node-offline",
		Payload: []byte(`"hello"`),
	}
	if err := connA.WriteJSON(msg); err != nil {
		t.Fatalf("failed to write message: %v", err)
	}

	// Read error response back
	connA.SetReadDeadline(time.Now().Add(2 * time.Second))
	var resp OutboundMessage
	if err := connA.ReadJSON(&resp); err != nil {
		t.Fatalf("failed to read response: %v", err)
	}

	if resp.Type != "error" {
		t.Fatalf("expected response type 'error', got %s", resp.Type)
	}
	if resp.Error != "peer_offline" {
		t.Fatalf("expected error 'peer_offline', got %s", resp.Error)
	}
	if resp.PeerID != "node-offline" {
		t.Fatalf("expected peer_id 'node-offline', got %s", resp.PeerID)
	}
}

func TestDeferredJSONIdentification(t *testing.T) {
	server, relay := newTestServer("")
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/ws"

	// Connect without query parameter
	conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("failed to connect: %v", err)
	}
	defer conn.Close()

	// Send identify message
	ident := InboundMessage{
		Type:     "identify",
		DeviceID: "node-deferred",
	}
	if err := conn.WriteJSON(ident); err != nil {
		t.Fatalf("failed to write identify: %v", err)
	}

	// Read ack
	conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	var ack OutboundMessage
	if err := conn.ReadJSON(&ack); err != nil {
		t.Fatalf("failed to read identify ack: %v", err)
	}

	if ack.Type != "identified" || ack.PeerID != "node-deferred" {
		t.Fatalf("unexpected identify ack: %+v", ack)
	}

	time.Sleep(30 * time.Millisecond)
	if relay.getClient("node-deferred") == nil {
		t.Fatalf("node-deferred not registered in server map")
	}
}

func TestBinaryMessageRouting(t *testing.T) {
	server, _ := newTestServer("")
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/ws"

	connA, _, err := websocket.DefaultDialer.Dial(wsURL+"?device_id=node-a", nil)
	if err != nil {
		t.Fatalf("failed to connect client A: %v", err)
	}
	defer connA.Close()

	connB, _, err := websocket.DefaultDialer.Dial(wsURL+"?device_id=node-b", nil)
	if err != nil {
		t.Fatalf("failed to connect client B: %v", err)
	}
	defer connB.Close()

	time.Sleep(30 * time.Millisecond)

	// Construct binary packet from A to B: [ToLen: 1 byte][To: "node-b"][Payload: 1, 2, 3, 4]
	toTarget := "node-b"
	payload := []byte{1, 2, 3, 4, 5}
	binPacket := append([]byte{byte(len(toTarget))}, []byte(toTarget)...)
	binPacket = append(binPacket, payload...)

	if err := connA.WriteMessage(websocket.BinaryMessage, binPacket); err != nil {
		t.Fatalf("failed to write binary message: %v", err)
	}

	// Client B reads binary packet
	connB.SetReadDeadline(time.Now().Add(2 * time.Second))
	msgType, receivedBytes, err := connB.ReadMessage()
	if err != nil {
		t.Fatalf("failed to read binary message on B: %v", err)
	}

	if msgType != websocket.BinaryMessage {
		t.Fatalf("expected binary message, got %d", msgType)
	}

	fromLen := int(receivedBytes[0])
	fromID := string(receivedBytes[1 : 1+fromLen])
	receivedPayload := receivedBytes[1+fromLen:]

	if fromID != "node-a" {
		t.Fatalf("expected from 'node-a', got %s", fromID)
	}
	if len(receivedPayload) != len(payload) || receivedPayload[0] != 1 {
		t.Fatalf("unexpected received payload: %v", receivedPayload)
	}
}

func TestDisconnectCleanup(t *testing.T) {
	server, relay := newTestServer("")
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/ws"

	conn, _, err := websocket.DefaultDialer.Dial(wsURL+"?device_id=temp-node", nil)
	if err != nil {
		t.Fatalf("failed to connect: %v", err)
	}

	time.Sleep(30 * time.Millisecond)
	if relay.getClient("temp-node") == nil {
		t.Fatalf("expected temp-node in registry")
	}

	// Close connection
	conn.Close()

	// Wait for readPump to detect close and unregister
	time.Sleep(100 * time.Millisecond)
	if relay.getClient("temp-node") != nil {
		t.Fatalf("expected temp-node to be removed after disconnect")
	}
}

func TestRustClientProtocolAlignment(t *testing.T) {
	server, relay := newTestServer("auth-secret-42")
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/ws"

	// 1. Connect bare (no query params, no HTTP headers) with wrong token in Connect message -> rejected
	connBad, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("bare connect failed: %v", err)
	}
	defer connBad.Close()

	badConnect := InboundMessage{
		Type:     "connect",
		DeviceID: "device-bad",
		Token:    "wrong-token",
	}
	if err := connBad.WriteJSON(badConnect); err != nil {
		t.Fatalf("failed to write bad connect: %v", err)
	}

	var badResp OutboundMessage
	connBad.SetReadDeadline(time.Now().Add(2 * time.Second))
	if err := connBad.ReadJSON(&badResp); err != nil {
		t.Fatalf("failed to read error on bad token: %v", err)
	}
	if badResp.Type != "error" || !strings.Contains(badResp.Message, "unauthorized") {
		t.Fatalf("expected unauthorized error, got: %+v", badResp)
	}

	// 2. Connect Side A and Side B with valid in-band Connect message
	connA, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("dial A failed: %v", err)
	}
	defer connA.Close()

	if err := connA.WriteJSON(InboundMessage{
		Type:     "connect",
		DeviceID: "device-a",
		Token:    "auth-secret-42",
	}); err != nil {
		t.Fatalf("A connect failed: %v", err)
	}

	connB, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("dial B failed: %v", err)
	}
	defer connB.Close()

	if err := connB.WriteJSON(InboundMessage{
		Type:     "connect",
		DeviceID: "device-b",
		Token:    "auth-secret-42",
	}); err != nil {
		t.Fatalf("B connect failed: %v", err)
	}

	time.Sleep(50 * time.Millisecond)
	if relay.getClient("device-a") == nil || relay.getClient("device-b") == nil {
		t.Fatalf("clients not registered after in-band connect")
	}

	// 3. A sends Data message to B
	dataPayload := json.RawMessage(`"base64encodedbytes=="`)
	if err := connA.WriteJSON(InboundMessage{
		Type:    "data",
		To:      "device-b",
		Payload: dataPayload,
	}); err != nil {
		t.Fatalf("A failed to write data message: %v", err)
	}

	// B reads Data message
	connB.SetReadDeadline(time.Now().Add(2 * time.Second))
	var receivedB OutboundMessage
	if err := connB.ReadJSON(&receivedB); err != nil {
		t.Fatalf("B failed to read data message: %v", err)
	}
	if receivedB.Type != "data" {
		t.Fatalf("expected type 'data', got '%s'", receivedB.Type)
	}
	if receivedB.From != "device-a" {
		t.Fatalf("expected from 'device-a', got '%s'", receivedB.From)
	}
	if string(receivedB.Payload) != `"base64encodedbytes=="` {
		t.Fatalf("payload mismatch: %s", string(receivedB.Payload))
	}

	// 4. A sends Data message to non-existent peer -> returns error with message field
	if err := connA.WriteJSON(InboundMessage{
		Type:    "data",
		To:      "offline-peer",
		Payload: dataPayload,
	}); err != nil {
		t.Fatalf("A failed to write offline data message: %v", err)
	}

	connA.SetReadDeadline(time.Now().Add(2 * time.Second))
	var errorResp OutboundMessage
	if err := connA.ReadJSON(&errorResp); err != nil {
		t.Fatalf("A failed to read error response: %v", err)
	}
	if errorResp.Type != "error" {
		t.Fatalf("expected type 'error', got '%s'", errorResp.Type)
	}
	if !strings.Contains(errorResp.Message, "offline-peer") {
		t.Fatalf("expected message to mention offline-peer, got: '%s'", errorResp.Message)
	}
}

