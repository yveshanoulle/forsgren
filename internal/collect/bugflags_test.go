package collect

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// bugsFileBeside is data/issue_bugs.csv next to the history at path.
func bugsFileBeside(path string) string { return filepath.Join(filepath.Dir(path), "issue_bugs.csv") }

// TestCollectStoresABugFlagForEveryIssueWithTheBugLabel (forsgren#126): the
// issues GitHub lists for the bug label, open or closed, are stored as bugs in
// data/issue_bugs.csv next to the history.
func TestCollectStoresABugFlagForEveryIssueWithTheBugLabel(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list()
	g.bodies[bugIssuesPath] = list(
		listed{number: 3, state: "open", created: "2026-09-20T08:00:00Z"}.json(),
		listed{2, "closed", "2026-09-15T07:45:00Z", "2026-09-21T09:30:00Z", "completed"}.json())
	path := historyPath(t)
	if r := g.collect(t, shop(production), path, 1); r.err != nil {
		t.Fatalf("want the run to succeed, got %v (stderr %q)", r.err, r.stderr)
	}
	got, err := history.LoadIssueBugs(bugsFileBeside(path))
	if err != nil {
		t.Fatalf("want a bug flags file, got %v", err)
	}
	want := []history.IssueBug{
		{Repository: "acme/app", Issue: 2, Bug: true},
		{Repository: "acme/app", Issue: 3, Bug: true},
	}
	if !slices.Equal(got, want) {
		t.Errorf("want the bug flags\n%v\ngot\n%v", want, got)
	}
}

// TestARefusedListOfBugIssuesFailsTheRepositoryWhole (forsgren#126): when
// GitHub refuses the list of the issues labelled bug, the repository is stored
// not at all, its deployments neither. Proven by mutation.
func TestARefusedListOfBugIssuesFailsTheRepositoryWhole(t *testing.T) {
	wantARefusedListToFailTheRepositoryWhole(t, bugIssuesPath)
}

// TestABugFlagsFileThatCannotBeWrittenStoresNoDeployment (forsgren#126): when
// issue_bugs.csv cannot be written, the repository fails and its deployments
// are not stored either, so the next run reads them again. Proven by mutation.
func TestABugFlagsFileThatCannotBeWrittenStoresNoDeployment(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(deployment(1001, shaA, "deploy", "2026-09-21T10:00:00Z"))
	g.bodies[statusesPath("1001")] = list(status(6, "success", "2026-09-21T10:05:00Z"))
	g.bodies[bugIssuesPath] = list(listed{number: 3, state: "open", created: "2026-09-20T08:00:00Z"}.json())
	path := historyPath(t)
	bugs := bugsFileBeside(path)
	if _, err := history.AppendIssueBugs(bugs, nil); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(bugs, 0o400); err != nil {
		t.Fatal(err)
	}
	if r := g.collect(t, shop(production), path, 1); !errors.Is(r.err, ErrFailed) {
		t.Errorf("want the run to fail on a read-only bug flags file, got %v (stderr %q)", r.err, r.stderr)
	}
	if _, err := os.Stat(path); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want no history written, got %v", err)
	}
}
