package overlay

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"regexp"
	"strings"
	"time"
)

var panelPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9_-]{0,79}$`)

type Message struct {
	Panel     string   `json:"panel"`
	Platform  string   `json:"platform"`
	Kind      string   `json:"kind"`
	ID        string   `json:"id,omitempty"`
	Author    string   `json:"author,omitempty"`
	Text      string   `json:"text"`
	Color     string   `json:"color,omitempty"`
	Badges    []string `json:"badges,omitempty"`
	Timestamp int64    `json:"timestamp,omitempty"`
	Channel   string   `json:"channel,omitempty"`
	UserID    string   `json:"user_id,omitempty"`
	StreamID  string   `json:"stream_id,omitempty"`
	Streak    int      `json:"streak,omitempty"`
}

func NormalizePanel(value string) string { return strings.ToLower(strings.TrimSpace(value)) }
func ValidPanel(value string) bool       { return panelPattern.MatchString(NormalizePanel(value)) }

func (m *Message) Validate() error {
	m.Panel = NormalizePanel(m.Panel)
	m.Platform = strings.ToLower(strings.TrimSpace(m.Platform))
	m.Kind = strings.ToLower(strings.TrimSpace(m.Kind))
	if !ValidPanel(m.Panel) {
		return fmt.Errorf("invalid panel")
	}
	if m.Platform == "" || len(m.Platform) > 24 {
		return fmt.Errorf("invalid platform")
	}
	if m.Kind == "" || len(m.Kind) > 48 {
		return fmt.Errorf("invalid kind")
	}
	if len(m.ID) > 160 || len(m.Author) > 200 || len(m.Text) > 4000 || len(m.Color) > 32 || len(m.Channel) > 200 || len(m.UserID) > 200 || len(m.StreamID) > 200 {
		return fmt.Errorf("message field exceeds limit")
	}
	if len(m.Badges) > 32 {
		return fmt.Errorf("too many badges")
	}
	for i := range m.Badges {
		if len(m.Badges[i]) > 80 {
			return fmt.Errorf("badge exceeds limit")
		}
	}
	if m.Timestamp == 0 {
		m.Timestamp = time.Now().UnixMilli()
	}
	return nil
}

func PostMessage(ctx context.Context, port int, message Message) error {
	if err := message.Validate(); err != nil {
		return err
	}
	body, _ := json.Marshal(message)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, fmt.Sprintf("http://127.0.0.1:%d/api/events", port), bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusAccepted {
		return fmt.Errorf("overlay returned HTTP %d", resp.StatusCode)
	}
	return nil
}
