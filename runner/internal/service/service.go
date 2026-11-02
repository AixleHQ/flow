// Package service is `aixle-runner service install | uninstall | start | stop`: a
// systemd unit that runs `aixle-runner --mode host` as the dedicated `aixle-runner`
// system user, in the `docker` group (DESIGN.md §6.3, §9.7).
package service

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
	"text/template"

	"github.com/aixlehq/aixle-runner/internal/fsutil"
)

const (
	// UnitName is the systemd unit.
	UnitName = "aixle-runner.service"
	// User is the system user the service runs as.
	User = "aixle-runner"
	// DockerGroup is the group that may use the Docker socket. It is
	// root-equivalent on the machine (§9.7).
	DockerGroup = "docker"
	// ExitStop is the exit code of a host runner stopped by a refusal that needs an
	// operator (re-registration, a revoked runner, an update). systemd does not
	// restart it.
	ExitStop = 3
)

// Runner runs a system command.
type Runner interface {
	Run(ctx context.Context, name string, args ...string) error
}

// ExecRunner runs commands for real.
type ExecRunner struct{}

// Run runs the command and returns its output in the error when it fails.
func (ExecRunner) Run(ctx context.Context, name string, args ...string) error {
	out, err := exec.CommandContext(ctx, name, args...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s %s: %v: %s", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return nil
}

// Manager installs and drives the unit.
type Manager struct {
	Runner Runner
	// UnitDir is where the unit file goes, /etc/systemd/system.
	UnitDir string
	// Binary is the absolute path of the aixle-runner binary the unit runs.
	Binary string
	// StateDir is the runner's state directory, which the service user owns.
	StateDir string
	// LookupUser and Chown are replaced in tests.
	LookupUser func(name string) (*user.User, error)
	Chown      func(path string, uid, gid int) error
	Geteuid    func() int
}

// NewManager returns a manager of the real system.
func NewManager(binary, stateDir string) *Manager {
	return &Manager{
		Runner:     ExecRunner{},
		UnitDir:    "/etc/systemd/system",
		Binary:     binary,
		StateDir:   stateDir,
		LookupUser: user.Lookup,
		Chown:      os.Lchown,
		Geteuid:    os.Geteuid,
	}
}

func (m *Manager) unitPath() string { return filepath.Join(m.UnitDir, UnitName) }

func (m *Manager) requireRoot() error {
	if m.Geteuid() != 0 {
		return errors.New("this command manages a system service: run it as root (sudo)")
	}
	return nil
}

// Install creates the service user, adds it to the docker group, hands it the
// state directory and installs and enables the unit. Running it again updates the
// unit and leaves the rest as it is.
func (m *Manager) Install(ctx context.Context) error {
	if err := m.requireRoot(); err != nil {
		return err
	}
	if !filepath.IsAbs(m.Binary) {
		return fmt.Errorf("the binary path %q is not absolute", m.Binary)
	}
	if _, err := m.LookupUser(User); err != nil {
		var unknown user.UnknownUserError
		if !errors.As(err, &unknown) {
			return fmt.Errorf("looking up the user %s: %w", User, err)
		}
		if err := m.Runner.Run(ctx, "useradd", "--system", "--user-group",
			"--home-dir", m.StateDir, "--no-create-home", "--shell", "/usr/sbin/nologin", User); err != nil {
			return fmt.Errorf("creating the system user %s: %w", User, err)
		}
	}
	if err := m.Runner.Run(ctx, "usermod", "--append", "--groups", DockerGroup, User); err != nil {
		return fmt.Errorf("adding %s to the %s group (is Docker installed?): %w", User, DockerGroup, err)
	}
	if err := m.ownStateDir(); err != nil {
		return err
	}

	unit, err := m.Unit()
	if err != nil {
		return err
	}
	if err := fsutil.WriteFileAtomic(m.unitPath(), unit, 0o644); err != nil {
		return err
	}
	if err := m.Runner.Run(ctx, "systemctl", "daemon-reload"); err != nil {
		return err
	}
	return m.Runner.Run(ctx, "systemctl", "enable", UnitName)
}

// ownStateDir gives the state directory and everything in it to the service user,
// so the credentials stay readable only by the runner's own user (§6.3).
func (m *Manager) ownStateDir() error {
	u, err := m.LookupUser(User)
	if err != nil {
		return fmt.Errorf("looking up the user %s: %w", User, err)
	}
	uid, err := strconv.Atoi(u.Uid)
	if err != nil {
		return fmt.Errorf("the uid of %s is %q", User, u.Uid)
	}
	gid, err := strconv.Atoi(u.Gid)
	if err != nil {
		return fmt.Errorf("the gid of %s is %q", User, u.Gid)
	}
	if err := os.MkdirAll(m.StateDir, 0o700); err != nil {
		return fmt.Errorf("creating %s: %w", m.StateDir, err)
	}
	if err := os.Chmod(m.StateDir, 0o700); err != nil {
		return fmt.Errorf("restricting %s: %w", m.StateDir, err)
	}
	return filepath.WalkDir(m.StateDir, func(path string, _ fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if err := m.Chown(path, uid, gid); err != nil {
			return fmt.Errorf("handing %s to %s: %w", path, User, err)
		}
		return nil
	})
}

// Uninstall stops, disables and removes the unit. The user, the credentials and
// the journal stay, so `install` brings the same machine back; `unregister`
// removes the machine itself.
func (m *Manager) Uninstall(ctx context.Context) error {
	if err := m.requireRoot(); err != nil {
		return err
	}
	if _, err := os.Stat(m.unitPath()); errors.Is(err, fs.ErrNotExist) {
		return fmt.Errorf("the service is not installed (%s does not exist)", m.unitPath())
	}
	if err := m.Runner.Run(ctx, "systemctl", "disable", "--now", UnitName); err != nil {
		return err
	}
	if err := os.Remove(m.unitPath()); err != nil {
		return fmt.Errorf("removing %s: %w", m.unitPath(), err)
	}
	return m.Runner.Run(ctx, "systemctl", "daemon-reload")
}

// Start starts the service.
func (m *Manager) Start(ctx context.Context) error {
	if err := m.requireRoot(); err != nil {
		return err
	}
	return m.Runner.Run(ctx, "systemctl", "start", UnitName)
}

// Stop stops the service.
func (m *Manager) Stop(ctx context.Context) error {
	if err := m.requireRoot(); err != nil {
		return err
	}
	return m.Runner.Run(ctx, "systemctl", "stop", UnitName)
}

// Unit renders the unit file.
func (m *Manager) Unit() ([]byte, error) {
	for _, p := range []string{m.Binary, m.StateDir} {
		if strings.ContainsAny(p, " \t\n\"'\\%$") {
			return nil, fmt.Errorf("the path %q cannot be written into a systemd unit", p)
		}
	}
	var buf bytes.Buffer
	err := unitTemplate.Execute(&buf, map[string]any{
		"Binary":   m.Binary,
		"StateDir": m.StateDir,
		"User":     User,
		"Group":    DockerGroup,
		"ExitStop": ExitStop,
	})
	return buf.Bytes(), err
}

var unitTemplate = template.Must(template.New("unit").Parse(`# Installed by ` + "`aixle-runner service install`" + `. Remove it with ` + "`aixle-runner service uninstall`" + `.
[Unit]
Description=Aixle runner (host mode)
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
User={{.User}}
Group={{.User}}
SupplementaryGroups={{.Group}}
ExecStart={{.Binary}} --mode host --state-dir {{.StateDir}}
Restart=on-failure
RestartSec=5
# Exit {{.ExitStop}}: a refusal that needs an operator (re-registration, a revoked
# runner, an update). Restarting cannot fix it.
RestartPreventExitStatus={{.ExitStop}}
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
`))
