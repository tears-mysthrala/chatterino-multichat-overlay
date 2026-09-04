package agent

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
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

func TestUpdaterInvalidatesFreshCacheWhenInstalledVersionChanges(t *testing.T) {
	root := t.TempDir()
	data := filepath.Join(root, "overlay", "data")
	pluginDir := filepath.Join(root, "kick")
	if err := os.MkdirAll(pluginDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(data, 0o700); err != nil {
		t.Fatal(err)
	}
	writeManifest := func(version string) {
		t.Helper()
		raw := fmt.Sprintf(`{"name":"chatterino-kick-chat","version":%q,"homepage":"https://github.com/tears-mysthrala/chatterino-kick-chat"}`, version)
		if err := os.WriteFile(filepath.Join(pluginDir, "info.json"), []byte(raw), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	writeManifest("0.1.0")
	requests := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		requests++
		fmt.Fprint(w, `{"tag_name":"v0.2.0","html_url":"https://github.com/tears-mysthrala/chatterino-kick-chat/releases/tag/v0.2.0"}`)
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
}

func TestSemverComparisonRejectsPrereleases(t *testing.T) {
	if compareSemver("1.4.0", "1.3.9") <= 0 {
		t.Fatal("stable version was not newer")
	}
	if compareSemver("1.4.0-beta.1", "1.3.9") >= 0 {
		t.Fatal("prerelease must be rejected")
	}
}
