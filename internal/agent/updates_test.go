package agent

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestUpdaterFindsOnlySupportedInstalledPlugins(t *testing.T) {
	root := t.TempDir()
	data := filepath.Join(root, "overlay", "data")
	if err := os.MkdirAll(data, 0o700); err != nil {
		t.Fatal(err)
	}
	writeManifest := func(dir, name, version, homepage string) {
		if err := os.MkdirAll(filepath.Join(root, dir), 0o700); err != nil {
			t.Fatal(err)
		}
		raw := fmt.Sprintf(`{"name":%q,"version":%q,"homepage":%q}`, name, version, homepage)
		if err := os.WriteFile(filepath.Join(root, dir, "info.json"), []byte(raw), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	writeManifest("kick", "chatterino-kick-chat", "0.1.0", "https://github.com/tears-mysthrala/chatterino-kick-chat")
	writeManifest("hostile", "hostile", "9.9.9", "https://evil.example/repo")

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `{"tag_name":"v0.2.0","html_url":"https://github.com/tears-mysthrala/chatterino-kick-chat/releases/tag/v0.2.0","draft":false,"prerelease":false}`)
	}))
	defer server.Close()
	u := &updater{pluginsRoot: root, dataDir: data, apiBase: server.URL, client: server.Client()}
	result, err := u.check(context.Background(), true)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Updates) != 1 || result.Updates[0].Latest != "0.2.0" {
		t.Fatalf("updates = %#v", result.Updates)
	}
}

func TestUpdaterUsesFreshCache(t *testing.T) {
	root := t.TempDir()
	data := filepath.Join(root, "overlay", "data")
	if err := os.MkdirAll(filepath.Join(root, "kick"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(data, 0o700); err != nil {
		t.Fatal(err)
	}
	manifest := `{"name":"chatterino-kick-chat","version":"0.1.0","homepage":"https://github.com/tears-mysthrala/chatterino-kick-chat"}`
	if err := os.WriteFile(filepath.Join(root, "kick", "info.json"), []byte(manifest), 0o600); err != nil {
		t.Fatal(err)
	}
	requests := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		requests++
		fmt.Fprint(w, `{"tag_name":"v0.2.0","html_url":"https://github.com/tears-mysthrala/chatterino-kick-chat/releases/tag/v0.2.0"}`)
	}))
	defer server.Close()
	u := &updater{pluginsRoot: root, dataDir: data, apiBase: server.URL, client: server.Client()}
	if _, err := u.check(context.Background(), false); err != nil {
		t.Fatal(err)
	}
	if _, err := u.check(context.Background(), false); err != nil {
		t.Fatal(err)
	}
	if requests != 1 {
		t.Fatalf("requests = %d, want 1", requests)
	}
}

func TestUpdaterInvalidatesFreshCacheWhenInstalledPluginsChange(t *testing.T) {
	root := t.TempDir()
	data := filepath.Join(root, "overlay", "data")
	kickDir := filepath.Join(root, "kick")
	if err := os.MkdirAll(kickDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(data, 0o700); err != nil {
		t.Fatal(err)
	}
	writeManifest := func(version string) {
		t.Helper()
		raw := fmt.Sprintf(`{"name":"chatterino-kick-chat","version":%q,"homepage":"https://github.com/tears-mysthrala/chatterino-kick-chat"}`, version)
		if err := os.WriteFile(filepath.Join(kickDir, "info.json"), []byte(raw), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	writeManifest("0.1.0")
	requests := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		repo, latest := "chatterino-kick-chat", "0.2.0"
		if strings.Contains(r.URL.Path, "chatterino-yt-chat") {
			repo, latest = "chatterino-yt-chat", "1.1.0"
		}
		fmt.Fprintf(w, `{"tag_name":"v%s","html_url":"https://github.com/tears-mysthrala/%s/releases/tag/v%s"}`, latest, repo, latest)
	}))
	defer server.Close()
	u := &updater{pluginsRoot: root, dataDir: data, apiBase: server.URL, client: server.Client()}
	first, err := u.check(context.Background(), false)
	if err != nil {
		t.Fatal(err)
	}
	if len(first.Updates) != 1 {
		t.Fatalf("first updates = %#v, want one update", first.Updates)
	}

	writeManifest("0.2.0")
	second, err := u.check(context.Background(), false)
	if err != nil {
		t.Fatal(err)
	}
	if len(second.Updates) != 0 {
		t.Fatalf("second updates = %#v, want none", second.Updates)
	}
	if requests != 2 {
		t.Fatalf("requests = %d, want 2 after installed version changed", requests)
	}

	youTubeDir := filepath.Join(root, "youtube")
	if err := os.MkdirAll(youTubeDir, 0o700); err != nil {
		t.Fatal(err)
	}
	youTubeManifest := `{"name":"chatterino-yt-chat","version":"1.0.0","homepage":"https://github.com/tears-mysthrala/chatterino-yt-chat"}`
	if err := os.WriteFile(filepath.Join(youTubeDir, "info.json"), []byte(youTubeManifest), 0o600); err != nil {
		t.Fatal(err)
	}
	third, err := u.check(context.Background(), false)
	if err != nil {
		t.Fatal(err)
	}
	if len(third.Updates) != 1 || third.Updates[0].Name != "chatterino-yt-chat" {
		t.Fatalf("third updates = %#v, want only YouTube after plugin addition", third.Updates)
	}
	if requests != 4 {
		t.Fatalf("requests = %d, want 4 after installed plugin was added", requests)
	}

	if err := os.RemoveAll(kickDir); err != nil {
		t.Fatal(err)
	}
	fourth, err := u.check(context.Background(), false)
	if err != nil {
		t.Fatal(err)
	}
	if len(fourth.Updates) != 1 || fourth.Updates[0].Name != "chatterino-yt-chat" {
		t.Fatalf("fourth updates = %#v, want only YouTube after plugin removal", fourth.Updates)
	}
	if requests != 5 {
		t.Fatalf("requests = %d, want 5 after installed plugin was removed", requests)
	}
}

func TestSemverComparisonRejectsPrereleases(t *testing.T) {
	if compareSemver("1.4.0", "1.3.9") <= 0 {
		t.Fatal("stable version was not newer")
	}
	if compareSemver("1.4.0-beta.1", "1.3.9") >= 0 {
		t.Fatal("prerelease must be rejected")
	}
}
