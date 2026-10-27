package collect

import (
	"context"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// The files of the deployed commits (forsgren#496, step 3): for a repository
// whose services have paths, every commit in commits.csv that has no line in
// commit_files.csv gets its changed files read, newest deployment first.

const (
	commitFilesHeader       = "# forsgren commit files v1\nrepository,sha,path\n"
	commitFilesFilledHeader = "# forsgren commit files filled v1\nrepository,filled_at\n"
	commitFilesFilledNow    = commitFilesFilledHeader + "acme/app,2026-10-01T00:00:00Z\n"
)

// withPaths is acme/app's production with one service, deploy, that has paths.
func withPaths() config.Repository {
	r := production
	r.Services = map[string]string{"deploy": "API"}
	r.Paths = map[string][]string{"deploy": {"api/"}}
	return r
}

// withoutPaths is acme/app's production with a service that has no paths.
func withoutPaths() config.Repository {
	r := production
	r.Services = map[string]string{"deploy": "API"}
	return r
}

// filesPath is GitHub's commit sha in acme/app.
func filesPath(sha string) string { return "/repos/acme/app/commits/" + sha }

// filesBody is GitHub's commit with these changed files.
func filesBody(names ...string) string {
	items := make([]string, len(names))
	for i, n := range names {
		items[i] = `{"filename": "` + n + `"}`
	}
	return `{"sha": "x", "files": ` + list(items...) + `}`
}

// storedCommits stores the commits B (deployment 1002, deployed 22 September)
// and A (deployment 1001, deployed 20 September) of acme/app, and returns the
// fake that lists nothing else and the path of the history.
func storedCommits(t *testing.T) (*gitHub, string) {
	t.Helper()
	g := pullsOnly(t)
	path := historyPath(t)
	stored := []history.Commit{
		commit(1001, shaA, at(19, 9, 0), at(20, 10, 0)),
		commit(1002, shaB, at(21, 9, 0), at(22, 10, 0)),
	}
	if _, err := history.AppendCommits(commitsPath(path), stored); err != nil {
		t.Fatal(err)
	}
	return g, path
}

// filesAsked is the commits the fake was asked the files of, in order.
func (g *gitHub) filesAsked() []string {
	var asked []string
	for _, r := range g.seen("/repos/acme/app/commits/") {
		asked = append(asked, strings.TrimPrefix(strings.SplitN(r, "?", 2)[0], "/repos/acme/app/commits/"))
	}
	return asked
}

// wantAsked fails unless the fake was asked the files of exactly these
// commits, in order.
func (g *gitHub) wantAsked(t *testing.T, want ...string) {
	t.Helper()
	if got := g.filesAsked(); strings.Join(got, " ") != strings.Join(want, " ") {
		t.Errorf("want the files of %v asked, got %v", want, got)
	}
}

// TestTheFilesOfEveryStoredCommitAreReadNewestFirstForAServiceWithPaths: both
// commits get their lines, a rename both paths, the newest deployment's
// commit is asked first, and the repository is noted as filled.
func TestTheFilesOfEveryStoredCommitAreReadNewestFirstForAServiceWithPaths(t *testing.T) {
	g, path := storedCommits(t)
	g.bodies[filesPath(shaB)] = `{"files": [{"filename": "web/b.go"}, ` +
		`{"filename": "api/new.go", "previous_filename": "web/old.go"}]}`
	g.bodies[filesPath(shaA)] = filesBody("api/a.go")
	r := g.collect(t, shop(withPaths()), path, github.DefaultMaxPages)
	if r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	g.wantAsked(t, shaB, shaA)
	data := dataOf(path)
	data.want(t, CommitFilesFile, commitFilesHeader+
		"acme/app,"+shaA+",api/a.go\n"+
		"acme/app,"+shaB+",api/new.go\n"+
		"acme/app,"+shaB+",web/b.go\n"+
		"acme/app,"+shaB+",web/old.go\n")
	data.want(t, CommitFilesFilledFile, commitFilesFilledNow)
	if !strings.HasSuffix(strings.TrimSpace(r.stdout), ", 2 commit files") {
		t.Errorf("want the stdout line to end with the 2 commits read, got %q", r.stdout)
	}
}

// TestARepositoryWithoutPathsNeverAsksForFiles: a repository whose services
// have no paths, or that has no services, costs no request and writes no file.
func TestARepositoryWithoutPathsNeverAsksForFiles(t *testing.T) {
	repositories := map[string]config.Repository{"service without paths": withoutPaths(), "no services": production}
	for name, repo := range repositories {
		t.Run(name, func(t *testing.T) {
			g, path := storedCommits(t)
			if r := g.collect(t, shop(repo), path, github.DefaultMaxPages); r.err != nil {
				t.Fatal(r.err)
			}
			g.wantAsked(t)
			dataOf(path).want(t, CommitFilesFile, "")
			dataOf(path).want(t, CommitFilesFilledFile, "")
		})
	}
}

// TestACommitReadWithNoFilesIsNotReadAgain: a commit that changes no file
// gets a line with an empty path, and the next run asks for nothing.
func TestACommitReadWithNoFilesIsNotReadAgain(t *testing.T) {
	g, path := storedCommits(t)
	g.bodies[filesPath(shaB)] = `{"sha": "x"}`
	g.bodies[filesPath(shaA)] = filesBody("api/a.go")
	if r := g.collect(t, shop(withPaths()), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	dataOf(path).want(t, CommitFilesFile, commitFilesHeader+"acme/app,"+shaA+",api/a.go\nacme/app,"+shaB+",\n")
	if r := g.collect(t, shop(withPaths()), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	g.wantAsked(t, shaB, shaA)
}

// TestOnlyTheCommitsWithoutLinesAreRead: a commit that has lines is not
// asked, whatever the case of the repository name in its lines.
func TestOnlyTheCommitsWithoutLinesAreRead(t *testing.T) {
	g, path := storedCommits(t)
	dataOf(path).write(t, CommitFilesFile, commitFilesHeader+"ACME/app,"+shaB+",web/b.go\n")
	g.bodies[filesPath(shaA)] = filesBody("api/a.go")
	if r := g.collect(t, shop(withPaths()), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	g.wantAsked(t, shaA)
	dataOf(path).want(t, CommitFilesFile, commitFilesHeader+"ACME/app,"+shaB+",web/b.go\nacme/app,"+shaA+",api/a.go\n")
}

// TestTheCommitsOfADeploymentStoredInTheSameRunAreReadToo: the new
// deployment's commits are in commits.csv before the files are read.
func TestTheCommitsOfADeploymentStoredInTheSameRunAreReadToo(t *testing.T) {
	path := historyPath(t)
	held := record(history.KindEnvironment, "production", 1001, shaA, at(20, 10, 0), history.StateSuccess, "deploy")
	if _, err := history.Append(path, []history.Record{held}); err != nil {
		t.Fatal(err)
	}
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(deployment(1002, shaB, "deploy", "2026-09-22T10:00:00Z"))
	g.succeeded("1002")
	g.bodies[comparePath(shaA, shaB)] = ahead(authored{shaC, at(21, 9, 0)}, authored{shaB, at(22, 8, 0)})
	g.bodies[filesPath(shaC)] = filesBody("api/c.go")
	g.bodies[filesPath(shaB)] = filesBody("go.mod")
	if r := g.collect(t, shop(withPaths()), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	dataOf(path).want(t, CommitFilesFile, commitFilesHeader+
		"acme/app,"+shaB+",go.mod\nacme/app,"+shaC+",api/c.go\n")
}

// TestTheFilesStopWithinTheRequestBudgetAndTheNextRunContinues: at the margin
// the commit read whole is stored and the repository is not noted as filled;
// stderr says so, the run does not fail, the report names the repository, and
// the next run reads the rest.
func TestTheFilesStopWithinTheRequestBudgetAndTheNextRunContinues(t *testing.T) {
	g, path := storedCommits(t)
	g.bodies[filesPath(shaB)] = filesBody("api/b.go")
	g.bodies[filesPath(shaA)] = filesBody("api/a.go")
	g.left[filesPath(shaB)] = 250
	r := g.collect(t, shop(withPaths()), path, github.DefaultMaxPages)
	if r.err != nil || !strings.Contains(r.stderr, "acme/app: the commit files were cut short") {
		t.Errorf("want stderr to say the read was cut short and no error, got %q, %v", r.stderr, r.err)
	}
	data := dataOf(path)
	data.want(t, CommitFilesFile, commitFilesHeader+"acme/app,"+shaB+",api/b.go\n")
	data.want(t, CommitFilesFilledFile, "")
	g.wantReportOf(t, Report{FilesCut: []string{"acme/app"}, Reset: g.resetAt.UTC()})
	delete(g.left, filesPath(shaB))
	if r := g.collect(t, shop(withPaths()), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	data.want(t, CommitFilesFile, commitFilesHeader+"acme/app,"+shaB+",api/b.go\nacme/app,"+shaA+",api/a.go\n")
	data.want(t, CommitFilesFilledFile, commitFilesFilledNow)
}

// containsAll says whether s holds every one of parts.
func containsAll(s string, parts ...string) bool {
	return !slices.ContainsFunc(parts, func(p string) bool { return !strings.Contains(s, p) })
}

// wantStored fails unless the file at path holds exactly one record.
func wantStored[T any](t *testing.T, path string, load func(string) ([]T, error)) {
	t.Helper()
	if got, err := load(path); err != nil || len(got) != 1 {
		t.Errorf("want one record in %s, got %v, %v", filepath.Base(path), got, err)
	}
}

// TestTheFilesAreReadLastSoACutThereKeepsThePullRequestsAndThePushes: fresh
// data comes first. The read of the files is cut by the budget after its first
// commit, and the repository's pull requests and pushes of that run are
// stored all the same.
func TestTheFilesAreReadLastSoACutThereKeepsThePullRequestsAndThePushes(t *testing.T) {
	g, path := storedCommits(t)
	g.bodies[pullsPath] = list(pull12.json())
	g.bodies[pull12.commitsPath()] = list(commitAt("2026-09-21T10:00:00Z"))
	g.bodies[activityPath] = list(activityOf("push", pushTime1, shaA, shaD))
	g.bodies[comparePath(shaA, shaD)] = chain(shaA, shaB, shaC, shaD)
	g.bodies[filesPath(shaB)] = filesBody("api/b.go")
	g.left[filesPath(shaB)] = 250
	r := g.collect(t, shop(withPaths()), path, github.DefaultMaxPages)
	if r.err != nil || !strings.Contains(r.stderr, "the commit files were cut short") {
		t.Fatalf("want the files cut short and no error, got %v (stderr %q)", r.err, r.stderr)
	}
	wantStored(t, filepath.Join(filepath.Dir(path), "pulls.csv"), history.LoadPullRequests)
	wantStored(t, filepath.Join(filepath.Dir(path), PushesFile), history.LoadPushes)
	dataOf(path).want(t, CommitFilesFile, commitFilesHeader+"acme/app,"+shaB+",api/b.go\n")
	g.wantReportOf(t, Report{FilesCut: []string{"acme/app"}, Reset: g.resetAt.UTC()})
}

// TestARefusedFilesReadNamesThePermissionAndNeverFails: a 403 stores nothing,
// notes no fill, names Contents: Read on stderr and does not fail the run; no
// denied mark is written, the push read's would blank the TBD page.
func TestARefusedFilesReadNamesThePermissionAndNeverFails(t *testing.T) {
	g, path := storedCommits(t)
	g.deny(filesPath(shaB))
	r := g.collect(t, shop(withPaths()), path, github.DefaultMaxPages)
	if r.err != nil || !containsAll(r.stderr, "Contents: Read", "commit files") {
		t.Errorf("want stderr to name Contents: Read and the commit files, and no error, got %q, %v", r.stderr, r.err)
	}
	g.wantAsked(t, shaB)
	data := dataOf(path)
	data.want(t, CommitFilesFile, commitFilesHeader)
	data.want(t, CommitFilesFilledFile, "")
	data.want(t, PushesDeniedFile, "")
	data.want(t, PullsDeniedFile, "")
}

// TestAFilesReadGitHubAnswersWronglyFailsTheRepositoryAfterStoringWhatItRead:
// any other error fails the repository, the commits read before it are
// stored, and the repository is not noted.
func TestAFilesReadGitHubAnswersWronglyFailsTheRepositoryAfterStoringWhatItRead(t *testing.T) {
	g, path := storedCommits(t)
	g.bodies[filesPath(shaB)] = filesBody("api/b.go")
	g.bodies[filesPath(shaA)] = `{"message": "boom"}`
	g.status[filesPath(shaA)] = http.StatusInternalServerError
	r := g.collect(t, shop(withPaths()), path, github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) {
		t.Errorf("want ErrFailed, got %v (stderr %q)", r.err, r.stderr)
	}
	data := dataOf(path)
	data.want(t, CommitFilesFile, commitFilesHeader+"acme/app,"+shaB+",api/b.go\n")
	data.want(t, CommitFilesFilledFile, "")
}

// TestACommitWithMoreFilesThanGitHubListsIsStoredAsReadAndNamed: a list cut at
// the page limit stores the paths read, is named on stderr, and the commit is
// not read again.
func TestACommitWithMoreFilesThanGitHubListsIsStoredAsReadAndNamed(t *testing.T) {
	g, path := storedCommits(t)
	g.bodies[filesPath(shaB)] = filesBody("api/b.go")
	g.paged[filesPath(shaB)] = true
	g.bodies[filesPath(shaA)] = filesBody("api/a.go")
	r := g.collect(t, shop(withPaths()), path, 1)
	if r.err != nil || !strings.Contains(r.stderr, "acme/app: commit "+shaB+": more files than were read") {
		t.Errorf("want stderr to name the cut commit and no error, got %q, %v", r.stderr, r.err)
	}
	dataOf(path).want(t, CommitFilesFile, commitFilesHeader+
		"acme/app,"+shaA+",api/a.go\nacme/app,"+shaB+",api/b.go\n")
	dataOf(path).want(t, CommitFilesFilledFile, commitFilesFilledNow)
}

// TestACommitGitHubDoesNotHaveIsNamedAndLeftWithoutLines: a 404 (history
// rewritten) is named on stderr, the commit stays without lines and the other
// commits are read; the repository is not noted as filled, but the run does
// not fail.
func TestACommitGitHubDoesNotHaveIsNamedAndLeftWithoutLines(t *testing.T) {
	g, path := storedCommits(t)
	g.bodies[filesPath(shaA)] = filesBody("api/a.go")
	r := g.collect(t, shop(withPaths()), path, github.DefaultMaxPages)
	if r.err != nil || !strings.Contains(r.stderr, "acme/app: commit "+shaB+": not found") {
		t.Errorf("want stderr to name the missing commit and no error, got %q, %v", r.stderr, r.err)
	}
	g.wantAsked(t, shaB, shaA)
	dataOf(path).want(t, CommitFilesFile, commitFilesHeader+"acme/app,"+shaA+",api/a.go\n")
	dataOf(path).want(t, CommitFilesFilledFile, "")
}

// TestAFileNameThatCannotBeStoredFailsTheRepository: a path with a line break
// is refused by the file, so the repository fails and nothing is stored.
func TestAFileNameThatCannotBeStoredFailsTheRepository(t *testing.T) {
	g, path := storedCommits(t)
	g.bodies[filesPath(shaB)] = `{"files": [{"filename": "a\nb.go"}]}`
	r := g.collect(t, shop(withPaths()), path, github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) || !strings.Contains(r.stderr, "path has a line break") {
		t.Errorf("want ErrFailed naming the path, got %v (stderr %q)", r.err, r.stderr)
	}
	dataOf(path).want(t, CommitFilesFilledFile, "")
}

// TestAFileTheFillReadsThatTurnsUnreadableFailsTheFill: the commits file or
// the commit files file that cannot be read is the fill's error, and no
// request is sent.
func TestAFileTheFillReadsThatTurnsUnreadableFailsTheFill(t *testing.T) {
	for _, name := range []string{"commits.csv", CommitFilesFile} {
		t.Run(name, func(t *testing.T) {
			g, path := storedCommits(t)
			unreadable := filepath.Join(filepath.Dir(path), name)
			if err := os.RemoveAll(unreadable); err != nil {
				t.Fatal(err)
			}
			if err := os.MkdirAll(unreadable, 0o750); err != nil {
				t.Fatal(err)
			}
			o := Options{History: path, Stderr: io.Discard}
			if _, err := o.fillCommitFiles(context.Background(), held{}, withPaths()); err == nil {
				t.Error("want an error for an unreadable file, got none")
			}
			g.wantAsked(t)
		})
	}
}

// TestACommitFilesFileThatCannotBeReadRefusesTheRun: a commit_files.csv that
// is not in the format is an error naming it, before GitHub is asked anything.
func TestACommitFilesFileThatCannotBeReadRefusesTheRun(t *testing.T) {
	g, path := storedCommits(t)
	dataOf(path).write(t, CommitFilesFile, "not a commit files file\n")
	r := g.collect(t, shop(withPaths()), path, github.DefaultMaxPages)
	if r.err == nil || !strings.Contains(r.err.Error(), CommitFilesFile) {
		t.Errorf("want an error naming %s, got %v", CommitFilesFile, r.err)
	}
	if n := len(g.requests); n != 0 {
		t.Errorf("want no request, got %d", n)
	}
}
