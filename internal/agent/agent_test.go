package agent

import (
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
)

func TestControlRejectsMissingToken(t *testing.T) {
	exe, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	agent, err := New("01234567890123456789012345678901", exe, 8764)
	if err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:8764/control/activate", nil)
	req.RemoteAddr = "127.0.0.1:12345"
	recorder := httptest.NewRecorder()
	agent.Handler().ServeHTTP(recorder, req)
	if recorder.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d", recorder.Code)
	}
}

func TestControlRejectsNonLoopbackHost(t *testing.T) {
	exe, _ := os.Executable()
	agent, _ := New("01234567890123456789012345678901", exe, 8764)
	req := httptest.NewRequest(http.MethodPost, "http://evil.example/control/activate", nil)
	req.RemoteAddr = "127.0.0.1:12345"
	req.Header.Set("Authorization", "Bearer 01234567890123456789012345678901")
	recorder := httptest.NewRecorder()
	agent.Handler().ServeHTTP(recorder, req)
	if recorder.Code != http.StatusForbidden {
		t.Fatalf("status = %d", recorder.Code)
	}
}
