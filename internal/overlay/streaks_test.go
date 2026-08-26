package overlay

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestCorruptStreakStateFailsClosed(t *testing.T) {
	path := filepath.Join(t.TempDir(), "streaks.json")
	if err := os.WriteFile(path, []byte("{"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := NewStreakTracker(path); err == nil {
		t.Fatal("corrupt streak state was silently discarded")
	}
}

func TestStreakStateRecoversFromBackup(t *testing.T) {
	path := filepath.Join(t.TempDir(), "streaks.json")
	if err := os.WriteFile(path, []byte("{"), 0600); err != nil {
		t.Fatal(err)
	}
	valid := `{"sessions":{},"viewers":{"youtube\\u0000UC1\\u0000u1":{"count":3,"last_viewed_day":"2026-08-25"}}}`
	if err := os.WriteFile(path+".bak", []byte(valid), 0600); err != nil {
		t.Fatal(err)
	}
	tracker, err := NewStreakTracker(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(tracker.viewers) != 1 {
		t.Fatalf("backup viewers = %d", len(tracker.viewers))
	}
}

func streakTime(t *testing.T, value string) time.Time {
	t.Helper()
	parsed, err := time.ParseInLocation("2006-01-02 15:04", value, time.Local)
	if err != nil {
		t.Fatal(err)
	}
	return parsed
}

func TestStreakUsesSessionDayAcrossMidnight(t *testing.T) {
	tracker, _ := NewStreakTracker(filepath.Join(t.TempDir(), "streaks.json"))
	tracker.Start(Message{Platform: "youtube", Channel: "UC1", StreamID: "video-1"}, streakTime(t, "2026-08-25 23:50"))
	first := Message{Platform: "youtube", Channel: "UC1", UserID: "viewer-1", Author: "Ana"}
	tracker.Observe(&first)
	if first.Streak != 1 {
		t.Fatalf("first streak = %d", first.Streak)
	}
	// The session remains pinned to Aug 25 even though the message arrives after midnight.
	late := Message{Platform: "youtube", Channel: "UC1", UserID: "viewer-1", Author: "Ana"}
	tracker.Observe(&late)
	if late.Streak != 1 {
		t.Fatalf("late streak = %d", late.Streak)
	}
	tracker.Start(Message{Platform: "youtube", Channel: "UC1", StreamID: "video-2"}, streakTime(t, "2026-08-26 20:00"))
	next := Message{Platform: "youtube", Channel: "UC1", UserID: "viewer-1", Author: "Ana"}
	tracker.Observe(&next)
	if next.Streak != 2 {
		t.Fatalf("next streak = %d", next.Streak)
	}
}

func TestTwoStreamsOnOneDayCountAsOneAndMissBreaksNextDay(t *testing.T) {
	tracker, _ := NewStreakTracker("")
	tracker.Start(Message{Platform: "kick", Channel: "caster", StreamID: "a"}, streakTime(t, "2026-08-24 10:00"))
	viewer := Message{Platform: "kick", Channel: "caster", UserID: "42", Author: "Ana"}
	tracker.Observe(&viewer)
	tracker.Start(Message{Platform: "kick", Channel: "caster", StreamID: "b"}, streakTime(t, "2026-08-24 22:00"))
	viewer = Message{Platform: "kick", Channel: "caster", UserID: "42", Author: "Ana"}
	tracker.Observe(&viewer)
	if viewer.Streak != 1 {
		t.Fatalf("same-day streak = %d", viewer.Streak)
	}
	tracker.Start(Message{Platform: "kick", Channel: "caster", StreamID: "c"}, streakTime(t, "2026-08-25 20:00"))
	// Ana misses Aug 25.
	tracker.Start(Message{Platform: "kick", Channel: "caster", StreamID: "d"}, streakTime(t, "2026-08-26 20:00"))
	viewer = Message{Platform: "kick", Channel: "caster", UserID: "42", Author: "Ana"}
	tracker.Observe(&viewer)
	if viewer.Streak != 1 {
		t.Fatalf("broken streak = %d", viewer.Streak)
	}
}

func TestStreaksAreSeparatedByPlatform(t *testing.T) {
	tracker, _ := NewStreakTracker("")
	for _, platform := range []string{"youtube", "twitch"} {
		tracker.Start(Message{Platform: platform, Channel: "caster", StreamID: platform + "-1"}, streakTime(t, "2026-08-25 20:00"))
	}
	yt := Message{Platform: "youtube", Channel: "caster", UserID: "same", Author: "Ana"}
	tracker.Observe(&yt)
	tw := Message{Platform: "twitch", Channel: "caster", UserID: "same", Author: "Ana"}
	tracker.Observe(&tw)
	if yt.Streak != 1 || tw.Streak != 1 {
		t.Fatalf("cross-platform leak: yt=%d twitch=%d", yt.Streak, tw.Streak)
	}
}
