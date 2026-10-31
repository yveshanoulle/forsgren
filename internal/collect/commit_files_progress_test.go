package collect

import (
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/github"
)

// The progress of a commit files read (forsgren#594, step 1):
// data/commit_files_progress.csv keeps, per repository whose read is still
// going, the commits read and those left, so the Data page, rendered from the
// data files, can say how far the read is; the line goes once a run leaves
// none of its commits unread.

const commitFilesProgressHeader = "# forsgren commit files progress v1\nrepository,read,left\n"

// readFiles runs collect over acme/app with paths, so its commit files are
// read, and fails on an error.
func (g *gitHub) readFiles(t *testing.T, path string) {
	t.Helper()
	if r := g.collect(t, shop(withPaths()), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
}

// TestACappedReadKeepsItsProgressAndTheReadThatEndsItDropsIt: of 1002
// commits a run reads 1000 and keeps 1000 read, 2 left; the next run reads
// the last two and the repository's line is gone.
func TestACappedReadKeepsItsProgressAndTheReadThatEndsItDropsIt(t *testing.T) {
	g, path, _ := manyCommits(t, capOfARun+2)
	g.readFiles(t, path)
	data := dataOf(path)
	data.want(t, CommitFilesProgressFile, commitFilesProgressHeader+"acme/app,1000,2\n")
	g.readFiles(t, path)
	data.want(t, CommitFilesProgressFile, commitFilesProgressHeader)
}

// TestABudgetStopKeepsTheCountsItReached: a read the budget stops after its
// first commit keeps 1 read, 1 left, counted as the cap's are, and the next
// run, which reads the last one, drops the line.
func TestABudgetStopKeepsTheCountsItReached(t *testing.T) {
	g, path := storedCommits(t)
	g.bodies[filesPath(shaB)] = filesBody("api/b.go")
	g.bodies[filesPath(shaA)] = filesBody("api/a.go")
	g.left[filesPath(shaB)] = 250
	g.readFiles(t, path)
	data := dataOf(path)
	data.want(t, CommitFilesProgressFile, commitFilesProgressHeader+"acme/app,1,1\n")
	delete(g.left, filesPath(shaB))
	g.readFiles(t, path)
	data.want(t, CommitFilesProgressFile, commitFilesProgressHeader)
}

// TestARunThatReadsNoCommitFilesKeepsTheProgressAsItWas: a repository whose
// files are not read this run (no paths) keeps its line as it was.
func TestARunThatReadsNoCommitFilesKeepsTheProgressAsItWas(t *testing.T) {
	g, path := storedCommits(t)
	kept := commitFilesProgressHeader + "acme/app,4199,3925\n"
	dataOf(path).write(t, CommitFilesProgressFile, kept)
	if r := g.collect(t, shop(withoutPaths()), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	dataOf(path).want(t, CommitFilesProgressFile, kept)
}

// TestACommitFilesProgressFileThatCannotBeReadRefusesTheRun: a
// commit_files_progress.csv not in the format is an error naming it, before
// GitHub is asked anything.
func TestACommitFilesProgressFileThatCannotBeReadRefusesTheRun(t *testing.T) {
	g, path := storedCommits(t)
	dataOf(path).write(t, CommitFilesProgressFile, "nope\n")
	r := g.collect(t, shop(withPaths()), path, github.DefaultMaxPages)
	if r.err == nil || !strings.Contains(r.err.Error(), CommitFilesProgressFile) {
		t.Errorf("want an error naming %s, got %v", CommitFilesProgressFile, r.err)
	}
	if n := len(g.requests); n != 0 {
		t.Errorf("want no request, got %d", n)
	}
}
