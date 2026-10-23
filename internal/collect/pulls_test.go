package collect

import (
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// The merged pull requests of each repository (forsgren#255, step 4).

const (
	pullsPath   = "/repos/acme/app/pulls"
	pullsHeader = "# forsgren pulls v1\nrepository,number,head_branch,created_at,merged_at,merge_commit,updated_at," +
		"first_commit_at,first_commit_cut,created_stands_in\n"
	pullsReadHeader = "# forsgren pulls read v1\nrepository,read_at\n"
	// readNow is the pulls read file after a run that moved acme/app's mark
	// to now.
	readNow = pullsReadHeader + "acme/app,2026-10-01T00:00:00Z\n"
)

// pull is a closed pull request of acme/app from the branch feature/<n>, its
// times as GitHub writes them; an empty merged time is one closed without a
// merge.
type pull struct {
	n                        int
	created, updated, merged string
}

// commitsPath is the path of the pull request's commits.
func (p pull) commitsPath() string { return pullsPath + "/" + strconv.Itoa(p.n) + "/commits" }

// json is the pull request as GitHub lists it: one closed without a merge has
// a null merged_at and a test-merge SHA.
func (p pull) json() string {
	m, sha := "null", shaC
	if p.merged != "" {
		m, sha = fmt.Sprintf("%q", p.merged), shaA
	}
	return fmt.Sprintf(`{"number": %d, "title": "Change %d", "user": {"login": "someone"}, `+
		`"head": {"ref": "feature/%d"}, "created_at": %q, "updated_at": %q, "closed_at": %q, `+
		`"merged_at": %s, "merge_commit_sha": %q}`, p.n, p.n, p.n, p.created, p.updated, p.updated, m, sha)
}

// line is the pull request's line in pulls.csv with the first commit time
// first, empty when the created time stands in, and the cut flag.
func (p pull) line(first string, cut bool) string {
	return fmt.Sprintf("acme/app,%d,feature/%d,%s,%s,%s,%s,%s,%t,%t\n", p.n, p.n, p.created, p.merged, shaA,
		p.updated, first, cut, first == "")
}

// commitAt is one commit of a pull request as GitHub lists it, authored at
// authored (null when empty) and committed later.
func commitAt(authored string) string {
	a := "null"
	if authored != "" {
		a = fmt.Sprintf("%q", authored)
	}
	return fmt.Sprintf(`{"sha": %q, "commit": {"author": {"name": "Someone", "date": %s}, `+
		`"committer": {"date": "2026-09-30T00:00:00Z"}}}`, shaB, a)
}

// The pull requests the tests read.
var (
	pull12  = pull{12, "2026-09-22T08:00:00Z", "2026-09-25T09:00:00Z", "2026-09-25T09:00:00Z"}
	pull13  = pull{13, "2026-09-23T08:00:00Z", "2026-09-26T09:00:00Z", ""}
	pull14  = pull{14, "2026-09-24T08:00:00Z", "2026-09-27T09:00:00Z", "2026-09-27T09:00:00Z"}
	pull15  = pull{15, "2026-09-25T08:00:00Z", "2026-09-28T09:00:00Z", "2026-09-28T09:00:00Z"}
	oldPull = pull{20, "2025-09-01T08:00:00Z", "2025-09-30T00:00:00Z", "2025-09-30T00:00:00Z"}
	newPull = pull{21, "2025-10-01T08:00:00Z", "2025-10-02T00:00:00Z", "2025-10-02T00:00:00Z"}
)

// pullsOnly is a fake GitHub with no deployments and no issues, whose closed
// pull requests of acme/app are pulls, each with one commit authored the day
// before it was created at 10:00.
func pullsOnly(t *testing.T, pulls ...pull) *gitHub {
	t.Helper()
	g := issuesOnly(t)
	items := make([]string, 0, len(pulls))
	for _, p := range pulls {
		items = append(items, p.json())
		g.bodies[p.commitsPath()] = list(commitAt(p.dayBefore(t)))
	}
	g.bodies[pullsPath] = list(items...)
	return g
}

// dayBefore is 10:00 UTC on the day before p was created, as GitHub writes it.
func (p pull) dayBefore(t *testing.T) string {
	t.Helper()
	created, err := time.Parse(time.RFC3339, p.created)
	if err != nil {
		t.Fatal(err)
	}
	d := created.AddDate(0, 0, -1)
	return time.Date(d.Year(), d.Month(), d.Day(), 10, 0, 0, 0, time.UTC).Format(time.RFC3339)
}

// dataDir is the directory of a test's history, where the pulls files go.
type dataDir string

// dataOf is the directory of the history at path.
func dataOf(path string) dataDir { return dataDir(filepath.Dir(path)) }

// write writes content to the file name in d.
func (d dataDir) write(t *testing.T, name, content string) {
	t.Helper()
	if err := os.MkdirAll(string(d), 0o750); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(string(d), name), []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}

// want fails unless the file name in d holds want; an empty want is no file.
func (d dataDir) want(t *testing.T, name, want string) {
	t.Helper()
	raw, err := os.ReadFile(filepath.Clean(filepath.Join(string(d), name)))
	if want == "" && errors.Is(err, os.ErrNotExist) {
		return
	}
	if string(raw) != want {
		t.Errorf("want %s\n%q\ngot\n%q (%v)", name, want, raw, err)
	}
}

// TestCollectStoresMergedPullRequestsWithTheirFirstCommitTime: each merged
// pull request is stored with the earliest author date of its commits; one
// closed without a merge is neither stored nor asked for its commits; one
// whose commit list gives no usable date, no commit or a commit without an
// author date, is stored with its created time standing in (forsgren#300).
// The report line counts them, and the read mark moves to now.
func TestCollectStoresMergedPullRequestsWithTheirFirstCommitTime(t *testing.T) {
	g := pullsOnly(t, pull15, pull14, pull13, pull12)
	g.bodies[pull12.commitsPath()] = list(commitAt("2026-09-21T10:00:00Z"), commitAt("2026-09-20T10:00:00Z"))
	g.bodies[pull14.commitsPath()] = list()
	g.bodies[pull15.commitsPath()] = list(commitAt(""))
	path := historyPath(t)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	wantStdout(t, r, "acme/app: 0 new, 0 skipped (not final), 0 commits, 3 merged pull requests\n")
	data := dataOf(path)
	data.want(t, "pulls.csv", pullsHeader+pull12.line("2026-09-20T10:00:00Z", false)+pull14.line("", false)+
		pull15.line("", false))
	data.want(t, "pulls_read.csv", readNow)
	if got := g.seen(pull13.commitsPath()); len(got) != 0 {
		t.Errorf("want no commits asked of the unmerged pull request, got %v", got)
	}
	for _, n := range []string{"pull request 14", "pull request 15"} {
		if !strings.Contains(r.stderr, n) || !strings.Contains(r.stderr, "created time stands in") {
			t.Errorf("want stderr to name %s and its created time standing in, got %q", n, r.stderr)
		}
	}
}

// TestThePullRequestsAreReadFromWhereTheLastReadEnded: the read asks for the
// pull requests updated since the mark less a day, never before history_days
// back, and since history_days back when there is no mark; a pull request
// merged before history_days back is not stored, whenever it was updated.
// The list is paged here: a read that meets an older pull request stops at
// it and asks no next page.
func TestThePullRequestsAreReadFromWhereTheLastReadEnded(t *testing.T) {
	before := pull{30, "2026-09-18T08:00:00Z", "2026-09-19T07:00:00Z", "2026-09-19T07:00:00Z"}
	within := pull{31, "2026-09-18T08:00:00Z", "2026-09-19T09:00:00Z", "2026-09-19T09:00:00Z"}
	mergedLongAgo := pull{51, "2025-09-01T08:00:00Z", "2026-09-20T00:00:00Z", "2025-09-02T00:00:00Z"}
	for _, c := range []struct {
		name, mark string // the mark before the run, empty for none
		pulls      []pull
		want       string // the stored lines
	}{
		{"no mark reads history_days back", "", []pull{newPull, oldPull}, newPull.line("2025-09-30T10:00:00Z", false)},
		{"a mark less a day", "2026-09-20T08:00:00Z", []pull{within, before}, within.line("2026-09-17T10:00:00Z", false)},
		{"a mark older than history_days", "2024-01-01T00:00:00Z", []pull{newPull, oldPull},
			newPull.line("2025-09-30T10:00:00Z", false)},
		{"merged before history_days", "", []pull{mergedLongAgo, oldPull}, ""},
	} {
		t.Run(c.name, func(t *testing.T) {
			g := pullsOnly(t, c.pulls...)
			g.paged[pullsPath] = true
			path := historyPath(t)
			data := dataOf(path)
			if c.mark != "" {
				data.write(t, "pulls_read.csv", pullsReadHeader+"acme/app,"+c.mark+"\n")
			}
			if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
				t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
			}
			data.want(t, "pulls.csv", pullsHeader+c.want)
			data.want(t, "pulls_read.csv", readNow)
			if got := g.seen(pullsPath + "?"); len(got) != 1 {
				t.Errorf("want the read to stop at the older pull request on page 1, got %v", got)
			}
		})
	}
}

