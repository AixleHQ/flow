package version

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// The strict Semantic Versioning 2.0 grammar (https://semver.org), the one the
// gateway requires in X-Aixle-Runner-Version (PROTOCOL.md §1).
var semverPattern = regexp.MustCompile(`^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$`)

// SemVer is a parsed version. Build metadata is dropped: it does not take part in
// the order.
type SemVer struct {
	Major, Minor, Patch uint64
	Pre                 []string
}

// Parse reads a strict SemVer 2.0 version, without a `v` prefix.
func Parse(s string) (SemVer, error) {
	m := semverPattern.FindStringSubmatch(s)
	if m == nil {
		return SemVer{}, fmt.Errorf("%q is not a semantic version", s)
	}
	var v SemVer
	var err error
	if v.Major, err = strconv.ParseUint(m[1], 10, 64); err != nil {
		return SemVer{}, fmt.Errorf("%q: %w", s, err)
	}
	if v.Minor, err = strconv.ParseUint(m[2], 10, 64); err != nil {
		return SemVer{}, fmt.Errorf("%q: %w", s, err)
	}
	if v.Patch, err = strconv.ParseUint(m[3], 10, 64); err != nil {
		return SemVer{}, fmt.Errorf("%q: %w", s, err)
	}
	if m[4] != "" {
		v.Pre = strings.Split(m[4], ".")
	}
	return v, nil
}

// Compare orders a and b by SemVer 2.0 precedence: -1, 0 or 1.
func Compare(a, b SemVer) int {
	for _, d := range [][2]uint64{{a.Major, b.Major}, {a.Minor, b.Minor}, {a.Patch, b.Patch}} {
		if d[0] != d[1] {
			if d[0] < d[1] {
				return -1
			}
			return 1
		}
	}
	// A version without a pre-release ranks above the same version with one.
	switch {
	case len(a.Pre) == 0 && len(b.Pre) == 0:
		return 0
	case len(a.Pre) == 0:
		return 1
	case len(b.Pre) == 0:
		return -1
	}
	for i := 0; i < len(a.Pre) && i < len(b.Pre); i++ {
		if c := compareIdentifier(a.Pre[i], b.Pre[i]); c != 0 {
			return c
		}
	}
	switch {
	case len(a.Pre) < len(b.Pre):
		return -1
	case len(a.Pre) > len(b.Pre):
		return 1
	}
	return 0
}

// compareIdentifier orders two pre-release identifiers: numeric ones by value,
// below every alphanumeric one, and alphanumeric ones in ASCII order.
func compareIdentifier(a, b string) int {
	an, aErr := strconv.ParseUint(a, 10, 64)
	bn, bErr := strconv.ParseUint(b, 10, 64)
	switch {
	case aErr == nil && bErr == nil:
		switch {
		case an < bn:
			return -1
		case an > bn:
			return 1
		}
		return 0
	case aErr == nil:
		return -1
	case bErr == nil:
		return 1
	}
	return strings.Compare(a, b)
}

// Newer says whether candidate ranks above current. Either one not being a
// semantic version is an error.
func Newer(candidate, current string) (bool, error) {
	c, err := Parse(candidate)
	if err != nil {
		return false, err
	}
	cur, err := Parse(current)
	if err != nil {
		return false, err
	}
	return Compare(c, cur) > 0, nil
}
