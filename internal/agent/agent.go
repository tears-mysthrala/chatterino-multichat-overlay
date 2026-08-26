package agent

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"
)

type Agent struct {
	token    string
	exePath  string
	port     int
	mu       sync.Mutex
	child    *exec.Cmd
	lastSeen time.Time
	updates  *updater
}

func New(token, exePath string, port int) (*Agent, error) {
	if len(token) < 32 {
		return nil, errors.New("control token is too short")
	}
	if port < 1024 || port > 65535 {
		return nil, errors.New("control port must be between 1024 and 65535")
	}
	info, err := os.Stat(exePath)
	if err != nil || info.IsDir() {
		return nil, errors.New("overlay executable is unavailable")
	}
	a := &Agent{token: strings.TrimSpace(token), exePath: exePath, port: port, updates: newUpdater(exePath)}
	go a.reapInactiveServer()
	return a, nil
}

func (a *Agent) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /control/health", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusNoContent) })
	mux.HandleFunc("POST /control/activate", a.activate)
	mux.HandleFunc("POST /control/heartbeat", a.heartbeat)
	mux.HandleFunc("GET /control/updates", a.updateStatus)
	mux.HandleFunc("POST /control/updates/{setting}", a.updateSetting)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		if !loopbackRequest(r) {
			http.Error(w, "loopback only", http.StatusForbidden)
			return
		}
		if !a.authorized(r.Header.Get("Authorization")) {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		mux.ServeHTTP(w, r)
	})
}

func (a *Agent) authorized(header string) bool {
	want := "Bearer " + a.token
	return len(header) == len(want) && subtle.ConstantTimeCompare([]byte(header), []byte(want)) == 1
}

func loopbackRequest(r *http.Request) bool {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil || net.ParseIP(host) == nil || !net.ParseIP(host).IsLoopback() {
		return false
	}
	requestHost := r.Host
	if parsed, _, err := net.SplitHostPort(requestHost); err == nil {
		requestHost = parsed
	}
	return requestHost == "127.0.0.1" || strings.EqualFold(requestHost, "localhost") || requestHost == "[::1]"
}

func (a *Agent) activate(w http.ResponseWriter, _ *http.Request) {
	a.touch()
	if err := a.ensureServer(); err != nil {
		http.Error(w, "overlay failed to start", http.StatusServiceUnavailable)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "active"})
}

func (a *Agent) heartbeat(w http.ResponseWriter, _ *http.Request) {
	a.touch()
	w.WriteHeader(http.StatusNoContent)
}

func (a *Agent) updateStatus(w http.ResponseWriter, r *http.Request) {
	manual := r.URL.Query().Get("manual") == "1"
	force := r.URL.Query().Get("force") == "1"
	result, err := a.updates.check(r.Context(), force)
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	if err != nil {
		if err.Error() == "disabled" && manual {
			fmt.Fprint(w, "Actualizaciones multichat desactivadas.")
		} else if manual {
			http.Error(w, "No se pudieron comprobar las actualizaciones.", http.StatusServiceUnavailable)
		} else {
			w.WriteHeader(http.StatusNoContent)
		}
		return
	}
	if len(result.Updates) == 0 {
		if manual {
			fmt.Fprint(w, "Todos los plugins multichat están actualizados.")
		}
		return
	}
	for i, update := range result.Updates {
		if i > 0 {
			fmt.Fprint(w, "\n")
		}
		fmt.Fprintf(w, "Actualización disponible: %s %s → %s · %s", update.Name, update.Installed, update.Latest, update.URL)
	}
}

func (a *Agent) updateSetting(w http.ResponseWriter, r *http.Request) {
	setting := r.PathValue("setting")
	if setting != "on" && setting != "off" {
		http.Error(w, "invalid setting", http.StatusBadRequest)
		return
	}
	if err := a.updates.setEnabled(setting == "on"); err != nil {
		http.Error(w, "settings unavailable", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	if setting == "on" {
		fmt.Fprint(w, "Avisos de actualizaciones activados.")
	} else {
		fmt.Fprint(w, "Avisos de actualizaciones desactivados.")
	}
}

func (a *Agent) touch() {
	a.mu.Lock()
	a.lastSeen = time.Now()
	a.mu.Unlock()
}

func (a *Agent) reapInactiveServer() {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()
	for range ticker.C {
		a.mu.Lock()
		if a.child != nil && !a.lastSeen.IsZero() && time.Since(a.lastSeen) > 15*time.Second {
			_ = a.child.Process.Kill()
			a.child = nil
		}
		a.mu.Unlock()
	}
}

func (a *Agent) ensureServer() error {
	if healthy(8765) {
		return nil
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	if healthy(8765) {
		return nil
	}
	cmd := exec.Command(a.exePath, "serve")
	configureHidden(cmd)
	if err := cmd.Start(); err != nil {
		return err
	}
	a.child = cmd
	go func() {
		_ = cmd.Wait()
		a.mu.Lock()
		if a.child == cmd {
			a.child = nil
		}
		a.mu.Unlock()
	}()
	for i := 0; i < 20; i++ {
		time.Sleep(100 * time.Millisecond)
		if healthy(8765) {
			return nil
		}
	}
	return fmt.Errorf("overlay health check timed out")
}

func healthy(port int) bool {
	client := &http.Client{Timeout: 250 * time.Millisecond}
	resp, err := client.Get(fmt.Sprintf("http://127.0.0.1:%d/health", port))
	if err != nil {
		return false
	}
	resp.Body.Close()
	return resp.StatusCode == http.StatusOK
}