// TestAStoredPullRequestIsNotAskedForItsCommitsAgain: a pull request
// pulls.csv already holds keeps its line (decision #306) and costs no
// commits request.
func TestAStoredPullRequestIsNotAskedForItsCommitsAgain(t *testing.T) {
	stored := pullsHeader + pull12.line("2026-09-20T10:00:00Z", false)
	g := pullsOnly(t, pull{12, pull12.created, "2026-09-29T09:00:00Z", pull12.merged})
	path := historyPath(t)
	dataOf(path).write(t, "pulls.csv", stored)
	wantStdout(t, g.collect(t, shop(production), path, github.DefaultMaxPages),
		"acme/app: 0 new, 0 skipped (not final), 0 commits\n")
	dataOf(path).want(t, "pulls.csv", stored)
	if got := g.seen(pull12.commitsPath()); len(got) != 0 {
		t.Errorf("want no commits asked of a stored pull request, got %v", got)
	}
}

// TestACutCommitListKeepsItsTimeWithTheCutFlag (forsgren#299, #300): a
// commit list cut at the page limit keeps its earliest author date, a lower
// bound, with first_commit_cut; the created time does not stand in.
func TestACutCommitListKeepsItsTimeWithTheCutFlag(t *testing.T) {
	g := pullsOnly(t, pull12)
	g.paged[pull12.commitsPath()] = true
	path := historyPath(t)
	if r := g.collect(t, shop(production), path, 1); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	dataOf(path).want(t, "pulls.csv", pullsHeader+pull12.line("2026-09-21T10:00:00Z", true))
}

