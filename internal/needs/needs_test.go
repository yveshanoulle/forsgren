package needs

import (
	"reflect"
	"strings"
	"testing"
)

// TestForReturnsTheNeedsAppliedFromTheirVersionOn (forsgren#73): a need
// introduced in 0.3.8 applies to 0.3.8 and every later version, and to none
// before it; versions compare as numbers, so 0.3.10 is later than 0.3.8.
func TestForReturnsTheNeedsAppliedFromTheirVersionOn(t *testing.T) {
	issuesWrite := Need{
		Version:    "0.3.8",
		Kind:       "permission",
		Workflow:   ".github/workflows/forsgren.yml",
		Permission: "issues",
		Access:     "write",
		Steps: "Add `issues: write` to the `permissions:` of the job in " +
			".github/workflows/forsgren.yml, so forsgren can open its setup issue.",
	}
	cases := []struct {
		version string
		want    []Need
	}{
		{"0.3.7", nil},
		{"0.3.8", []Need{issuesWrite}},
		{"0.3.10", []Need{issuesWrite}},
		{"0.4.0", []Need{issuesWrite}},
	}
	for _, c := range cases {
		got, err := For(c.version)
		if err != nil || !reflect.DeepEqual(got, c.want) {
			t.Errorf("For(%q): want %v and no error, got %v, %v", c.version, c.want, got, err)
		}
	}
}

// TestForRefusesWhatItCannotRead (forsgren#73): a running version or a
// declared one that is not three dot-separated numbers, and declarations that
// are not YAML, are errors whose text names the reason.
func TestForRefusesWhatItCannotRead(t *testing.T) {
	cases := []struct {
		name, text, version, want string
	}{
		{"too few parts", declared, "0.3", `version "0.3"`},
		{"non-numeric part", declared, "0.x.7", `version "0.x.7"`},
		{"bad YAML", "- version: [", "0.3.7", "needs.yml"},
		{"declared version unreadable", "- version: soon\n", "0.3.7", `needs.yml: version "soon"`},
	}
	for _, c := range cases {
		got, err := forVersion(c.text, c.version)
		if got != nil || err == nil || !strings.Contains(err.Error(), c.want) {
			t.Errorf("%s: want no needs and an error naming %s, got %v, %v", c.name, c.want, got, err)
		}
	}
}
