package service

import (
	"context"
	"errors"
	"os"
	"os/user"
	"path/filepath"
	"strings"
	"testing"
	"time"
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
		Source:   filepath.Join(root, "home", "aixle-runner"),
		Binary:   filepath.Join(root, "bin", "aixle-runner"),
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
	_ = os.MkdirAll(filepath.Dir(m.Source), 0o755)
	_ = os.WriteFile(m.Source, []byte("the runner"), 0o755)
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

	// The binary belongs to root, and the state directory and the credentials to
	// the service user.
	if len(*chowns) != 3 || (*chowns)[0].uid != 0 || (*chowns)[0].gid != 0 ||
		(*chowns)[1].uid != 998 || (*chowns)[2].path != filepath.Join(m.StateDir, "credentials") {
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
		"ExecStart=" + m.Binary + " --mode host --state-dir " + m.StateDir,
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

func TestNewManagerRunsTheFixedPathWhereverTheBinaryRunsFrom(t *testing.T) {
	m := NewManager("/home/ec2-user/aixle-runner", "/var/lib/aixle-runner")
	if m.Binary != BinaryPath || BinaryPath != "/usr/local/bin/aixle-runner" {
		t.Fatalf("binary %s", m.Binary)
	}
	unit, err := m.Unit()
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(unit), "ExecStart=/usr/local/bin/aixle-runner --mode host --state-dir /var/lib/aixle-runner\n") ||
		strings.Contains(string(unit), "/home/ec2-user") {
		t.Fatalf("unit:\n%s", unit)
	}
}

func TestInstallCopiesTheRunningBinaryForRoot(t *testing.T) {
	m, _, chowns := manager(t, true)
	if err := m.Install(context.Background()); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(m.Binary)
	if err != nil || string(got) != "the runner" {
		t.Fatalf("copied %q, %v", got, err)
	}
	info, _ := os.Lstat(m.Binary)
	if !info.Mode().IsRegular() || info.Mode().Perm() != 0o755 {
		t.Fatalf("mode %v", info.Mode())
	}
	// The copy is given to root before it appears at its path.
	c := (*chowns)[0]
	if c.uid != 0 || c.gid != 0 || filepath.Dir(c.path) != filepath.Dir(m.Binary) || c.path == m.Binary {
		t.Fatalf("chowns %v", *chowns)
	}

	// The source the user can write is replaced: the service keeps its own copy.
	if err := os.WriteFile(m.Source, []byte("something else"), 0o755); err != nil {
		t.Fatal(err)
	}
	if got, _ := os.ReadFile(m.Binary); string(got) != "the runner" {
		t.Fatalf("the installed binary changed to %q", got)
	}
}

func TestInstallFromTheFixedPathCopiesNothing(t *testing.T) {
	m, _, chowns := manager(t, true)
	if err := os.MkdirAll(filepath.Dir(m.Binary), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(m.Binary, []byte("installed"), 0o755); err != nil {
		t.Fatal(err)
	}
	old := time.Now().Add(-time.Hour).Truncate(time.Second)
	if err := os.Chtimes(m.Binary, old, old); err != nil {
		t.Fatal(err)
	}
	m.Source = m.Binary
	if err := m.Install(context.Background()); err != nil {
		t.Fatal(err)
	}
	info, _ := os.Stat(m.Binary)
	got, _ := os.ReadFile(m.Binary)
	if string(got) != "installed" || !info.ModTime().Equal(old) {
		t.Fatalf("the binary was rewritten: %q at %v", got, info.ModTime())
	}
	for _, c := range *chowns {
		if filepath.Dir(c.path) == filepath.Dir(m.Binary) {
			t.Fatalf("chowned %s", c.path)
		}
	}
	unit, _ := os.ReadFile(filepath.Join(m.UnitDir, UnitName))
	if !strings.Contains(string(unit), "ExecStart="+m.Binary+" ") {
		t.Fatalf("unit:\n%s", unit)
	}
}

func TestInstallStopsWhenTheUserCannotBeLookedUp(t *testing.T) {
	m, rec, _ := manager(t, true)
	m.LookupUser = func(string) (*user.User, error) { return nil, errors.New("nss: connection refused") }
	err := m.Install(context.Background())
	if err == nil || !strings.Contains(err.Error(), "looking up the user") {
		t.Fatalf("got %v", err)
	}
	for _, c := range rec.commands {
		if strings.HasPrefix(c, "useradd") {
			t.Fatal("useradd ran after a failed lookup")
		}
	}
}

func TestLookupAccount(t *testing.T) {
	found := func(uid, gid string) func(string) (*user.User, error) {
		return func(string) (*user.User, error) { return &user.User{Uid: uid, Gid: gid}, nil }
	}
	if acct, ok, err := LookupAccount(found("998", "997")); err != nil || !ok || acct != (Account{998, 997}) {
		t.Fatalf("got %v %v %v", acct, ok, err)
	}
	if _, ok, err := LookupAccount(func(n string) (*user.User, error) { return nil, user.UnknownUserError(n) }); err != nil || ok {
		t.Fatalf("an unknown user: %v %v", ok, err)
	}
	for name, lookup := range map[string]func(string) (*user.User, error){
		"lookup": func(string) (*user.User, error) { return nil, errors.New("nss: connection refused") },
		"uid":    found("x", "997"),
		"gid":    found("998", ""),
		"-1":     found("-1", "997"),
	} {
		if _, ok, err := LookupAccount(lookup); err == nil || ok {
			t.Errorf("%s: got %v %v", name, ok, err)
		}
	}
}