// TestAPullRequestListCutAtThePageLimitIsNamedAndTheMarkMoves: the read
// stores what it read, says on stderr that older pull requests were not
// read, and moves its mark: the list is newest first, so reading it again
// from the same mark would read the same pages.
func TestAPullRequestListCutAtThePageLimitIsNamedAndTheMarkMoves(t *testing.T) {
	g := pullsOnly(t, pull12)
	g.paged[pullsPath] = true
	path := historyPath(t)
	r := g.collect(t, shop(production), path, 1)
	if r.err != nil || !strings.Contains(r.stderr, "acme/app: read the newest 1 page(s) of pull requests only") {
		t.Errorf("want stderr to name the cut pull request list, got %q, %v", r.stderr, r.err)
	}
	dataOf(path).want(t, "pulls.csv", pullsHeader+pull12.line("2026-09-21T10:00:00Z", false))
	dataOf(path).want(t, "pulls_read.csv", readNow)
}

// oneSuccess makes the fake list one successful deployment of acme/app.
func (g *gitHub) oneSuccess() {
	g.bodies[deploymentsPath] = list(deployment(1003, shaC, "deploy", "2026-09-20T10:00:00Z"))
	g.bodies[statusesPath("1003")] = list(status(3, "success", "2026-09-20T10:05:00Z"))
}

// deny makes the fake answer path with a 403 for the token's missing
// permission.
func (g *gitHub) deny(path string) {
	g.bodies[path] = `{"message":"Resource not accessible by integration"}`
	g.status[path] = http.StatusForbidden
}

// TestAMissingPullRequestsPermissionNeverFailsTheCollection (Yves's ruling
// on #255): a 403 on the pull requests stores none of them and moves no
// mark, stderr names the missing permission, and the deployments and the
// run go on.
func TestAMissingPullRequestsPermissionNeverFailsTheCollection(t *testing.T) {
	g := pullsOnly(t)
	g.oneSuccess()
	g.deny(pullsPath)
	path := historyPath(t)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	wantStdout(t, r, "acme/app: 1 new, 0 skipped (not final), 0 commits\n")
	if !strings.Contains(r.stderr, "pull-requests: read") {
		t.Errorf("want stderr to name the missing pull-requests: read, got %q", r.stderr)
	}
	dataOf(path).want(t, "pulls_read.csv", "")
	if len(g.report.Failed) != 0 || len(g.report.Cuts) != 0 {
		t.Errorf("want nothing failed or cut in the report, got %+v", g.report)
	}
}

