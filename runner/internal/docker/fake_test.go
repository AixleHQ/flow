package docker

import (
	"archive/tar"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path"
	"regexp"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/moby/moby/api/types/container"
	"github.com/moby/moby/api/types/volume"
	"github.com/moby/moby/client"
)

// fakeEngine is a fake of the Docker Engine API, served over HTTP so that the real
// SDK client talks to it: the version handshake, /version, /info, images,
// containers, exec (hijacked, with the multiplexed stream), the archive API and
// volumes.
type fakeEngine struct {
	mu         sync.Mutex
	apiVersion string
	images     map[string]bool
	// pullError is sent in the progress stream, the way a registry failure arrives.
	pullError string
	// pullStatus, when set, refuses the pull with that HTTP status before streaming.
	pullStatus int
	// pullDelay holds every pull that long before it answers, or until the
	// client gives up.
	pullDelay time.Duration
	pulls     []string
	// pullAuths is the X-Registry-Auth of every pull, "" for an anonymous one.
	pullAuths []string
	rootDir   string

	containers map[string]*fakeContainer
	execs      map[string]*fakeExec
	volumes    map[string]*fakeVolume
	seq        int
	// run decides what an exec does. It is called without the lock held.
	run func(x *fakeExec, stdin []byte) fakeRun
	// startError refuses every container start with a 500.
	startError string
	// scrubExit is the exit code of the container that empties the outputs.
	scrubExit int
	// release ends every exec that is still blocked when the test ends.
	release chan struct{}
	creates []container.CreateRequest
	// onCreate, when set, runs once a create has made its container. The create
	// then never answers: it waits until the client gives up.
	onCreate func()
	removed  []string
	// removeBlocks keeps every container removal from answering until the
	// client gives up, as a stalled daemon does.
	removeBlocks bool
	// removeError refuses every container removal with a 500.
	removeError string
	// bindsNotVisible refuses every bind mount, as a daemon that does not see
	// the client's files does.
	bindsNotVisible bool
	// startErrorFor refuses the start of the containers with these names.
	startErrorFor map[string]string
	// waitFailures breaks that many container waits, the next ones first, as
	// a daemon whose wait stream fails does: the headers, then no body.
	waitFailures int
	// waits counts every container wait.
	waits int
	// logsBlock keeps every container log read from answering until the
	// client gives up, as a stalled logs endpoint or log driver does.
	logsBlock bool
	// logReads counts every container log read.
	logReads int
}

type fakeContainer struct {
	ID     string
	Name   string
	Config container.Config
	Host   container.HostConfig
	State  container.State
	Files  map[string]*fakeFile
	// Logs is the container's log, served as stdout.
	Logs   []byte
	exited chan struct{}
}

type fakeFile struct {
	Content []byte
	Mode    int64
	UID     int
	GID     int
	Link    string
	Dir     bool
}

type fakeExec struct {
	ID        string
	Container string
	Request   container.ExecCreateRequest
	Running   bool
	ExitCode  *int
	Stdin     []byte
	Started   bool
}

// fakeRun is the outcome of an exec: its output, its exit code, and how long it
// takes. block, when set, keeps it running until the channel is closed.
type fakeRun struct {
	Stdout, Stderr []byte
	Code           int
	Delay          time.Duration
	Block          chan struct{}
}

type fakeVolume struct {
	Name   string
	Labels map[string]string
	// Files are the volume's content, by path relative to its root.
	Files map[string][]byte
}

var versionedPath = regexp.MustCompile(`^/v[0-9.]+(/.*)$`)

