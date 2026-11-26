package main

import (
	"os"
	"reflect"
	"strings"
	"testing"
)

// The published image is as docs/design/agent-runtimes/add-machine.md §3.1 says:
// the runner is the entrypoint, with no shell script, and the two things that differ
// in a container are set explicitly by the image.
func TestThePublishedImageIsAsTheDesignSaysIt(t *testing.T) {
	raw, err := os.ReadFile("../../../docker/runner/Dockerfile")
	if err != nil {
		t.Fatal(err)
	}
	var instructions [][]string
	for _, line := range strings.Split(string(raw), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		instructions = append(instructions, strings.Fields(line))
	}
	find := func(keyword string) [][]string {
		var found [][]string
		for _, fields := range instructions {
			if strings.EqualFold(fields[0], keyword) {
				found = append(found, fields[1:])
			}
		}
		return found
	}

	entrypoint := strings.Join(find("ENTRYPOINT")[0], " ")
	if entrypoint != `["aixle-runner"]` {
		t.Errorf("ENTRYPOINT %s", entrypoint)
	}
	cmd := strings.Join(find("CMD")[0], " ")
	if cmd != `["--mode", "machine", "--state-dir", "/var/lib/aixle-runner"]` {
		t.Errorf("CMD %s", cmd)
	}
	if volumes := find("VOLUME"); !reflect.DeepEqual(volumes, [][]string{{"/var/lib/aixle-runner"}}) {
		t.Errorf("VOLUME %v", volumes)
	}
	env := map[string]bool{}
	for _, fields := range find("ENV") {
		env[strings.Join(fields, " ")] = true
	}
	for _, want := range []string{"AIXLE_RUNNER_IN_CONTAINER=1", "AIXLE_RUNNER_UNREGISTER_ON_STOP=1", "AIXLE_RUNNER_NO_SELF_UPDATE=1"} {
		if !env[want] {
			t.Errorf("ENV lacks %s: %v", want, env)
		}
	}
	for name := range env {
		if strings.HasPrefix(name, "AIXLE_RUNNER_DIR") {
			t.Errorf("ENV %s: the image has no AIXLE_RUNNER_DIR", name)
		}
	}
	// No shell entrypoint: nothing of the image's setup runs in sh.
	for _, fields := range instructions {
		line := strings.Join(fields, " ")
		if strings.Contains(line, "aixle-runner-entrypoint") || strings.Contains(line, "/bin/sh") || (strings.EqualFold(fields[0], "COPY") && strings.Contains(line, "<<")) {
			t.Errorf("the image has a shell script: %s", line)
		}
	}
	if user := find("USER"); len(user) != 0 {
		t.Errorf("USER %v: the image runs as root by default; the controller sets non-root in its pod spec", user)
	}
}