// TestADeniedCommitListKeepsThePullRequestsReadWhole: a 403 on a pull
// request's commits stores the pull requests read before it, moves no mark
// and does not fail the run (Yves's ruling on #255).
func TestADeniedCommitListKeepsThePullRequestsReadWhole(t *testing.T) {
	g := pullsOnly(t, pull14, pull12)
	g.deny(pull12.commitsPath())
	path := historyPath(t)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	wantStdout(t, r, "acme/app: 0 new, 0 skipped (not final), 0 commits, 1 merged pull requests\n")
	if !strings.Contains(r.stderr, "pull-requests: read") {
		t.Errorf("want stderr to name the missing pull-requests: read, got %q", r.stderr)
	}
	dataOf(path).want(t, "pulls.csv", pullsHeader+pull14.line("2026-09-23T10:00:00Z", false))
	dataOf(path).want(t, "pulls_read.csv", "")
}

// TestThePullRequestsStopWithinTheRequestBudget (forsgren#64): a pull
// request's commits are read only while the budget has room for all their
// pages; at the margin the pull requests read whole are stored, the mark
// stays, so the next run reads the rest, stderr says so and the run does not
// fail. The repository is not cut short: its deployments and issues were
// stored whole, so the one-time catch-up of its failure starts is done.
func TestThePullRequestsStopWithinTheRequestBudget(t *testing.T) {
	g := pullsOnly(t, pull14, pull12)
	g.left[pullsPath] = 300
	g.left[pull14.commitsPath()] = 251
	path := historyPath(t)
	data := dataOf(path)
	stored := pullsReadHeader + "acme/app,2026-09-20T08:00:00Z\n"
	data.write(t, "pulls_read.csv", stored)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if r.err != nil || !strings.Contains(r.stderr, "acme/app: the pull requests were cut short") {
		t.Errorf("want stderr to say the pull requests were cut short and no error, got %q, %v", r.stderr, r.err)
	}
	data.want(t, "pulls.csv", pullsHeader+pull14.line("2026-09-23T10:00:00Z", false))
	data.want(t, "pulls_read.csv", stored)
	if got := g.seen(pull12.commitsPath()); len(got) != 0 {
		t.Errorf("want no commits asked past the margin, got %v", got)
	}
	data.want(t, "starts_checked.csv",
		"# forsgren starts checked v1\nrepository,checked_at\nacme/app,2026-10-01T00:00:00Z\n")
}

// TestAPullRequestListGitHubAnswersWronglyFailsTheRepository: any other error
// of the read fails the repository, after its deployments are stored, and
// moves no mark.
func TestAPullRequestListGitHubAnswersWronglyFailsTheRepository(t *testing.T) {
	g := pullsOnly(t)
	g.oneSuccess()
	g.bodies[pullsPath] = list(`{"number": 0}`)
	path := historyPath(t)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) || !strings.Contains(r.stderr, "pull request") {
		t.Errorf("want ErrFailed and stderr naming the pull requests, got %v, %q", r.err, r.stderr)
	}
	wantRecords(t, path,
		record(history.KindEnvironment, "production", 1003, shaC, at(20, 10, 0), history.StateSuccess, "deploy"))
	dataOf(path).want(t, "pulls_read.csv", "")
}

// TestAPullsFileThatCannotBeReadRefusesTheRun: a pulls.csv or a
// pulls_read.csv not in its format is an error naming it, before GitHub is
// asked anything.
func TestAPullsFileThatCannotBeReadRefusesTheRun(t *testing.T) {
	for _, name := range []string{"pulls.csv", "pulls_read.csv"} {
		t.Run(name, func(t *testing.T) {
			g := pullsOnly(t)
			path := historyPath(t)
			dataOf(path).write(t, name, "nope\n")
			r := g.collect(t, shop(production), path, github.DefaultMaxPages)
			if !errors.Is(r.err, history.ErrMalformed) || !strings.Contains(r.err.Error(), name) {
				t.Errorf("want ErrMalformed naming %s, got %v", name, r.err)
			}
			if got := g.seen("/"); len(got) != 0 {
				t.Errorf("want GitHub asked nothing, got %v", got)
			}
		})
	}
}

// TestAPullsFileThatCannotBeWrittenFailsTheRepository: the error names
// pulls.csv and no mark moves.
func TestAPullsFileThatCannotBeWrittenFailsTheRepository(t *testing.T) {
	g := pullsOnly(t, pull12)
	path := historyPath(t)
	dataOf(path).write(t, "pulls.csv", pullsHeader)
	if err := os.Chmod(filepath.Join(filepath.Dir(path), "pulls.csv"), 0o400); err != nil {
		t.Fatal(err)
	}
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) || !strings.Contains(r.stderr, "pulls.csv") {
		t.Errorf("want ErrFailed and stderr naming pulls.csv, got %v, %q", r.err, r.stderr)
	}
	dataOf(path).want(t, "pulls_read.csv", "")
}