func (f *fakeEngine) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Api-Version", f.apiVersion)
	p := r.URL.Path
	if m := versionedPath.FindStringSubmatch(p); m != nil {
		p = m[1]
	}
	switch {
	case p == "/_ping":
		_, _ = w.Write([]byte("OK"))
	case p == "/version":
		writeJSON(w, http.StatusOK, map[string]any{"Version": "27.1.0", "ApiVersion": f.apiVersion, "MinAPIVersion": "1.24", "Os": "linux", "Arch": "amd64"})
	case p == "/info":
		writeJSON(w, http.StatusOK, map[string]any{"DockerRootDir": f.rootDir})
	case strings.HasPrefix(p, "/images/"):
		f.serveImages(w, r, p)
	case strings.HasPrefix(p, "/containers/"):
		f.serveContainers(w, r, p)
	case strings.HasPrefix(p, "/exec/"):
		f.serveExec(w, r, p)
	case strings.HasPrefix(p, "/volumes"):
		f.serveVolumes(w, r, p)
	default:
		notFound(w, r)
	}
}

func notFound(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusNotFound, map[string]any{"message": fmt.Sprintf("page not found: %s %s", r.Method, r.URL.Path)})
}

func (f *fakeEngine) serveImages(w http.ResponseWriter, r *http.Request, p string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	switch {
	case strings.HasSuffix(p, "/json") && r.Method == http.MethodGet:
		ref := strings.TrimSuffix(strings.TrimPrefix(p, "/images/"), "/json")
		if !f.images[ref] {
			writeJSON(w, http.StatusNotFound, map[string]any{"message": "No such image: " + ref})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"Id": "sha256:" + strings.Repeat("0", 64), "RepoDigests": []string{ref}})
	case p == "/images/create" && r.Method == http.MethodPost:
		// The SDK sends a digest as the `tag`, as the daemon's API takes it.
		tag := r.URL.Query().Get("tag")
		separator := ":"
		if strings.HasPrefix(tag, "sha256:") {
			separator = "@"
		}
		ref := r.URL.Query().Get("fromImage") + separator + tag
		f.pulls = append(f.pulls, ref)
		f.pullAuths = append(f.pullAuths, r.Header.Get("X-Registry-Auth"))
		if f.pullDelay > 0 {
			select {
			case <-time.After(f.pullDelay):
			case <-r.Context().Done():
				return
			}
		}
		if f.pullStatus != 0 {
			writeJSON(w, f.pullStatus, map[string]any{"message": "pull access denied for " + r.URL.Query().Get("fromImage")})
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		enc := json.NewEncoder(w)
		_ = enc.Encode(map[string]any{"status": "Pulling from " + r.URL.Query().Get("fromImage"), "id": tag})
		if f.pullError != "" {
			_ = enc.Encode(map[string]any{"errorDetail": map[string]any{"message": f.pullError}, "error": f.pullError})
			return
		}
		_ = enc.Encode(map[string]any{"status": "Digest: " + tag})
		f.images[ref] = true
	default:
		notFound(w, r)
	}
}

func (f *fakeEngine) nextID() string {
	f.seq++
	return fmt.Sprintf("%064x", f.seq)
}

// lookup finds a container by ID or name. The caller holds the lock.
func (f *fakeEngine) lookup(ref string) *fakeContainer {
	if c, ok := f.containers[ref]; ok {
		return c
	}
	for _, c := range f.containers {
		if c.Name == ref || strings.HasPrefix(c.ID, ref) && len(ref) >= 12 {
			return c
		}
	}
	return nil
}

func labelsMatch(labels map[string]string, filters map[string]map[string]bool) bool {
	for term := range filters["label"] {
		k, v, hasValue := strings.Cut(term, "=")
		got, ok := labels[k]
		if !ok || hasValue && got != v {
			return false
		}
	}
	return true
}

func parseFilters(r *http.Request) map[string]map[string]bool {
	var filters map[string]map[string]bool
	if raw := r.URL.Query().Get("filters"); raw != "" {
		_ = json.Unmarshal([]byte(raw), &filters)
	}
	return filters
}

