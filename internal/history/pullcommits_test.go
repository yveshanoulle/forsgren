package history

import (
	"path/filepath"
	"testing"
	"time"
)

const (
	pullCommitsHead = "# forsgren pull commits v1\nrepository,number,sha,author,authored_at\n"
	pullCommitSHA   = "5555555555555555555555555555555555555555"
	pullCommitLine  = "acme/app,45," + pullCommitSHA + ",acme-dev,2026-09-01T07:00:00Z\n"
)

// pullCommit is a commit of pull request 45 of acme/app, by acme-dev,
// authored at 07:00 on 2026-09-01.
func pullCommit() PullCommit {
	return PullCommit{Repository: "acme/app", Number: 45, SHA: pullCommitSHA, Author: "acme-dev",
		AuthoredAt: time.Date(2026, 9, 1, 7, 0, 0, 0, time.UTC)}
}

// wantPullCommits fails unless the pull commits at path are want.
func wantPullCommits(t *testing.T, path string, want []PullCommit) {
	t.Helper()
	wantLoaded(t, path, LoadPullCommits, want)
}

// wantAppended fails unless appending c to the file at path stores n lines.
func wantAppended(t *testing.T, path string, c PullCommit, n int) {
	t.Helper()
	if got, err := AppendPullCommits(path, []PullCommit{c}); err != nil || got != n {
		t.Errorf("want %d line written for %v, got %d, %v", n, c, got, err)
	}
}

// TestAPullCommitIsWrittenOnceByRepositoryNumberAndSHA (forsgren#463, step
// 5): data/pull_commits.csv is created with its version and column lines; a
// commit already held (repository ignoring case, number and commit SHA) is
// not written again, whatever else it says.
func TestAPullCommitIsWrittenOnceByRepositoryNumberAndSHA(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data", "pull_commits.csv")
	wantAppended(t, path, pullCommit(), 1)
	again := pullCommit()
	again.Repository, again.Author = "ACME/app", "someone-else"
	wantAppended(t, path, again, 0)
	other := pullCommit()
	other.Number = 46
	wantAppended(t, path, other, 1)
	wantFile(t, path, pullCommitsHead+pullCommitLine+
		"acme/app,46,"+pullCommitSHA+",acme-dev,2026-09-01T07:00:00Z\n")
	wantPullCommits(t, path, []PullCommit{pullCommit(), other})
}

// TestPullCommitsAreWrittenByPullRequestThenOldestFirstAndKeepNoAuthor: the
// new lines go by repository, number, author date, SHA; an empty author is
// an empty column.
func TestPullCommitsAreWrittenByPullRequestThenOldestFirstAndKeepNoAuthor(t *testing.T) {
	path := filepath.Join(t.TempDir(), "pull_commits.csv")
	late, early, later := pullCommit(), pullCommit(), pullCommit()
	late.SHA, late.AuthoredAt = "6666666666666666666666666666666666666666", late.AuthoredAt.Add(time.Hour)
	early.Author = ""
	later.Number = 46
	if n, err := AppendPullCommits(path, []PullCommit{later, late, early}); err != nil || n != 3 {
		t.Fatalf("want 3 lines written, got %d, %v", n, err)
	}
	wantFile(t, path, pullCommitsHead+
		"acme/app,45,"+pullCommitSHA+",,2026-09-01T07:00:00Z\n"+
		"acme/app,45,6666666666666666666666666666666666666666,acme-dev,2026-09-01T08:00:00Z\n"+
		"acme/app,46,"+pullCommitSHA+",acme-dev,2026-09-01T07:00:00Z\n")
}

// TestAPullCommitThatCannotBeStoredIsRefused: each broken field is refused,
// naming it; an author that is an email address is no login.
func TestAPullCommitThatCannotBeStoredIsRefused(t *testing.T) {
	for name, c := range map[string]struct {
		spoil func(*PullCommit)
		word  string
	}{
		"repository": {func(p *PullCommit) { p.Repository = "app" }, "repository"},
		"number":     {func(p *PullCommit) { p.Number = 0 }, "number"},
		"sha":        {func(p *PullCommit) { p.SHA = "abc" }, "sha"},
		"author":     {func(p *PullCommit) { p.Author = "dev@acme.example" }, "author"},
		"time":       {func(p *PullCommit) { p.AuthoredAt = time.Time{} }, "authored_at"},
		"fraction":   {func(p *PullCommit) { p.AuthoredAt = p.AuthoredAt.Add(time.Millisecond) }, "authored_at"},
	} {
		t.Run(name, func(t *testing.T) {
			p := pullCommit()
			c.spoil(&p)
			n, err := AppendPullCommits(filepath.Join(t.TempDir(), "pull_commits.csv"), []PullCommit{p})
			if n != 0 || !refusedFor(err, c.word) {
				t.Errorf("want %s refused, got %d, %v", c.word, n, err)
			}
		})
	}
}

// TestAMalformedPullCommitsFileIsRefusedOnRead: a bad time names its line.
func TestAMalformedPullCommitsFileIsRefusedOnRead(t *testing.T) {
	path := filepath.Join(t.TempDir(), "pull_commits.csv")
	writeAt(t, path, pullCommitsHead+"acme/app,45,"+pullCommitSHA+",acme-dev,yesterday\n")
	if _, err := LoadPullCommits(path); !malformedOn(err, 3, "authored_at") {
		t.Errorf("want line 3 refused for authored_at, got %v", err)
	}
	writeAt(t, path, pullCommitsHead+"acme/app,forty,"+pullCommitSHA+",acme-dev,2026-09-01T07:00:00Z\n")
	if _, err := LoadPullCommits(path); !malformedOn(err, 3, "number") {
		t.Errorf("want line 3 refused for number, got %v", err)
	}
}
