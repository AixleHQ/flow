package service

import (
	"context"
	"errors"
	"os"
	"os/user"
	"path/filepath"
	"strings"
	"testing"
)

type recorder struct {
	commands []string
	fail     string
}

func (r *recorder) Run(_ context.Context, name string, args ...string) error {
	cmd := strings.Join(append([]string{name}, args...), " ")
	r.commands = append(r.commands, cmd)
	if r.fail != "" && strings.HasPrefix(cmd, r.fail) {
		return errors.New("failed")
	}
	return nil
}

type chown struct {
	path     string
	uid, gid int
}

func manager(t *testing.T, userExists bool) (*Manager, *recorder, *[]chown) {
	t.Helper()
	root := t.TempDir()
	rec := &recorder{}
	chowns := &[]chown{}
	created := userExists
	m := &Manager{
		Runner:   rec,
		UnitDir:  filepath.Join(root, "systemd"),
		Binary:   "/usr/local/bin/aixle-runner",
		StateDir: filepath.Join(root, "state"),
		LookupUser: func(name string) (*user.User, error) {
			if name != User {
				t.Fatalf("looked up %s", name)
			}
			if !created {
				// useradd creates it.
				for _, c := range rec.commands {
					if strings.HasPrefix(c, "useradd") {
						created = true
					}
				}
				if !created {
					return nil, user.UnknownUserError(name)
				}
			}
			return &user.User{Username: User, Uid: "998", Gid: "997"}, nil
		},
		Chown: func(path string, uid, gid int) error {
			*chowns = append(*chowns, chown{path, uid, gid})
			return nil
		},
		Geteuid: func() int { return 0 },
	}
	_ = os.MkdirAll(m.StateDir, 0o755)
	_ = os.WriteFile(filepath.Join(m.StateDir, "credentials"), []byte("{}"), 0o600)
	return m, rec, chowns
}

func TestInstallCreatesTheUserAndTheUnit(t *testing.T) {
	m, rec, chowns := manager(t, false)
	if err := m.Install(context.Background()); err != nil {
		t.Fatal(err)
	}
	want := []string{
		"useradd --system --user-group --home-dir " + m.StateDir + " --no-create-home --shell /usr/sbin/nologin aixle-runner",
		"usermod --append --groups docker aixle-runner",
		"systemctl daemon-reload",
		"systemctl enable aixle-runner.service",
	}
	if strings.Join(rec.commands, "\n") != strings.Join(want, "\n") {
		t.Fatalf("commands:\n%s\nwant:\n%s", strings.Join(rec.commands, "\n"), strings.Join(want, "\n"))
	}

	// The state directory and the credentials belong to the service user.
	if len(*chowns) != 2 || (*chowns)[0].uid != 998 || (*chowns)[1].path != filepath.Join(m.StateDir, "credentials") {
		t.Fatalf("chowns %v", *chowns)
	}
	info, _ := os.Stat(m.StateDir)
	if info.Mode().Perm() != 0o700 {
		t.Fatalf("state dir mode %v", info.Mode().Perm())
	}

	unit, err := os.ReadFile(filepath.Join(m.UnitDir, UnitName))
	if err != nil {
		t.Fatal(err)
	}
	for _, line := range []string{
		"User=aixle-runner",
		"SupplementaryGroups=docker",
		"ExecStart=/usr/local/bin/aixle-runner --mode host --state-dir " + m.StateDir,
		"Restart=on-failure",
		"RestartPreventExitStatus=3",
		"WantedBy=multi-user.target",
	} {
		if !strings.Contains(string(unit), line+"\n") {
			t.Errorf("the unit lacks %q:\n%s", line, unit)
		}
	}
}

func TestInstallKeepsAnExistingUser(t *testing.T) {
	m, rec, _ := manager(t, true)
	if err := m.Install(context.Background()); err != nil {
		t.Fatal(err)
	}
	for _, c := range rec.commands {
		if strings.HasPrefix(c, "useradd") {
			t.Fatal("useradd ran for an existing user")
		}
	}
}

func TestInstallWithoutADockerGroupFails(t *testing.T) {
	m, rec, _ := manager(t, true)
	rec.fail = "usermod"
	err := m.Install(context.Background())
	if err == nil || !strings.Contains(err.Error(), "docker group") {
		t.Fatalf("got %v", err)
	}
	if _, err := os.Stat(filepath.Join(m.UnitDir, UnitName)); err == nil {
		t.Fatal("a unit was installed")
	}
}

func TestEveryCommandNeedsRoot(t *testing.T) {
	m, rec, _ := manager(t, true)
	m.Geteuid = func() int { return 1000 }
	for name, f := range map[string]func(context.Context) error{"install": m.Install, "uninstall": m.Uninstall, "start": m.Start, "stop": m.Stop} {
		if err := f(context.Background()); err == nil || !strings.Contains(err.Error(), "root") {
			t.Errorf("%s: got %v", name, err)
		}
	}
	if len(rec.commands) != 0 {
		t.Fatalf("ran %v", rec.commands)
	}
}

func TestUninstallStartStop(t *testing.T) {
	m, rec, _ := manager(t, true)
	if err := m.Uninstall(context.Background()); err == nil {
		t.Fatal("uninstalled a service that is not installed")
	}
	if err := m.Install(context.Background()); err != nil {
		t.Fatal(err)
	}
	rec.commands = nil
	_ = m.Start(context.Background())
	_ = m.Stop(context.Background())
	if err := m.Uninstall(context.Background()); err != nil {
		t.Fatal(err)
	}
	want := "systemctl start aixle-runner.service\nsystemctl stop aixle-runner.service\nsystemctl disable --now aixle-runner.service\nsystemctl daemon-reload"
	if strings.Join(rec.commands, "\n") != want {
		t.Fatalf("commands:\n%s", strings.Join(rec.commands, "\n"))
	}
	if _, err := os.Stat(filepath.Join(m.UnitDir, UnitName)); err == nil {
		t.Fatal("the unit is still there")
	}
	// The credentials stay: unregister removes the machine.
	if _, err := os.Stat(filepath.Join(m.StateDir, "credentials")); err != nil {
		t.Fatal("uninstall removed the credentials")
	}
}

func TestAPathTheUnitCannotQuoteIsRefused(t *testing.T) {
	m, _, _ := manager(t, true)
	m.Binary = "/opt/my runner/aixle-runner"
	if _, err := m.Unit(); err == nil {
		t.Fatal("accepted a path with a space")
	}
}