func (f *fakeEngine) serveContainers(w http.ResponseWriter, r *http.Request, p string) {
	rest := strings.TrimPrefix(p, "/containers/")
	switch {
	case rest == "create" && r.Method == http.MethodPost:
		f.createContainer(w, r)
		return
	case rest == "json" && r.Method == http.MethodGet:
		f.listContainers(w, r)
		return
	}
	ref, action, _ := strings.Cut(rest, "/")
	if action == "wait" {
		f.waitContainer(w, r, ref)
		return
	}
	if action == "logs" && r.Method == http.MethodGet {
		f.mu.Lock()
		c := f.lookup(ref)
		var logs []byte
		if c != nil {
			logs = append(logs, c.Logs...)
		}
		f.logReads++
		blocks := f.logsBlock
		f.mu.Unlock()
		if blocks {
			<-r.Context().Done()
			return
		}
		if c == nil {
			writeJSON(w, http.StatusNotFound, map[string]any{"message": "No such container: " + ref})
			return
		}
		w.Header().Set("Content-Type", "application/vnd.docker.multiplexed-stream")
		w.WriteHeader(http.StatusOK)
		if len(logs) > 0 {
			writeFrames(w, 1, logs)
		}
		return
	}
	if action == "" && r.Method == http.MethodDelete {
		f.mu.Lock()
		blocks := f.removeBlocks
		f.mu.Unlock()
		if blocks {
			<-r.Context().Done()
			return
		}
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	c := f.lookup(ref)
	if c == nil {
		writeJSON(w, http.StatusNotFound, map[string]any{"message": "No such container: " + ref})
		return
	}
	switch {
	case action == "start" && r.Method == http.MethodPost:
		if f.startError != "" {
			writeJSON(w, http.StatusInternalServerError, map[string]any{"message": f.startError})
			return
		}
		if message, ok := f.startErrorFor[c.Name]; ok {
			writeJSON(w, http.StatusInternalServerError, map[string]any{"message": message})
			return
		}
		c.State = container.State{Status: container.StateRunning, Running: true, Pid: 4242}
		if c.Config.Labels[LabelRole] == "scrub" {
			f.runScrub(c)
		}
		w.WriteHeader(http.StatusNoContent)
	case action == "stop" && r.Method == http.MethodPost:
		if !c.State.Running {
			w.WriteHeader(http.StatusNotModified)
			return
		}
		f.exit(c, 143)
		w.WriteHeader(http.StatusNoContent)
	case action == "json" && r.Method == http.MethodGet:
		state := c.State
		config, host := c.Config, c.Host
		writeJSON(w, http.StatusOK, container.InspectResponse{ID: c.ID, Name: "/" + c.Name, State: &state, Config: &config, HostConfig: &host, Image: "sha256:" + strings.Repeat("1", 64)})
	case action == "" && r.Method == http.MethodDelete:
		if f.removeError != "" {
			writeJSON(w, http.StatusInternalServerError, map[string]any{"message": f.removeError})
			return
		}
		if c.State.Running && r.URL.Query().Get("force") != "1" {
			writeJSON(w, http.StatusConflict, map[string]any{"message": "container is running"})
			return
		}
		if c.State.Running {
			f.exit(c, 137)
		}
		delete(f.containers, c.ID)
		f.removed = append(f.removed, c.Name)
		w.WriteHeader(http.StatusNoContent)
	case action == "exec" && r.Method == http.MethodPost:
		var req container.ExecCreateRequest
		_ = json.NewDecoder(r.Body).Decode(&req)
		if !c.State.Running {
			writeJSON(w, http.StatusConflict, map[string]any{"message": "container " + c.ID + " is not running"})
			return
		}
		x := &fakeExec{ID: f.nextID(), Container: c.ID, Request: req}
		f.execs[x.ID] = x
		writeJSON(w, http.StatusCreated, map[string]any{"Id": x.ID})
	case action == "archive" && r.Method == http.MethodPut:
		f.putArchive(w, r, c)
	case action == "archive" && r.Method == http.MethodGet:
		f.getArchive(w, r, c)
	default:
		notFound(w, r)
	}
}

// exit stops a container with an exit code. The caller holds the lock.
func (f *fakeEngine) exit(c *fakeContainer, code int) {
	c.State = container.State{Status: container.StateExited, ExitCode: code}
	select {
	case <-c.exited:
	default:
		close(c.exited)
	}
	for _, x := range f.execs {
		if x.Container == c.ID {
			x.Running = false
		}
	}
}

// runScrub plays the container that empties the outputs: it deletes what is
// under outputs/ on the workspace volume it mounts, and exits.
func (f *fakeEngine) runScrub(c *fakeContainer) {
	for _, m := range c.Host.Mounts {
		v, ok := f.volumes[m.Source]
		if !ok || m.Target != WorkspaceTarget {
			continue
		}
		for name := range v.Files {
			if strings.HasPrefix(name, "outputs/") {
				delete(v.Files, name)
			}
		}
	}
	f.exit(c, f.scrubExit)
}

func (f *fakeEngine) createContainer(w http.ResponseWriter, r *http.Request) {
	var req container.CreateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": err.Error()})
		return
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	f.creates = append(f.creates, req)
	name := r.URL.Query().Get("name")
	if !f.images[req.Config.Image] {
		writeJSON(w, http.StatusNotFound, map[string]any{"message": "No such image: " + req.Config.Image})
		return
	}
	if name != "" && f.lookup(name) != nil {
		writeJSON(w, http.StatusConflict, map[string]any{"message": "Conflict. The container name \"/" + name + "\" is already in use"})
		return
	}
	for _, m := range req.HostConfig.Mounts {
		if m.Type == "bind" && f.bindsNotVisible {
			writeJSON(w, http.StatusBadRequest, map[string]any{"message": "invalid mount config for type \"bind\": bind source path does not exist: " + m.Source})
			return
		}
		if m.Type == "volume" {
			if _, ok := f.volumes[m.Source]; !ok {
				f.volumes[m.Source] = &fakeVolume{Name: m.Source, Labels: map[string]string{}, Files: map[string][]byte{}}
			}
		}
	}
	c := &fakeContainer{ID: f.nextID(), Name: name, Config: *req.Config, Host: *req.HostConfig,
		State: container.State{Status: container.StateCreated}, Files: map[string]*fakeFile{}, exited: make(chan struct{})}
	f.containers[c.ID] = c
	if f.onCreate != nil {
		// The container exists, but its answer waits until the client gives up.
		hook := f.onCreate
		f.mu.Unlock()
		hook()
		<-r.Context().Done()
		f.mu.Lock()
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"Id": c.ID, "Warnings": []string{}})
}

