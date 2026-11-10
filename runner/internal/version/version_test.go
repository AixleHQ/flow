package version

import (
	"testing"
)

func TestALocalBuildReportsAValidVersion(t *testing.T) {
	if _, err := Parse(Version); err != nil {
		t.Fatal(err)
	}
}

func TestParseTakesStrictSemVerOnly(t *testing.T) {
	for _, ok := range []string{"0.1.0", "1.4.0", "1.5.0-rc.1+build.7", "0.0.0-dev", "10.20.30"} {
		if _, err := Parse(ok); err != nil {
			t.Errorf("%s: %v", ok, err)
		}
	}
	for _, bad := range []string{"", "1.4", "v1.4.0", "01.2.3", "1.2.3-01", "1.2.3-..", "1.2.3-", "1.2.3+", "latest"} {
		if _, err := Parse(bad); err == nil {
			t.Errorf("%q parsed", bad)
		}
	}
}

func TestCompareFollowsSemVerPrecedence(t *testing.T) {
	// semver.org §11, in ascending order.
	ordered := []string{
		"0.0.0-dev", "0.1.0", "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta",
		"1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "1.0.1", "1.1.0", "2.0.0",
	}
	for i := range ordered {
		for k := range ordered {
			a, _ := Parse(ordered[i])
			b, _ := Parse(ordered[k])
			want := 0
			switch {
			case i < k:
				want = -1
			case i > k:
				want = 1
			}
			if got := Compare(a, b); got != want {
				t.Errorf("Compare(%s, %s) = %d, want %d", ordered[i], ordered[k], got, want)
			}
		}
	}
	a, _ := Parse("1.4.0+build.1")
	b, _ := Parse("1.4.0+build.2")
	if Compare(a, b) != 0 {
		t.Error("build metadata takes part in the order")
	}
}

func TestNewer(t *testing.T) {
	if ok, err := Newer("1.5.0", "1.4.0"); err != nil || !ok {
		t.Fatalf("1.5.0 over 1.4.0: %v %v", ok, err)
	}
	if ok, err := Newer("1.4.0", "1.4.0"); err != nil || ok {
		t.Fatalf("1.4.0 over 1.4.0: %v %v", ok, err)
	}
	if ok, err := Newer("1.3.0", "1.4.0"); err != nil || ok {
		t.Fatalf("1.3.0 over 1.4.0: %v %v", ok, err)
	}
	if _, err := Newer("latest", "1.4.0"); err == nil {
		t.Fatal("accepted latest")
	}
}
