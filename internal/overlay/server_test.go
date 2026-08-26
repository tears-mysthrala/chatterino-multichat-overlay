package overlay

import (
	"bufio"
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestMessageValidation(t *testing.T) {
	message := Message{Panel: " GilraenNR ", Platform: "KICK", Kind: "text_message", Author: "Ana", Text: "hola"}
	if err := message.Validate(); err != nil {
		t.Fatal(err)
	}
	if message.Panel != "gilraennr" || message.Platform != "kick" {
		t.Fatalf("not normalized: %#v", message)
	}
	if message.Timestamp == 0 {
		t.Fatal("timestamp not assigned")
	}
}

func TestIngestAndStreamHistory(t *testing.T) {
	server := httptest.NewServer(NewServer(10).Handler())
	defer server.Close()
	payload, _ := json.Marshal(Message{Panel: "gilraennr", Platform: "kick", Kind: "text_message", ID: "1", Author: "Ana", Text: "hola"})
	response, err := http.Post(server.URL+"/api/events", "application/json", bytes.NewReader(payload))
	if err != nil {
		t.Fatal(err)
	}
	if response.StatusCode != http.StatusAccepted {
		t.Fatalf("status %d", response.StatusCode)
	}
	response.Body.Close()

	stream, err := http.Get(server.URL + "/events/gilraennr")
	if err != nil {
		t.Fatal(err)
	}
	defer stream.Body.Close()
	line, err := bufio.NewReader(stream.Body).ReadString('\n')
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(line, `"author":"Ana"`) {
		t.Fatalf("unexpected SSE: %s", line)
	}
}

func TestRejectsUnknownFieldsAndInvalidPanel(t *testing.T) {
	server := httptest.NewServer(NewServer(10).Handler())
	defer server.Close()
	response, err := http.Post(server.URL+"/api/events", "application/json", strings.NewReader(`{"panel":"bad/panel","platform":"kick","kind":"text","text":"x","secret":"no"}`))
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusBadRequest {
		t.Fatalf("status %d", response.StatusCode)
	}
}

func TestOverlayEscapesPanelByValidation(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/overlay/gilraennr", nil)
	request.SetPathValue("panel", "gilraennr")
	recorder := httptest.NewRecorder()
	NewServer(10).overlay(recorder, request)
	if recorder.Code != http.StatusOK || !strings.Contains(recorder.Body.String(), `data-panel="gilraennr"`) {
		t.Fatal("overlay not rendered")
	}
}

func TestMessagesDoNotExpireOnATimer(t *testing.T) {
	css, err := webFiles.ReadFile("web/overlay.css")
	if err != nil {
		t.Fatal(err)
	}
	js, err := webFiles.ReadFile("web/overlay.js")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(css), "message-out") || strings.Contains(string(js), "animationend") {
		t.Fatal("overlay messages must persist until displaced by history limit")
	}
}

func TestBrowserAssetsAreNotCached(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/assets/overlay.js", nil)
	recorder := httptest.NewRecorder()
	NewServer(10).Handler().ServeHTTP(recorder, request)
	if recorder.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("cache-control = %q", recorder.Header().Get("Cache-Control"))
	}
}