func (f *fakeEngine) listContainers(w http.ResponseWriter, r *http.Request) {
	filters := parseFilters(r)
	all := r.URL.Query().Get("all") == "1"
	f.mu.Lock()
	defer f.mu.Unlock()
	out := []container.Summary{}
	for _, c := range f.containers {
		if !all && !c.State.Running {
			continue
		}
		if !labelsMatch(c.Config.Labels, filters) {
			continue
		}
		out = append(out, container.Summary{ID: c.ID, Names: []string{"/" + c.Name}, Labels: c.Config.Labels, State: c.State.Status})
	}
	sort.Slice(out, func(i, k int) bool { return out[i].ID < out[k].ID })
	writeJSON(w, http.StatusOK, out)
}

func (f *fakeEngine) waitContainer(w http.ResponseWriter, r *http.Request, ref string) {
	f.mu.Lock()
	c := f.lookup(ref)
	f.mu.Unlock()
	if c == nil {
		writeJSON(w, http.StatusNotFound, map[string]any{"message": "No such container: " + ref})
		return
	}
	// The daemon answers the headers at once and the body at the exit.
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.(http.Flusher).Flush()
	f.mu.Lock()
	f.waits++
	broken := f.waitFailures > 0
	if broken {
		f.waitFailures--
	}
	f.mu.Unlock()
	if broken {
		_, _ = w.Write([]byte("{\"StatusCo"))
		return
	}
	select {
	case <-c.exited:
	case <-r.Context().Done():
		return
	case <-time.After(5 * time.Second):
		return
	}
	f.mu.Lock()
	code := c.State.ExitCode
	f.mu.Unlock()
	_ = json.NewEncoder(w).Encode(container.WaitResponse{StatusCode: int64(code)})
}

