package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	authToken := os.Getenv("RELAY_AUTH_TOKEN")

	server := NewRelayServer(authToken)

	mux := http.NewServeMux()
	mux.Handle("/", server)
	mux.Handle("/ws", server)
	mux.HandleFunc("/health", server.handleHealth)

	httpServer := &http.Server{
		Addr:         ":" + port,
		Handler:      mux,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Graceful shutdown channel
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

	go func() {
		log.Printf("==========================================================")
		log.Printf(" Cycles Relay Server (Out-of-Proximity Transport)")
		log.Printf(" Listening on :%s", port)
		if authToken != "" {
			log.Printf(" Authentication: Enabled (Shared Secret)")
		} else {
			log.Printf(" Authentication: Disabled (Public / Local dev mode)")
		}
		log.Printf(" Design: Zero-Knowledge live relay (no task storage / no CRDT)")
		log.Printf("==========================================================")
		if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("[relay] Server failed: %v", err)
		}
	}()

	<-stop
	log.Printf("[relay] Shutting down server gracefully...")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := httpServer.Shutdown(ctx); err != nil {
		log.Printf("[relay] Server forced shutdown: %v", err)
	}

	log.Printf("[relay] Server exited cleanly.")
}
