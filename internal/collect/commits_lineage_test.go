package collect

import (
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// lineage is an authoredBy commit of a comparison with its parents, the
// first parent first, and its committer date as GitHub writes it, "" for an
// answer with no committer (forsgren#254).
type lineage struct {
	authoredBy
	parents   []string
	committed string
}

// comparisonOf is GitHub's answer to a comparison with status and
// total_commits, listing commits oldest first, each with its author login,
// parents and committer date.
func comparisonOf(status string, total int, commits ...lineage) string {
	items := make([]string, 0, len(commits))
	for _, c := range commits {
		items = append(items, c.answer())
	}
	return fmt.Sprintf(`{"status": %q, "ahead_by": %d, "behind_by": 0, "total_commits": %d, "commits": %s, `+
		`"files": []}`, status, total, total, list(items...))
}

// answer is c as one commit of GitHub's answer; the git name and email are
// there, as in GitHub's answer, for collect to leave out.
func (c lineage) answer() string {
	account, committer := "null", "null"
	if c.login != "" {
		account = fmt.Sprintf(`{"login": %q, "type": "User"}`, c.login)
	}
	if c.committed != "" {
		committer = fmt.Sprintf(`{"name": "Acme Dev", "email": "dev@acme.example", "date": %q}`, c.committed)
	}
	parents := make([]string, 0, len(c.parents))
	for _, p := range c.parents {
		parents = append(parents, fmt.Sprintf(`{"sha": %q}`, p))
	}
	return fmt.Sprintf(`{"sha": %q, "author": %s, "commit": {"author": {"name": "Acme Dev", `+
		`"email": "dev@acme.example", "date": %q}, "committer": %s, "message": "More"}, "parents": %s}`,
		c.sha, account, c.date.Format(time.RFC3339), committer, list(parents...))
}

// landed is commit with its parents and committer date.
func landed(c history.Commit, committed time.Time, parents ...string) history.Commit {
	c.Parents, c.CommittedAt = parents, committed
	return c
}

// TestCollectStoresEachCommitsParentsInOrderAndItsCommitterDate
// (forsgren#254, step 3): each stored commit keeps its parents in GitHub's
// order, the first parent first even when it sorts after the second, and
// its committer date in UTC, whole seconds; a commit GitHub gives no
// committer date for stores none, never its author date in its place.
func TestCollectStoresEachCommitsParentsInOrderAndItsCommitterDate(t *testing.T) {
	g := twoDeployments(t)
	g.bodies[comparePath(shaA, shaB)] = comparisonOf("ahead", 3,
		lineage{authoredBy{authored{shaC, at(21, 9, 0)}, ""}, []string{shaA}, "2026-09-21T11:30:00.5+02:00"},
		lineage{authoredBy{authored{shaD, at(21, 10, 0)}, ""}, []string{shaE, shaC}, "2026-09-21T10:15:00Z"},
		lineage{authoredBy{authored{shaB, at(22, 8, 0)}, ""}, []string{shaD}, ""})
	path := historyPath(t)
	wantStdout(t, g.collect(t, shop(production), path, github.DefaultMaxPages),
		"acme/app: 2 new, 0 skipped (not final), 3 commits\n")
	deployed := at(22, 10, 0)
	wantCommits(t, path,
		landed(commit(1002, shaC, at(21, 9, 0), deployed), at(21, 9, 30), shaA),
		landed(commit(1002, shaD, at(21, 10, 0), deployed), at(21, 10, 15), shaE, shaC),
		landed(commit(1002, shaB, at(22, 8, 0), deployed), time.Time{}, shaD))
}

// TestACommitStoredBeforeV3IsBackfilledOnALaterCollect (forsgren#254, step
// 3; changed by forsgren#385, step 2): a deployment stored by an earlier run
// is not compared as a new deployment again, but its commits from a v2 file
// are legacy (no parents, no committer date), so the one-time backfill
// compares the deployment once with its previous success and fills the
// parents and the committer date from GitHub, keeping the author the line has,
// while the file is rewritten as v3; the newer deployment's commits get theirs
// from its own comparison. Before #385 the stored line kept its empty parents
// and committer date (unknown) and the comparison was never made.
func TestACommitStoredBeforeV3IsBackfilledOnALaterCollect(t *testing.T) {
	path := historyPath(t)
	held := []history.Record{
		record(history.KindEnvironment, "production", 1001, shaA, at(20, 10, 0), history.StateSuccess, "deploy"),
		record(history.KindEnvironment, "production", 1002, shaB, at(22, 10, 0), history.StateSuccess, "deploy"),
	}
	if _, err := history.Append(path, held); err != nil {
		t.Fatal(err)
	}
	v2 := "# forsgren commits v2\nrepository,kind,deployment_id,commit,authored_at,deployed_at,author\n" +
		"acme/app,environment,1002," + shaB + ",2026-09-21T09:00:00Z,2026-09-22T10:00:00Z,ada-dev\n"
	if err := os.WriteFile(commitsPath(path), []byte(v2), 0o600); err != nil {
		t.Fatal(err)
	}
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(deployment(1003, shaD, "deploy", "2026-09-23T10:00:00Z"),
		deployment(1002, shaB, "deploy", "2026-09-22T10:00:00Z"), deployment(1001, shaA, "deploy", "2026-09-20T10:00:00Z"))
	g.succeeded("1003", "1002", "1001")
	g.bodies[comparePath(shaA, shaB)] = comparisonOf("ahead", 1,
		lineage{authoredBy{authored{shaB, at(21, 9, 0)}, "ada-dev"}, []string{shaA}, "2026-09-21T09:00:00Z"})
	g.bodies[comparePath(shaB, shaD)] = comparisonOf("ahead", 1,
		lineage{authoredBy{authored{shaD, at(23, 8, 0)}, ""}, []string{shaB}, "2026-09-23T08:30:00Z"})
	g.collect(t, shop(production), path, github.DefaultMaxPages)
	stored := commit(1002, shaB, at(21, 9, 0), at(22, 10, 0))
	stored.Author = "ada-dev"
	wantCommits(t, path, landed(stored, at(21, 9, 0), shaA),
		landed(commit(1003, shaD, at(23, 8, 0), at(23, 10, 0)), at(23, 8, 30), shaB))
	if asked := g.seen(comparePath(shaA, shaB)); len(asked) != 1 {
		t.Errorf("want the stored deployment 1002 compared once, by the backfill, got %v", asked)
	}
	file, err := os.ReadFile(commitsPath(path))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(string(file), "# forsgren commits v3\n") {
		t.Errorf("want the commits file rewritten as v3, got\n%s", file)
	}
}
