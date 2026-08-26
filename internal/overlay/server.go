package overlay

import (
	"embed"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

//go:embed web/*
var webFiles embed.FS

type Server struct {
	hub          *Hub
	started      time.Time
	historyFile  string
	persistMu    sync.Mutex
	persistTimer *time.Timer
}

func NewServer(historyLimit int) *Server {
	return &Server{hub: NewHub(historyLimit), started: time.Now()}
}

func NewPersistentServer(historyLimit int, historyFile string) (*Server, error) {
	s := NewServer(historyLimit)
	s.historyFile = historyFile
	raw, err := os.ReadFile(historyFile)
	if err != nil && !os.IsNotExist(err) {
		return nil, err
	}
	if len(raw) > 0 {
		var snapshot map[string][]Message
		if json.Unmarshal(raw, &snapshot) == nil {
			s.hub.Restore(snapshot)
		}
	}
	return s, nil
}

func (s *Server) schedulePersist() {
	if s.historyFile == "" {
		return
	}
	s.persistMu.Lock()
	defer s.persistMu.Unlock()
	if s.persistTimer != nil {
		s.persistTimer.Stop()
	}
	s.persistTimer = time.AfterFunc(250*time.Millisecond, s.persist)
}

func (s *Server) persist() {
	s.persistMu.Lock()
	defer s.persistMu.Unlock()
	raw, err := json.Marshal(s.hub.Snapshot())
	if err != nil {
		return
	}
	if os.MkdirAll(filepath.Dir(s.historyFile), 0700) != nil {
		return
	}
	temporary := s.historyFile + ".tmp"
	if os.WriteFile(temporary, raw, 0600) != nil {
		return
	}
	_ = os.Remove(s.historyFile)
	_ = os.Rename(temporary, s.historyFile)
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	assets, _ := fs.Sub(webFiles, "web")
	mux.Handle("GET /assets/", http.StripPrefix("/assets/", http.FileServer(http.FS(assets))))
	mux.HandleFunc("GET /{$}", s.index)
	mux.HandleFunc("GET /overlay/{panel}", s.overlay)
	mux.HandleFunc("GET /events/{panel}", s.events)
	mux.HandleFunc("POST /api/events", s.ingest)
	mux.HandleFunc("GET /health", s.health)
	return securityHeaders(mux)
}

func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' https: data:")
		next.ServeHTTP(w, r)
	})
}

func (s *Server) index(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	io.WriteString(w, `<!doctype html><meta charset="utf-8"><title>Multichat overlay</title><style>body{font:16px system-ui;background:#101218;color:#eef2f7;max-width:760px;margin:4rem auto;padding:0 2rem}code{color:#7ee787}</style><h1>Multichat overlay is running</h1><p>Use this URL as an OBS Browser Source:</p><code>http://127.0.0.1:8765/overlay/gilraennr</code>`)
}

func (s *Server) overlay(w http.ResponseWriter, r *http.Request) {
	panel := NormalizePanel(r.PathValue("panel"))
	if !ValidPanel(panel) {
		http.Error(w, "invalid panel", http.StatusBadRequest)
		return
	}
	raw, err := webFiles.ReadFile("web/overlay.html")
	if err != nil {
		http.Error(w, "overlay unavailable", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write(bytesReplaceAll(raw, "__PANEL__", panel))
}

func bytesReplaceAll(raw []byte, old, replacement string) []byte {
	return []byte(strings.ReplaceAll(string(raw), old, replacement))
}

func (s *Server) events(w http.ResponseWriter, r *http.Request) {
	panel := NormalizePanel(r.PathValue("panel"))
	if !ValidPanel(panel) {
		http.Error(w, "invalid panel", http.StatusBadRequest)
		return
	}
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming unavailable", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	stream, history, unsubscribe := s.hub.Subscribe(panel)
	defer unsubscribe()
	write := func(message Message) bool {
		encoded, _ := json.Marshal(message)
		_, err := fmt.Fprintf(w, "data: %s\n\n", encoded)
		flusher.Flush()
		return err == nil
	}
	for _, message := range history {
		if !write(message) {
			return
		}
	}
	keepalive := time.NewTicker(15 * time.Second)
	defer keepalive.Stop()
	for {
		select {
		case message := <-stream:
			if !write(message) {
				return
			}
		case <-keepalive.C:
			if _, err := io.WriteString(w, ": keepalive\n\n"); err != nil {
				return
			}
			flusher.Flush()
		case <-r.Context().Done():
			return
		}
	}
}

func (s *Server) ingest(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, 64*1024)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	var message Message
	if err := decoder.Decode(&message); err != nil {
		http.Error(w, "invalid event", http.StatusBadRequest)
		return
	}
	if err := message.Validate(); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	s.hub.Publish(message)
	s.schedulePersist()
	w.WriteHeader(http.StatusAccepted)
}

func (s *Server) health(w http.ResponseWriter, _ *http.Request) {
	panels, subscribers, messages := s.hub.Stats()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"status": "healthy", "uptime_ms": time.Since(s.started).Milliseconds(), "panels": panels, "subscribers": subscribers, "messages": messages})
}
