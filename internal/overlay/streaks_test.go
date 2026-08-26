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

func TestContinuousUpdatesCannotPostponePersistence(t *testing.T) {
	path := filepath.Join(t.TempDir(), "streaks.json")
	tracker, err := NewStreakTracker(path)
	if err != nil {
		t.Fatal(err)
	}
	tracker.Start(Message{Platform: "youtube", Channel: "UC1", StreamID: "live"}, time.Now())
	for index := 0; index < 4; index++ {
		time.Sleep(100 * time.Millisecond)
		message := Message{Platform: "youtube", Channel: "UC1", StreamID: "live", UserID: string(rune('a' + index)), Author: "viewer"}
		tracker.Observe(&message)
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("state was not persisted during continuous updates: %v", err)
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
	first := Message{Platform: "youtube", Channel: "UC1", StreamID: "video-1", UserID: "viewer-1", Author: "Ana"}
	tracker.Observe(&first)
	if first.Streak != 1 {
		t.Fatalf("first streak = %d", first.Streak)
	}
	// The session remains pinned to Aug 25 even though the message arrives after midnight.
	late := Message{Platform: "youtube", Channel: "UC1", StreamID: "video-1", UserID: "viewer-1", Author: "Ana"}
	tracker.Observe(&late)
	if late.Streak != 1 {
		t.Fatalf("late streak = %d", late.Streak)
	}
	tracker.Start(Message{Platform: "youtube", Channel: "UC1", StreamID: "video-2"}, streakTime(t, "2026-08-26 20:00"))
	next := Message{Platform: "youtube", Channel: "UC1", StreamID: "video-2", UserID: "viewer-1", Author: "Ana"}
	tracker.Observe(&next)
	if next.Streak != 2 {
		t.Fatalf("next streak = %d", next.Streak)
	}
}

func TestTwoStreamsOnOneDayCountAsOneAndMissBreaksNextDay(t *testing.T) {
	tracker, _ := NewStreakTracker("")
	tracker.Start(Message{Platform: "kick", Channel: "caster", StreamID: "a"}, streakTime(t, "2026-08-24 10:00"))
	viewer := Message{Platform: "kick", Channel: "caster", StreamID: "a", UserID: "42", Author: "Ana"}
	tracker.Observe(&viewer)
	tracker.Start(Message{Platform: "kick", Channel: "caster", StreamID: "b"}, streakTime(t, "2026-08-24 22:00"))
	viewer = Message{Platform: "kick", Channel: "caster", StreamID: "b", UserID: "42", Author: "Ana"}
	tracker.Observe(&viewer)
	if viewer.Streak != 1 {
		t.Fatalf("same-day streak = %d", viewer.Streak)
	}
	tracker.Start(Message{Platform: "kick", Channel: "caster", StreamID: "c"}, streakTime(t, "2026-08-25 20:00"))
	// Ana misses Aug 25.
	tracker.Start(Message{Platform: "kick", Channel: "caster", StreamID: "d"}, streakTime(t, "2026-08-26 20:00"))
	viewer = Message{Platform: "kick", Channel: "caster", StreamID: "d", UserID: "42", Author: "Ana"}
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
	yt := Message{Platform: "youtube", Channel: "caster", StreamID: "youtube-1", UserID: "same", Author: "Ana"}
	tracker.Observe(&yt)
	tw := Message{Platform: "twitch", Channel: "caster", StreamID: "twitch-1", UserID: "same", Author: "Ana"}
	tracker.Observe(&tw)
	if yt.Streak != 1 || tw.Streak != 1 {
		t.Fatalf("cross-platform leak: yt=%d twitch=%d", yt.Streak, tw.Streak)
	}
}

func TestRepeatedStreamIDRemainsPinnedAcrossMidnight(t *testing.T) {
	tracker, _ := NewStreakTracker("")
	tracker.Start(Message{Platform: "kick", Channel: "caster", StreamID: "same"}, streakTime(t, "2026-08-25 23:50"))
	tracker.Start(Message{Platform: "kick", Channel: "caster", StreamID: "same"}, streakTime(t, "2026-08-26 00:10"))
	if tracker.sessions[streakScope("kick", "caster")].Day != "2026-08-25" {
		t.Fatal("repeated stream moved to the next day")
	}
}

func TestMismatchedStreamMessageIsNotObserved(t *testing.T) {
	tracker, _ := NewStreakTracker("")
	tracker.Start(Message{Platform: "youtube", Channel: "UC1", StreamID: "current"}, streakTime(t, "2026-08-25 20:00"))
	message := Message{Platform: "youtube", Channel: "UC1", StreamID: "old", UserID: "u1", Author: "Ana"}
	tracker.Observe(&message)
	if message.Streak != 0 || len(tracker.viewers) != 0 {
		t.Fatal("message from another stream was observed")
	}
}

func TestOpaqueChannelIDsPreserveCase(t *testing.T) {
	tracker, _ := NewStreakTracker("")
	tracker.Start(Message{Platform: "future", Channel: "ChannelA", StreamID: "one"}, streakTime(t, "2026-08-25 20:00"))
	tracker.Start(Message{Platform: "future", Channel: "channela", StreamID: "two"}, streakTime(t, "2026-08-25 20:00"))
	if len(tracker.sessions) != 2 {
		t.Fatalf("case-sensitive channels merged: %d", len(tracker.sessions))
	}
}

func TestStableIDsCannotCollideWithAuthorFallbacks(t *testing.T) {
	tracker, _ := NewStreakTracker("")
	tracker.Start(Message{Platform: "future", Channel: "channel", StreamID: "live"}, streakTime(t, "2026-08-25 20:00"))
	stable := Message{Platform: "future", Channel: "channel", StreamID: "live", UserID: "alice", Author: "Someone"}
	fallback := Message{Platform: "future", Channel: "channel", StreamID: "live", Author: "Alice"}
	tracker.Observe(&stable)
	tracker.Observe(&fallback)
	if len(tracker.viewers) != 2 {
		t.Fatalf("stable and fallback identities merged: %d", len(tracker.viewers))
	}
}

func TestOldViewerStateIsPrunedOnNewBroadcastDay(t *testing.T) {
	tracker, _ := NewStreakTracker("")
	scope := streakScope("kick", "caster")
	tracker.sessions[scope] = streakSession{StreamID: "previous", Day: "2026-08-25", Previous: "2026-08-24"}
	tracker.viewers[viewerKey(scope, "stale", "")] = streakViewer{Count: 8, LastViewedDay: "2026-08-23"}
	tracker.viewers[viewerKey(scope, "recent", "")] = streakViewer{Count: 2, LastViewedDay: "2026-08-25"}
	tracker.Start(Message{Platform: "kick", Channel: "caster", StreamID: "current"}, streakTime(t, "2026-08-26 20:00"))
	if len(tracker.viewers) != 1 {
		t.Fatalf("viewer state after prune = %d", len(tracker.viewers))
	}
}
