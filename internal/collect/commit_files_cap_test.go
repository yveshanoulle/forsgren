package collect

import (
	"fmt"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// The cap of the commit files read (forsgren#589, step 1, Yves's ruling): a
// run reads the files of at most 1000 commits of a repository, newest first,
// and the next run continues, so the fill of thousands of commits never
// spends a whole request budget in one run.

// capOfARun is the cap Yves ruled: 1000 commits a run.
const capOfARun = 1000

// manyCommits stores n commits of acme/app's deployment 1001, the i-th
// authored i minutes after 1 September, gives each its files on the fake,
// and returns the fake, the path of the history and the SHAs, oldest first.
func manyCommits(t *testing.T, n int) (*gitHub, string, []string) {
	t.Helper()
	g := pullsOnly(t)
	path := historyPath(t)
	shas := make([]string, n)
	stored := make([]history.Commit, n)
	for i := range n {
		shas[i] = fmt.Sprintf("%040x", i+1)
		stored[i] = commit(1001, shas[i], at(1, 0, 0).Add(time.Duration(i)*time.Minute), at(20, 10, 0))
		g.bodies[filesPath(shas[i])] = filesBody("api/a.go")
	}
	if _, err := history.AppendCommits(commitsPath(path), stored); err != nil {
		t.Fatal(err)
	}
	return g, path, shas
}

// TestTheFilesReadStopsAtTheCapOfARunAndTheNextRunContinues: of 1002 commits
// without files the newest 1000 are read and stored, the repository is not
// noted as filled, stderr names the cap, the report names the repository as
// capped while it stays complete (a cap is no budget stop), and the next run
// reads the two oldest and notes the fill.
func TestTheFilesReadStopsAtTheCapOfARunAndTheNextRunContinues(t *testing.T) {
	g, path, shas := manyCommits(t, capOfARun+2)
	r := g.collect(t, shop(withPaths()), path, github.DefaultMaxPages)
	if r.err != nil || !strings.Contains(r.stderr, "acme/app: the commit files stopped at the cap of 1000 commits a run") {
		t.Fatalf("want stderr to name the cap and no error, got %v (stderr %q)", r.err, r.stderr)
	}
	g.wantAsked(t, reversed(shas[2:])...)
	wantCapped(t, g, path)
	g.requests = nil
	if r := g.collect(t, shop(withPaths()), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	g.wantAsked(t, shas[1], shas[0])
	dataOf(path).want(t, CommitFilesFilledFile, commitFilesFilledNow)
	g.wantReportOf(t, Report{})
}

// reversed is shas in the reverse order.
func reversed(shas []string) []string {
	out := slices.Clone(shas)
	slices.Reverse(out)
	return out
}

// wantCapped fails unless the run stored the files of the cap's commits,
// noted no fill, and reported the repository capped in a complete report.
func wantCapped(t *testing.T, g *gitHub, path string) {
	t.Helper()
	files, err := history.LoadCommitFiles(filepath.Join(filepath.Dir(path), CommitFilesFile))
	if err != nil || len(files) != capOfARun {
		t.Errorf("want the %d commits read stored, got %d (%v)", capOfARun, len(files), err)
	}
	dataOf(path).want(t, CommitFilesFilledFile, "")
	want := "# forsgren collect report v1\ncomplete\ncommit-files-capped acme/app\n"
	if got := g.report.Render(); got != want {
		t.Errorf("want the report\n%q\ngot\n%q", want, got)
	}
}

// TestACappedReportReadsBack: the commit-files-capped line reads back as it
// was written, and a line without the repository or with more is refused.
func TestACappedReportReadsBack(t *testing.T) {
	text := "# forsgren collect report v1\ncomplete\ncommit-files-capped acme/app\n"
	back, err := ParseReport(text)
	if err != nil || back.Render() != text {
		t.Errorf("want the report back, got %q (%v)", back.Render(), err)
	}
	for _, bad := range []string{"commit-files-capped\n", "commit-files-capped acme/app left=2\n"} {
		if _, err := ParseReport("# forsgren collect report v1\ncomplete\n" + bad); err == nil {
			t.Errorf("want %q refused, got no error", bad)
		}
	}
}