func (f *fakeEngine) serveExec(w http.ResponseWriter, r *http.Request, p string) {
	id, action, _ := strings.Cut(strings.TrimPrefix(p, "/exec/"), "/")
	f.mu.Lock()
	x, ok := f.execs[id]
	f.mu.Unlock()
	if !ok {
		writeJSON(w, http.StatusNotFound, map[string]any{"message": "No such exec instance: " + id})
		return
	}
	switch {
	case action == "json" && r.Method == http.MethodGet:
		f.mu.Lock()
		defer f.mu.Unlock()
		writeJSON(w, http.StatusOK, container.ExecInspectResponse{ID: x.ID, ContainerID: x.Container, Running: x.Running, ExitCode: x.ExitCode, Pid: 77})
	case action == "start" && r.Method == http.MethodPost:
		// The start request's own body is read before the connection is hijacked.
		_, _ = io.Copy(io.Discard, r.Body)
		f.startExec(w, x)
	default:
		notFound(w, r)
	}
}

// startExec hijacks the connection, as the daemon does, reads stdin to its end,
// and writes the command's output as the multiplexed stream of a non-TTY exec.
func (f *fakeEngine) startExec(w http.ResponseWriter, x *fakeExec) {
	conn, buf, err := w.(http.Hijacker).Hijack()
	if err != nil {
		return
	}
	defer conn.Close()
	_, _ = buf.WriteString("HTTP/1.1 101 UPGRADED\r\nContent-Type: application/vnd.docker.multiplexed-stream\r\nConnection: Upgrade\r\nUpgrade: tcp\r\n\r\n")
	_ = buf.Flush()

	f.mu.Lock()
	x.Running, x.Started = true, true
	f.mu.Unlock()
	var stdin []byte
	if x.Request.AttachStdin {
		stdin, _ = io.ReadAll(buf)
	}
	f.mu.Lock()
	x.Stdin = stdin
	run := f.run
	f.mu.Unlock()
	outcome := fakeRun{Stdout: []byte("ok\n")}
	if run != nil {
		outcome = run(x, stdin)
	}
	if outcome.Block != nil {
		select {
		case <-outcome.Block:
		case <-f.release:
		}
	}
	if outcome.Delay > 0 {
		time.Sleep(outcome.Delay)
	}
	writeFrames(conn, 1, outcome.Stdout)
	writeFrames(conn, 2, outcome.Stderr)
	f.mu.Lock()
	code := outcome.Code
	x.Running, x.ExitCode = false, &code
	f.mu.Unlock()
}

func writeFrames(w io.Writer, stream byte, data []byte) {
	for len(data) > 0 {
		n := min(len(data), 32<<10)
		header := make([]byte, 8)
		header[0] = stream
		binary.BigEndian.PutUint32(header[4:], uint32(n))
		if _, err := w.Write(append(header, data[:n]...)); err != nil {
			return
		}
		data = data[n:]
	}
}

func (f *fakeEngine) putArchive(w http.ResponseWriter, r *http.Request, c *fakeContainer) {
	dest := r.URL.Query().Get("path")
	tr := tar.NewReader(r.Body)
	for {
		h, err := tr.Next()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"message": err.Error()})
			return
		}
		content, _ := io.ReadAll(tr)
		c.Files[path.Join(dest, h.Name)] = &fakeFile{Content: content, Mode: h.Mode, UID: h.Uid, GID: h.Gid}
	}
	w.WriteHeader(http.StatusOK)
}

