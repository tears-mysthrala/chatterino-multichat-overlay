package agent

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

const updateCacheTTL = 24 * time.Hour

var supportedPlugins = map[string]string{
	"chatterino-multichat-overlay": "tears-mysthrala/chatterino-multichat-overlay",
	"chatterino-kick-chat":         "tears-mysthrala/chatterino-kick-chat",
	"chatterino-yt-chat":           "tears-mysthrala/chatterino-yt-chat",
}

type updateInfo struct {
	Name      string `json:"name"`
	Installed string `json:"installed"`
	Latest    string `json:"latest"`
	URL       string `json:"url"`
}

type updateCache struct {
	CheckedAt time.Time    `json:"checked_at"`
	Updates   []updateInfo `json:"updates"`
}

type updater struct {
	pluginsRoot string
	dataDir     string
	apiBase     string
	client      *http.Client
}

func newUpdater(exePath string) *updater {
	pluginRoot := filepath.Dir(filepath.Dir(exePath))
	return &updater{pluginsRoot: filepath.Dir(pluginRoot), dataDir: filepath.Join(pluginRoot, "data"), apiBase: "https://api.github.com", client: &http.Client{Timeout: 5 * time.Second}}
}

func (u *updater) enabled() bool {
	raw, err := os.ReadFile(filepath.Join(u.dataDir, "updates.disabled"))
	return err != nil || strings.TrimSpace(string(raw)) != "1"
}

func (u *updater) setEnabled(enabled bool) error {
	path := filepath.Join(u.dataDir, "updates.disabled")
	if enabled {
		if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
		return nil
	}
	return os.WriteFile(path, []byte("1\n"), 0o600)
}

func (u *updater) check(ctx context.Context, force bool) (updateCache, error) {
	if !u.enabled() {
		return updateCache{}, errors.New("disabled")
	}
	if !force {
		if cached, ok := u.readCache(); ok && time.Since(cached.CheckedAt) < updateCacheTTL {
			return cached, nil
		}
	}
	installed, err := u.installedPlugins()
	if err != nil {
		return updateCache{}, err
	}
	result := updateCache{CheckedAt: time.Now().UTC()}
	names := make([]string, 0, len(installed))
	for name := range installed {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		version := installed[name]
		repo := supportedPlugins[name]
		latest, releaseURL, err := u.latest(ctx, repo)
		if err != nil {
			return updateCache{}, err
		}
		if compareSemver(latest, version) > 0 {
			result.Updates = append(result.Updates, updateInfo{Name: name, Installed: version, Latest: latest, URL: releaseURL})
		}
	}
	if err := os.MkdirAll(u.dataDir, 0o700); err != nil {
		return updateCache{}, err
	}
	raw, _ := json.Marshal(result)
	if err := os.WriteFile(filepath.Join(u.dataDir, "updates.json"), raw, 0o600); err != nil {
		return updateCache{}, err
	}
	return result, nil
}

func (u *updater) installedPlugins() (map[string]string, error) {
	entries, err := os.ReadDir(u.pluginsRoot)
	if err != nil {
		return nil, err
	}
	installed := map[string]string{}
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		var manifest struct{ Name, Version, Homepage string }
		raw, err := os.ReadFile(filepath.Join(u.pluginsRoot, entry.Name(), "info.json"))
		if err != nil || json.Unmarshal(raw, &manifest) != nil {
			continue
		}
		repo, supported := supportedPlugins[manifest.Name]
		if !supported || manifest.Version == "" || manifest.Homepage != "https://github.com/"+repo {
			continue
		}
		installed[manifest.Name] = manifest.Version
	}
	return installed, nil
}

func (u *updater) latest(ctx context.Context, repo string) (string, string, error) {
	endpoint := u.apiBase + "/repos/" + repo + "/releases/latest"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return "", "", err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "chatterino-multichat-overlay")
	resp, err := u.client.Do(req)
	if err != nil {
		return "", "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", "", fmt.Errorf("GitHub HTTP %d", resp.StatusCode)
	}
	var release struct {
		TagName    string `json:"tag_name"`
		HTMLURL    string `json:"html_url"`
		Draft      bool   `json:"draft"`
		Prerelease bool   `json:"prerelease"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&release); err != nil {
		return "", "", err
	}
	if release.Draft || release.Prerelease || compareSemver(release.TagName, "0.0.0") < 0 {
		return "", "", errors.New("invalid stable release")
	}
	parsed, err := url.Parse(release.HTMLURL)
	if err != nil || parsed.Scheme != "https" || parsed.Host != "github.com" {
		return "", "", errors.New("invalid release URL")
	}
	return strings.TrimPrefix(release.TagName, "v"), release.HTMLURL, nil
}

func (u *updater) readCache() (updateCache, bool) {
	var cached updateCache
	raw, err := os.ReadFile(filepath.Join(u.dataDir, "updates.json"))
	return cached, err == nil && json.Unmarshal(raw, &cached) == nil && !cached.CheckedAt.IsZero()
}

func compareSemver(left, right string) int {
	parse := func(value string) ([3]int, bool) {
		value = strings.TrimPrefix(strings.TrimSpace(value), "v")
		if strings.ContainsAny(value, "+-") {
			return [3]int{}, false
		}
		parts := strings.Split(value, ".")
		if len(parts) != 3 {
			return [3]int{}, false
		}
		var out [3]int
		for i, part := range parts {
			n, err := strconv.Atoi(part)
			if err != nil || n < 0 {
				return out, false
			}
			out[i] = n
		}
		return out, true
	}
	a, okA := parse(left)
	b, okB := parse(right)
	if !okA || !okB {
		return -1
	}
	for i := range a {
		if a[i] < b[i] {
			return -1
		}
		if a[i] > b[i] {
			return 1
		}
	}
	return 0
}
