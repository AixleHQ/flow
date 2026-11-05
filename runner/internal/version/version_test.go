package version

import (
	"regexp"
	"testing"
)

// Strict SemVer 2.0, which the gateway's grammar always accepts (PROTOCOL.md §1).
var semver = regexp.MustCompile(`^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$`)

func TestALocalBuildReportsAValidVersion(t *testing.T) {
	if !semver.MatchString(Version) {
		t.Fatalf("%q is not a semantic version", Version)
	}
}
