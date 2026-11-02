package docker

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"sync"
	"testing"

	"github.com/moby/moby/client"
)

// fakeEngine is a fake of the Docker Engine API, served over HTTP so that the real
// SDK client talks to it: the version handshake, /version, /info, image inspect and
// image create (the pull).
type fakeEngine struct {
	mu         sync.Mutex
	apiVersion string
	images     map[string]bool
	// pullError is sent in the progress stream, the way a registry failure arrives.
	pullError string
	// pullStatus, when set, refuses the pull with that HTTP status before streaming.
	pullStatus int
	pulls      []string
	rootDir    string
}

var versionedPath = regexp.MustCompile(`^/v[0-9.]+(/.*)$`)

func (f *fakeEngine) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	f.mu.Lock()
	defer f.mu.Unlock()
	w.Header().Set("Api-Version", f.apiVersion)
	path := r.URL.Path
	if m := versionedPath.FindStringSubmatch(path); m != nil {
		path = m[1]
	}
	switch {
	case path == "/_ping":
		_, _ = w.Write([]byte("OK"))
	case path == "/version":
		writeJSON(w, http.StatusOK, map[string]any{"Version": "27.1.0", "ApiVersion": f.apiVersion, "MinAPIVersion": "1.24", "Os": "linux", "Arch": "amd64"})
	case path == "/info":
		writeJSON(w, http.StatusOK, map[string]any{"DockerRootDir": f.rootDir})
	case strings.HasPrefix(path, "/images/") && strings.HasSuffix(path, "/json") && r.Method == http.MethodGet:
		ref := strings.TrimSuffix(strings.TrimPrefix(path, "/images/"), "/json")
		if !f.images[ref] {
			writeJSON(w, http.StatusNotFound, map[string]any{"message": "No such image: " + ref})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"Id": "sha256:" + strings.Repeat("0", 64), "RepoDigests": []string{ref}})
	case path == "/images/create" && r.Method == http.MethodPost:
		ref := r.URL.Query().Get("fromImage") + "@" + r.URL.Query().Get("tag")
		f.pulls = append(f.pulls, ref)
		if f.pullStatus != 0 {
			writeJSON(w, f.pullStatus, map[string]any{"message": "pull access denied for " + r.URL.Query().Get("fromImage")})
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		enc := json.NewEncoder(w)
		_ = enc.Encode(map[string]any{"status": "Pulling from " + r.URL.Query().Get("fromImage"), "id": r.URL.Query().Get("tag")})
		if f.pullError != "" {
			_ = enc.Encode(map[string]any{"errorDetail": map[string]any{"message": f.pullError}, "error": f.pullError})
			return
		}
		_ = enc.Encode(map[string]any{"status": "Digest: " + r.URL.Query().Get("tag")})
		f.images[ref] = true
	default:
		writeJSON(w, http.StatusNotFound, map[string]any{"message": fmt.Sprintf("page not found: %s %s", r.Method, r.URL.Path)})
	}
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// newFakeEngine starts the fake and returns an SDK client of it.
func newFakeEngine(t *testing.T) (*fakeEngine, *client.Client) {
	t.Helper()
	f := &fakeEngine{apiVersion: "1.47", images: map[string]bool{}, rootDir: "/var/lib/docker"}
	server := httptest.NewServer(f)
	t.Cleanup(server.Close)
	c, err := client.New(client.WithHost("tcp://" + strings.TrimPrefix(server.URL, "http://")))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { c.Close() })
	return f, c
}
