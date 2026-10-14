package collect

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"
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

// TestCollectStoresNoBugForAnIssueThatLostItsLabel (forsgren#126): an issue
// stored as a bug that GitHub no longer lists under the bug label is stored
// again, as not a bug, and one still listed is left as it is.
func TestCollectStoresNoBugForAnIssueThatLostItsLabel(t *testing.T) {
	g := newGitHub(t)
	path, _ := listFourOverStoredThreeAndFour(t, g)
	if r := g.collect(t, shop(production), path, 1); r.err != nil {
		t.Fatalf("want the run to succeed, got %v (stderr %q)", r.err, r.stderr)
	}
	got, err := history.LoadIssueBugs(bugsFileBeside(path))
	if err != nil {
		t.Fatalf("want a bug flags file, got %v", err)
	}
	want := []history.IssueBug{{Repository: "acme/app", Issue: 3}, {Repository: "acme/app", Issue: 4, Bug: true}}
	if !slices.Equal(got, want) {
		t.Errorf("want the bug flags\n%v\ngot\n%v", want, got)
	}
}

// TestACutListOfBugIssuesKeepsTheStoredFlagsAndSaysSo (forsgren#126): when the
// read of the issues labelled bug stopped at its page cap, an issue it did not
// list may still carry the label, so no stored bug is stored again as not a
// bug, and stderr says the read stopped.
func TestACutListOfBugIssuesKeepsTheStoredFlagsAndSaysSo(t *testing.T) {
	g := newGitHub(t)
	path, stored := listFourOverStoredThreeAndFour(t, g)
	g.paged[bugIssuesPath] = true
	r := g.collect(t, shop(production), path, 1)
	if r.err != nil {
		t.Fatalf("want the run to succeed, got %v (stderr %q)", r.err, r.stderr)
	}
	got, err := history.LoadIssueBugs(bugsFileBeside(path))
	if err != nil || !slices.Equal(got, stored) {
		t.Errorf("want the stored bug flags kept\n%v\ngot\n%v, %v", stored, got, err)
	}
	if !strings.Contains(r.stderr, "the bug read stopped at 100 page(s)") {
		t.Errorf("want stderr to say the bug read stopped at 100 pages, got %q", r.stderr)
	}
}

// listFourOverStoredThreeAndFour has g list acme/app with no deployments and
// issue 4 alone under the bug label, and stores issues 3 and 4 of acme/app as
// bugs beside a new history; it returns the history path and the stored flags.
func listFourOverStoredThreeAndFour(t *testing.T, g *gitHub) (string, []history.IssueBug) {
	t.Helper()
	g.bodies[deploymentsPath] = list()
	g.bodies[bugIssuesPath] = list(listed{number: 4, state: "open", created: "2026-09-20T08:00:00Z"}.json())
	path := historyPath(t)
	stored := []history.IssueBug{
		{Repository: "acme/app", Issue: 3, Bug: true},
		{Repository: "acme/app", Issue: 4, Bug: true},
	}
	if _, err := history.AppendIssueBugs(bugsFileBeside(path), stored); err != nil {
		t.Fatal(err)
	}
	return path, stored
}

// TestABugFlagsFileItCannotReadFailsTheRepositoryBeforeTheBugRead
// (forsgren#126): an issue_bugs.csv with an unknown version fails the
// repository before GitHub is asked for the bug issues, stores no deployment
// and stays as it was. Proven by mutation.
func TestABugFlagsFileItCannotReadFailsTheRepositoryBeforeTheBugRead(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(deployment(1001, shaA, "deploy", "2026-09-21T10:00:00Z"))
	g.bodies[statusesPath("1001")] = list(status(6, "success", "2026-09-21T10:05:00Z"))
	path := historyPath(t)
	bugs := bugsFileBeside(path)
	const content = "# forsgren issue bugs v9\n"
	writeFileAt(t, bugs, content)
	r := g.collect(t, shop(production), path, 1)
	if !errors.Is(r.err, ErrFailed) || len(g.seen(issuesPath+"?labels=bug")) != 0 {
		t.Errorf("want the repository failed before the bug read, got %v after %v", r.err, g.seen(issuesPath))
	}
	if got, _ := os.ReadFile(filepath.Clean(bugs)); string(got) != content {
		t.Errorf("want the bug flags file untouched, got %q", got)
	}
	if _, err := os.Stat(path); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want no history written, got %v", err)
	}
}

// writeFileAt writes content to path, its folder made.
func writeFileAt(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}
