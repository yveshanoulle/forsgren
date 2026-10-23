package needs

import (
	"reflect"
	"slices"
	"strings"
	"testing"
)

// TestForReturnsTheNeedsAppliedFromTheirVersionOn (forsgren#73): a need
// introduced in 0.4.0 applies to 0.4.0 and every later version, and to none
// before it; versions compare as numbers, so 0.4.10 is later than 0.4.9.
func TestForReturnsTheNeedsAppliedFromTheirVersionOn(t *testing.T) {
	issuesWrite := Need{
		Version:    "0.4.0",
		Kind:       "permission",
		Workflow:   ".github/workflows/forsgren.yml",
		Permission: "issues",
		Access:     "write",
		Steps:      wantIssuesWriteSteps,
	}
	cases := []struct {
		version string
		want    []Need
	}{
		{"0.3.9", nil},
		{"0.4.0", []Need{issuesWrite}},
		{"0.4.10", []Need{issuesWrite}},
		{"0.10.0", []Need{issuesWrite}},
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
		{"kind with no check", "- version: 0.4.0\n  kind: permision\n", "0.4.0", `kind "permision"`},
	}
	for _, c := range cases {
		got, err := forVersion(c.text, c.version)
		if got != nil {
			t.Errorf("%s: want no needs, got %v", c.name, got)
		}
		if err == nil || !strings.Contains(err.Error(), c.want) {
			t.Errorf("%s: want an error naming %s, got %v", c.name, c.want, err)
		}
	}
}

// TestEveryNeedIsIntroducedInAMinorOrMajor (forsgren#78): a release that
// declares a new need asks the installation for something, so it is a minor
// or a major, never a patch. Every embedded entry's version has patch 0.
func TestEveryNeedIsIntroducedInAMinorOrMajor(t *testing.T) {
	all, err := For("999.999.999")
	if err != nil {
		t.Fatal(err)
	}
	for _, n := range all {
		if !strings.HasSuffix(n.Version, ".0") {
			t.Errorf("need %s %s: version %s has a patch number; a release that declares a need is a minor or a major (x.y.0)",
				n.Kind, n.Permission+n.File+n.Key+n.Secret, n.Version)
		}
	}
}

// wantPullRequestsReadSteps is the setup issue's item for a caller that does
// not grant pull-requests: read (forsgren#255).
const wantPullRequestsReadSteps = "Add `pull-requests: read` to the `permissions:` of the forsgren job in " +
	".github/workflows/forsgren.yml, so forsgren can read the merged pull requests of the measured " +
	"repositories for the Mainline Lead Time. When FORSGREN_TOKEN is a fine-grained token, give it " +
	"Pull requests (read) as well. Without it everything else is still collected: only the pull " +
	"requests are not read."

// TestFromTheMergedPullRequestsReleaseTheCallerGrantsPullRequestsRead
// (forsgren#255, Yves's ruling on the issue): from 1.15.0, the release that
// collects the merged pull requests (one release with forsgren#254,
// forsgren#319), a caller workflow without pull-requests: read is named in the
// setup issue; the template's caller, which grants it, needs nothing, and
// 1.14.0 does not ask for it.
func TestFromTheMergedPullRequestsReleaseTheCallerGrantsPullRequestsRead(t *testing.T) {
	want := Need{Version: "1.15.0", Kind: "permission", Workflow: callerWorkflow,
		Permission: "pull-requests", Access: "read", Steps: wantPullRequestsReadSteps}
	before, err := For("1.14.0")
	asksForPulls := slices.ContainsFunc(before, func(n Need) bool { return n.Permission == want.Permission })
	if err != nil || asksForPulls {
		t.Errorf("For(1.14.0): want no pull-requests need and no error, got %v, %v", before, err)
	}
	from, err := For("1.15.0")
	if err != nil || !slices.Contains(from, want) {
		t.Fatalf("For(1.15.0): want %v among the needs and no error, got %v, %v", want, from, err)
	}
	cases := []permissionCase{
		{"template shape, grants it", want, templateWorkflow, true},
		{"caller without it", want, templateHead + "      id-token: write\n", false},
	}
	for _, c := range cases {
		c.assert(t)
	}
}
