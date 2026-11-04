// Package service is `aixle-runner service install | uninstall | start | stop`: a
// systemd unit that runs `/usr/local/bin/aixle-runner --mode host` as the dedicated
// `aixle-runner` system user, in the `docker` group (DESIGN.md §6.3, §9.7).
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
	// BinaryPath is the binary the unit runs. `install` copies the running binary
	// there, owned by root, so a user who can write the file `install` ran from
	// cannot replace what the service runs (§9.7).
	BinaryPath = "/usr/local/bin/aixle-runner"
)

// Account is the service user's uid and gid.
type Account struct{ UID, GID int }

// LookupAccount looks up the service user with lookup. A user that does not exist
// yet is not an error: it returns ok false. Any other failure of the lookup, and
// a uid or gid that is not a number, is an error.
func LookupAccount(lookup func(name string) (*user.User, error)) (acct Account, ok bool, err error) {
	u, err := lookup(User)
	if err != nil {
		var unknown user.UnknownUserError
		if errors.As(err, &unknown) {
			return Account{}, false, nil
		}
		return Account{}, false, fmt.Errorf("looking up the user %s: %w", User, err)
	}
	if acct.UID, err = strconv.Atoi(u.Uid); err != nil || acct.UID < 0 {
		return Account{}, false, fmt.Errorf("the uid of %s is %q, not a number", User, u.Uid)
	}
	if acct.GID, err = strconv.Atoi(u.Gid); err != nil || acct.GID < 0 {
		return Account{}, false, fmt.Errorf("the gid of %s is %q, not a number", User, u.Gid)
	}
	return acct, true, nil
}

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
	// Source is the absolute path of the running aixle-runner binary, which
	// `install` copies to Binary.
	Source string
	// Binary is the binary the unit runs, BinaryPath.
	Binary string
	// StateDir is the runner's state directory, which the service user owns.
	StateDir string
	// LookupUser and Chown are replaced in tests.
	LookupUser func(name string) (*user.User, error)
	Chown      func(path string, uid, gid int) error
	Geteuid    func() int
}

// NewManager returns a manager of the real system. source is the running binary.
func NewManager(source, stateDir string) *Manager {
	return &Manager{
		Runner:     ExecRunner{},
		UnitDir:    "/etc/systemd/system",
		Source:     source,
		Binary:     BinaryPath,
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

// Install copies the running binary to Binary, creates the service user, adds it
// to the docker group, hands it the state directory and installs and enables the
// unit. Running it again updates the binary and the unit and leaves the rest as it
// is.
func (m *Manager) Install(ctx context.Context) error {
	if err := m.requireRoot(); err != nil {
		return err
	}
	for _, p := range []string{m.Source, m.Binary} {
		if !filepath.IsAbs(p) {
			return fmt.Errorf("the binary path %q is not absolute", p)
		}
	}
	if err := m.installBinary(); err != nil {
		return err
	}
	if _, exists, err := LookupAccount(m.LookupUser); err != nil {
		return err
	} else if !exists {
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
	acct, exists, err := LookupAccount(m.LookupUser)
	if err != nil {
		return err
	}
	if !exists {
		return fmt.Errorf("the user %s does not exist after it was created", User)
	}
	uid, gid := acct.UID, acct.GID
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

// installBinary copies Source to Binary atomically, owned by root with mode 0755,
// unless the running binary is Binary already.
func (m *Manager) installBinary() error {
	same, err := sameFile(m.Source, m.Binary)
	if err != nil {
		return err
	}
	if same {
		return nil
	}
	err = fsutil.CopyFileAtomic(m.Source, m.Binary, 0o755, func(name string) error {
		return m.Chown(name, 0, 0)
	})
	if err != nil {
		return fmt.Errorf("installing the binary the service runs: %w", err)
	}
	return nil
}

// sameFile says whether a and b are the same file. A missing b is not.
func sameFile(a, b string) (bool, error) {
	bi, err := os.Stat(b)
	if errors.Is(err, fs.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("checking %s: %w", b, err)
	}
	ai, err := os.Stat(a)
	if err != nil {
		return false, fmt.Errorf("checking %s: %w", a, err)
	}
	return os.SameFile(ai, bi), nil
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
