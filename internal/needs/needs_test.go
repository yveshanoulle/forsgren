package needs

import (
	"reflect"
	"testing"
)

// TestForReturnsTheNeedsAppliedFromTheirVersionOn (forsgren#73): a need
// introduced in 0.3.7 applies to 0.3.7 and every later version, and to none
// before it; versions compare as numbers, so 0.3.10 is later than 0.3.7.
func TestForReturnsTheNeedsAppliedFromTheirVersionOn(t *testing.T) {
	issuesWrite := Need{
		Version:    "0.3.7",
		Kind:       "permission",
		Workflow:   ".github/workflows/forsgren.yml",
		Permission: "issues",
		Access:     "write",
		Steps:      "Add `issues: write` to the `permissions:` of the job in .github/workflows/forsgren.yml, so forsgren can open its setup issue.",
	}
	cases := []struct {
		version string
		want    []Need
	}{
		{"0.3.6", nil},
		{"0.3.7", []Need{issuesWrite}},
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
