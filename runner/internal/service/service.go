// Package service is `aixle-runner service install | uninstall | start | stop`: a
// systemd unit that runs `aixle-runner --mode host` as the dedicated
// `aixle-runner` system user, in the `docker` group (DESIGN.md §6.3, §9.7), from a
// directory that user owns, so the runner can update itself (§14.4).
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
	"syscall"
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
	// ExitUpdated is the exit code of a host runner that replaced its binary with
	// a newer one. systemd restarts it on the new binary, and so does a supervisor
	// that restarts only on a failure, such as the `local` adapter's Compose
	// service.
	ExitUpdated = 4
	// BinaryPath is the binary the unit runs: `bin/aixle-runner` in the state
	// directory. `install` copies the running binary there, owned by the service
	// user, in a directory that user owns, the way the GitHub Actions runner lives
	// in its own user's directory: a self-update replaces it in place, with no
	// root helper. Whoever runs as that user is root-equivalent anyway, through
	// the docker group (§9.7). A user who can write the file `install` ran from
	// still cannot replace what the service runs.
	BinaryPath = "/var/lib/aixle-runner/bin/aixle-runner"
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
	// Binary is the binary the unit runs, BinaryPath. Its directory is the service
	// user's.
	Binary string
	// StateDir is the runner's state directory, which the service user owns.
	StateDir string
	// OpenSelf opens the running binary, /proc/self/exe. `install` decides and
	// copies from that one descriptor, so what it installs is what is running,
	// whatever happens to the path it was started from.
	OpenSelf func() (*os.File, error)
	// LookupUser, Chown, Owner and Geteuid are replaced in tests. Owner is the uid
	// that owns a file, or -1 when the platform does not say.
	LookupUser func(name string) (*user.User, error)
	Chown      func(path string, uid, gid int) error
	Owner      func(info fs.FileInfo) int
	Geteuid    func() int
}

// NewManager returns a manager of the real system.
func NewManager(stateDir string) *Manager {
	return &Manager{
		Runner:     ExecRunner{},
		UnitDir:    "/etc/systemd/system",
		OpenSelf:   func() (*os.File, error) { return os.Open("/proc/self/exe") },
		Binary:     BinaryPath,
		StateDir:   stateDir,
		LookupUser: user.Lookup,
		Chown:      os.Lchown,
		Owner:      fileOwner,
		Geteuid:    os.Geteuid,
	}
}

// fileOwner is the uid in info's stat data, or -1.
func fileOwner(info fs.FileInfo) int {
	if st, ok := info.Sys().(*syscall.Stat_t); ok {
		return int(st.Uid)
	}
	return -1
}

func (m *Manager) unitPath() string { return filepath.Join(m.UnitDir, UnitName) }

func (m *Manager) requireRoot() error {
	if m.Geteuid() != 0 {
		return errors.New("this command manages a system service: run it as root (sudo)")
	}
	return nil
}

// Install creates the service user, adds it to the docker group, hands it the
// state directory and the binary's directory, copies the running binary to
// Binary, owned by that user, and installs and enables the unit. Running it again
// updates the binary and the unit and leaves the rest as it is.
func (m *Manager) Install(ctx context.Context) error {
	if err := m.requireRoot(); err != nil {
		return err
	}
	if !filepath.IsAbs(m.Binary) {
		return fmt.Errorf("the binary path %q is not absolute", m.Binary)
	}
	// The running binary is opened first, and both decided on and copied from that
	// one descriptor, so a user who can write the path `install` was started from
	// cannot swap in other bytes meanwhile.
	self, err := m.OpenSelf()
	if err != nil {
		return fmt.Errorf("opening the running binary: %w", err)
	}
	defer self.Close()

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
	acct, err := m.ownDirectories()
	if err != nil {
		return err
	}
	if err := m.installBinary(self, acct); err != nil {
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

// ownDirectories gives the state directory and everything in it to the service
// user, so the credentials stay readable only by the runner's own user (§6.3), and
// creates the binary's directory and gives it to that user too, so a self-update
// can put the new binary next to the old one and rename it over (§14.4).
func (m *Manager) ownDirectories() (Account, error) {
	acct, exists, err := LookupAccount(m.LookupUser)
	if err != nil {
		return Account{}, err
	}
	if !exists {
		return Account{}, fmt.Errorf("the user %s does not exist after it was created", User)
	}
	if err := os.MkdirAll(m.StateDir, 0o700); err != nil {
		return Account{}, fmt.Errorf("creating %s: %w", m.StateDir, err)
	}
	if err := os.Chmod(m.StateDir, 0o700); err != nil {
		return Account{}, fmt.Errorf("restricting %s: %w", m.StateDir, err)
	}
	binDir := filepath.Dir(m.Binary)
	if err := os.MkdirAll(binDir, 0o755); err != nil {
		return Account{}, fmt.Errorf("creating %s: %w", binDir, err)
	}
	own := func(path string, _ fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if err := m.Chown(path, acct.UID, acct.GID); err != nil {
			return fmt.Errorf("handing %s to %s: %w", path, User, err)
		}
		return nil
	}
	if err := filepath.WalkDir(m.StateDir, own); err != nil {
		return Account{}, err
	}
	if !within(binDir, m.StateDir) {
		if err := own(binDir, nil, nil); err != nil {
			return Account{}, err
		}
	}
	return acct, nil
}

func within(path, dir string) bool {
	rel, err := filepath.Rel(dir, path)
	return err == nil && rel != ".." && !strings.HasPrefix(rel, "../")
}

// installBinary copies self to Binary atomically, owned by the service user with
// mode 0755, unless Binary is that already. The copy is given to the user before
// it appears at its path. The rename replaces whatever is at Binary, a symlink
// included, not its target.
func (m *Manager) installBinary(self *os.File, acct Account) error {
	selfInfo, err := self.Stat()
	if err != nil {
		return fmt.Errorf("checking the running binary: %w", err)
	}
	installed, err := m.isInstalled(selfInfo, acct)
	if err != nil {
		return err
	}
	if installed {
		return nil
	}
	err = fsutil.CopyFileAtomic(self, m.Binary, 0o755, func(name string) error {
		return m.Chown(name, acct.UID, acct.GID)
	})
	if err != nil {
		return fmt.Errorf("installing the binary the service runs: %w", err)
	}
	return nil
}

// isInstalled says whether Binary already is what installBinary would make of
// self: the same regular file, not through a link, owned by the service user,
// with mode exactly 0755. Anything else is copied over. A missing Binary is not
// installed.
func (m *Manager) isInstalled(self fs.FileInfo, acct Account) (bool, error) {
	info, err := os.Lstat(m.Binary)
	if errors.Is(err, fs.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("checking %s: %w", m.Binary, err)
	}
	return info.Mode().IsRegular() &&
		os.SameFile(self, info) &&
		m.Owner(info) == acct.UID &&
		info.Mode().Perm() == 0o755, nil
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
		"Binary":      m.Binary,
		"StateDir":    m.StateDir,
		"User":        User,
		"Group":       DockerGroup,
		"ExitStop":    ExitStop,
		"ExitUpdated": ExitUpdated,
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
# Always: a self-update replaces the binary and exits ({{.ExitUpdated}}), and the
# restart runs the new one.
Restart=always
RestartSec=5
# Exit {{.ExitStop}}: a refusal that needs an operator (re-registration, a revoked
# runner, an update). Restarting cannot fix it.
RestartPreventExitStatus={{.ExitStop}}
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
`))
