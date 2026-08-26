package overlay

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type streakSession struct {
	StreamID string `json:"stream_id"`
	Day      string `json:"day"`
	Previous string `json:"previous,omitempty"`
}

type streakViewer struct {
	Count         int    `json:"count"`
	LastViewedDay string `json:"last_viewed_day"`
}

type streakSnapshot struct {
	Sessions map[string]streakSession `json:"sessions"`
	Viewers  map[string]streakViewer  `json:"viewers"`
}

type StreakTracker struct {
	mu       sync.Mutex
	file     string
	sessions map[string]streakSession
	viewers  map[string]streakViewer
	timer    *time.Timer
}

func NewStreakTracker(file string) (*StreakTracker, error) {
	t := &StreakTracker{file: file, sessions: map[string]streakSession{}, viewers: map[string]streakViewer{}}
	if file == "" {
		return t, nil
	}
	raw, err := os.ReadFile(file)
	if err != nil && !os.IsNotExist(err) {
		return nil, err
	}
	if os.IsNotExist(err) {
		raw, _ = os.ReadFile(file + ".bak")
	}
	if len(raw) > 0 {
		var saved streakSnapshot
		if err := json.Unmarshal(raw, &saved); err != nil {
			backup, backupErr := os.ReadFile(file + ".bak")
			var recovered streakSnapshot
			if backupErr != nil || json.Unmarshal(backup, &recovered) != nil {
				return nil, fmt.Errorf("decode streak state: %w", err)
			}
			saved = recovered
		}
		if saved.Sessions != nil {
			t.sessions = saved.Sessions
		}
		if saved.Viewers != nil {
			t.viewers = saved.Viewers
		}
	}
	return t, nil
}

func streakScope(platform, channel string) string {
	return strings.ToLower(strings.TrimSpace(platform)) + "\x00" + strings.TrimSpace(channel)
}

func viewerKey(scope, userID, author string) string {
	identity := strings.TrimSpace(userID)
	if identity != "" {
		identity = "id:" + identity
	} else {
		identity = "author:" + strings.ToLower(strings.TrimSpace(author))
	}
	return scope + "\x00" + identity
}

func (t *StreakTracker) Start(message Message, now time.Time) {
	t.mu.Lock()
	defer t.mu.Unlock()
	scope := streakScope(message.Platform, message.Channel)
	if message.Channel == "" || message.StreamID == "" {
		return
	}
	day := now.Local().Format("2006-01-02")
	current, ok := t.sessions[scope]
	if ok && current.StreamID == message.StreamID {
		return
	}
	previous := current.Day
	if previous == day {
		previous = current.Previous
	}
	t.sessions[scope] = streakSession{StreamID: message.StreamID, Day: day, Previous: previous}
	if !ok || current.Day != day {
		prefix := scope + "\x00"
		for key, viewer := range t.viewers {
			if strings.HasPrefix(key, prefix) && viewer.LastViewedDay != day && viewer.LastViewedDay != previous {
				delete(t.viewers, key)
			}
		}
	}
	t.schedulePersistLocked()
}

func (t *StreakTracker) Observe(message *Message) {
	if message == nil || (message.Author == "" && message.UserID == "") || message.Channel == "" {
		return
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	scope := streakScope(message.Platform, message.Channel)
	session, ok := t.sessions[scope]
	if !ok || message.StreamID == "" || message.StreamID != session.StreamID {
		return
	}
	key := viewerKey(scope, message.UserID, message.Author)
	viewer := t.viewers[key]
	if viewer.LastViewedDay == session.Day {
		message.Streak = viewer.Count
		return
	}
	if viewer.LastViewedDay != "" && viewer.LastViewedDay == session.Previous {
		viewer.Count++
	} else {
		viewer.Count = 1
	}
	viewer.LastViewedDay = session.Day
	t.viewers[key] = viewer
	message.Streak = viewer.Count
	t.schedulePersistLocked()
}

func (t *StreakTracker) schedulePersistLocked() {
	if t.file == "" {
		return
	}
	if t.timer != nil {
		return
	}
	t.timer = time.AfterFunc(250*time.Millisecond, func() {
		t.mu.Lock()
		defer t.mu.Unlock()
		t.timer = nil
		t.persistLocked()
	})
}

func (t *StreakTracker) persistLocked() {
	if t.file == "" {
		return
	}
	raw, err := json.Marshal(streakSnapshot{Sessions: t.sessions, Viewers: t.viewers})
	if err != nil {
		return
	}
	if os.MkdirAll(filepath.Dir(t.file), 0700) != nil {
		return
	}
	tmp := t.file + ".tmp"
	if os.WriteFile(tmp, raw, 0600) != nil {
		return
	}
	backup := t.file + ".bak"
	if _, err := os.Stat(t.file); err == nil {
		_ = os.Remove(backup)
		if os.Rename(t.file, backup) != nil {
			_ = os.Remove(tmp)
			return
		}
	}
	if os.Rename(tmp, t.file) != nil {
		_ = os.Rename(backup, t.file)
		return
	}
}
