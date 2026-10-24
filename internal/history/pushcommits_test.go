package history

import (
	"path/filepath"
	"slices"
	"testing"
	"time"
)

const (
	pushCommitsHead = "# forsgren push commits v1\nrepository,after,sha,author,authored_at\n"
	pushCommitSHA   = "3333333333333333333333333333333333333333"
	pushCommitLine  = "acme/app," + pushAfter + "," + pushCommitSHA + ",acme-dev,2026-09-02T08:30:00Z\n"
)

// pushCommit is a commit of the push that ended at pushAfter, by acme-dev,
// authored at 08:30 on 2026-09-02.
func pushCommit() PushCommit {
	return PushCommit{Repository: "acme/app", After: pushAfter, SHA: pushCommitSHA, Author: "acme-dev",
		AuthoredAt: time.Date(2026, 9, 2, 8, 30, 0, 0, time.UTC)}
}

// TestAPushCommitIsWrittenOnceByRepositoryAfterAndSHA (forsgren#397, step
// 3): data/push_commits.csv is created with its version and column lines; a
// commit already held (repository ignoring case, after SHA and commit SHA)
// is not written again, whatever else it says.
func TestAPushCommitIsWrittenOnceByRepositoryAfterAndSHA(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data", "push_commits.csv")
	if n, err := AppendPushCommits(path, []PushCommit{pushCommit()}); err != nil || n != 1 {
		t.Fatalf("want 1 line written, got %d, %v", n, err)
	}
	again := pushCommit()
	again.Repository, again.Author = "ACME/app", "someone-else"
	if n, err := AppendPushCommits(path, []PushCommit{again}); err != nil || n != 0 {
		t.Errorf("want the held commit skipped, got %d, %v", n, err)
	}
	wantFile(t, path, pushCommitsHead+pushCommitLine)
	wantPushCommits(t, path, []PushCommit{pushCommit()})
}

// wantPushCommits fails unless the push commits at path are want.
func wantPushCommits(t *testing.T, path string, want []PushCommit) {
	t.Helper()
	got, err := LoadPushCommits(path)
	if err != nil || !slices.Equal(got, want) {
		t.Errorf("want %v, got %v, %v", want, got, err)
	}
}

// TestPushCommitsAreWrittenOldestFirstAndKeepNoAuthor: the new lines of a
// push go by author date then SHA; an empty author is an empty column.
func TestPushCommitsAreWrittenOldestFirstAndKeepNoAuthor(t *testing.T) {
	path := filepath.Join(t.TempDir(), "push_commits.csv")
	late, early := pushCommit(), pushCommit()
	late.SHA, late.AuthoredAt = "4444444444444444444444444444444444444444", late.AuthoredAt.Add(time.Hour)
	early.Author = ""
	if n, err := AppendPushCommits(path, []PushCommit{late, early}); err != nil || n != 2 {
		t.Fatalf("want 2 lines written, got %d, %v", n, err)
	}
	wantFile(t, path, pushCommitsHead+
		"acme/app,"+pushAfter+","+pushCommitSHA+",,2026-09-02T08:30:00Z\n"+
		"acme/app,"+pushAfter+",4444444444444444444444444444444444444444,acme-dev,2026-09-02T09:30:00Z\n")
}

// TestAPushCommitThatCannotBeStoredIsRefused: each broken field is refused,
// naming it; an author that is an email address is no login.
func TestAPushCommitThatCannotBeStoredIsRefused(t *testing.T) {
	for name, c := range map[string]struct {
		spoil func(*PushCommit)
		word  string
	}{
		"repository": {func(p *PushCommit) { p.Repository = "app" }, "repository"},
		"after":      {func(p *PushCommit) { p.After = "abc" }, "after"},
		"sha":        {func(p *PushCommit) { p.SHA = "" }, "sha"},
		"author":     {func(p *PushCommit) { p.Author = "dev@acme.example" }, "author"},
		"time":       {func(p *PushCommit) { p.AuthoredAt = time.Time{} }, "authored_at"},
		"fraction":   {func(p *PushCommit) { p.AuthoredAt = p.AuthoredAt.Add(time.Millisecond) }, "authored_at"},
	} {
		t.Run(name, func(t *testing.T) {
			p := pushCommit()
			c.spoil(&p)
			n, err := AppendPushCommits(filepath.Join(t.TempDir(), "push_commits.csv"), []PushCommit{p})
			if n != 0 || !refusedFor(err, c.word) {
				t.Errorf("want %s refused, got %d, %v", c.word, n, err)
			}
		})
	}
}

// TestAMalformedPushCommitsFileIsRefusedOnRead: a bad time names its line.
func TestAMalformedPushCommitsFileIsRefusedOnRead(t *testing.T) {
	path := filepath.Join(t.TempDir(), "push_commits.csv")
	writeAt(t, path, pushCommitsHead+"acme/app,"+pushAfter+","+pushCommitSHA+",acme-dev,yesterday\n")
	if _, err := LoadPushCommits(path); !malformedOn(err, 3, "authored_at") {
		t.Errorf("want line 3 refused for authored_at, got %v", err)
	}
}