func (f *fakeEngine) getArchive(w http.ResponseWriter, r *http.Request, c *fakeContainer) {
	p := r.URL.Query().Get("path")
	file, ok := c.Files[p]
	if !ok {
		writeJSON(w, http.StatusNotFound, map[string]any{"message": "Could not find the file " + p + " in container " + c.Name})
		return
	}
	stat := container.PathStat{Name: path.Base(p), Size: int64(len(file.Content)), Mode: os.FileMode(file.Mode) & os.ModePerm}
	header := &tar.Header{Name: path.Base(p), Mode: file.Mode, Size: int64(len(file.Content)), Typeflag: tar.TypeReg}
	switch {
	case file.Link != "":
		stat.Mode |= os.ModeSymlink
		stat.LinkTarget, stat.Size = file.Link, 0
		header.Typeflag, header.Linkname, header.Size = tar.TypeSymlink, file.Link, 0
	case file.Dir:
		stat.Mode |= os.ModeDir
		stat.Size = 0
		header.Typeflag, header.Size = tar.TypeDir, 0
	}
	raw, _ := json.Marshal(stat)
	w.Header().Set("X-Docker-Container-Path-Stat", base64.StdEncoding.EncodeToString(raw))
	w.Header().Set("Content-Type", "application/x-tar")
	w.WriteHeader(http.StatusOK)
	tw := tar.NewWriter(w)
	_ = tw.WriteHeader(header)
	if header.Typeflag == tar.TypeReg {
		_, _ = tw.Write(file.Content)
	}
	_ = tw.Close()
}

func (f *fakeEngine) serveVolumes(w http.ResponseWriter, r *http.Request, p string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	switch {
	case p == "/volumes" && r.Method == http.MethodGet:
		filters := parseFilters(r)
		out := []volume.Volume{}
		for _, v := range f.volumes {
			if labelsMatch(v.Labels, filters) {
				out = append(out, volume.Volume{Name: v.Name, Labels: v.Labels, Driver: "local"})
			}
		}
		sort.Slice(out, func(i, k int) bool { return out[i].Name < out[k].Name })
		writeJSON(w, http.StatusOK, volume.ListResponse{Volumes: out})
	case p == "/volumes/create" && r.Method == http.MethodPost:
		var req volume.CreateRequest
		_ = json.NewDecoder(r.Body).Decode(&req)
		v, ok := f.volumes[req.Name]
		if !ok {
			v = &fakeVolume{Name: req.Name, Labels: req.Labels, Files: map[string][]byte{}}
			if v.Labels == nil {
				v.Labels = map[string]string{}
			}
			f.volumes[req.Name] = v
		}
		writeJSON(w, http.StatusCreated, volume.Volume{Name: v.Name, Labels: v.Labels, Driver: "local"})
	default:
		name := strings.TrimPrefix(p, "/volumes/")
		v, ok := f.volumes[name]
		if !ok {
			writeJSON(w, http.StatusNotFound, map[string]any{"message": "get " + name + ": no such volume"})
			return
		}
		switch r.Method {
		case http.MethodGet:
			writeJSON(w, http.StatusOK, volume.Volume{Name: v.Name, Labels: v.Labels, Driver: "local"})
		case http.MethodDelete:
			for _, c := range f.containers {
				for _, m := range c.Host.Mounts {
					if m.Source == name {
						writeJSON(w, http.StatusConflict, map[string]any{"message": "remove " + name + ": volume is in use - [" + c.ID + "]"})
						return
					}
				}
			}
			delete(f.volumes, name)
			w.WriteHeader(http.StatusNoContent)
		default:
			notFound(w, r)
		}
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
	f := &fakeEngine{
		apiVersion: "1.47", images: map[string]bool{}, rootDir: "/var/lib/docker",
		containers: map[string]*fakeContainer{}, execs: map[string]*fakeExec{}, volumes: map[string]*fakeVolume{},
		release: make(chan struct{}),
	}
	// No credentials of the machine the tests run on reach a pull.
	withDockerConfig(t, `{}`)
	server := httptest.NewServer(f)
	t.Cleanup(server.Close)
	t.Cleanup(func() { close(f.release) })
	c, err := client.New(client.WithHost("tcp://" + strings.TrimPrefix(server.URL, "http://")))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { c.Close() })
	return f, c
}
