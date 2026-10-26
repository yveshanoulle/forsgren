package history

import (
	"path/filepath"
	"slices"
	"testing"
	"time"
)

const (
	pushCommitsHead = "# forsgren push commits v2\nrepository,after,sha,author,authored_at,first_parent,parents\n"
	// pushCommitsHeadV1 and pushCommitLineV1 are the format v1, before the
	// first_parent and parents columns (forsgren#463, step 3).
	pushCommitsHeadV1 = "# forsgren push commits v1\nrepository,after,sha,author,authored_at\n"
	pushCommitLineV1  = "acme/app," + pushAfter + "," + pushCommitSHA + ",acme-dev,2026-09-02T08:30:00Z\n"
	pushCommitSHA     = "3333333333333333333333333333333333333333"
	pushCommitLine    = "acme/app," + pushAfter + "," + pushCommitSHA + ",acme-dev,2026-09-02T08:30:00Z,true,1\n"
)

// pushCommit is a commit of the push that ended at pushAfter, by acme-dev,
// authored at 08:30 on 2026-09-02.
func pushCommit() PushCommit {
	return PushCommit{Repository: "acme/app", After: pushAfter, SHA: pushCommitSHA, Author: "acme-dev",
		AuthoredAt: time.Date(2026, 9, 2, 8, 30, 0, 0, time.UTC), FirstParent: true, Parents: 1}
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
		"acme/app,"+pushAfter+","+pushCommitSHA+",,2026-09-02T08:30:00Z,true,1\n"+
		"acme/app,"+pushAfter+",4444444444444444444444444444444444444444,acme-dev,2026-09-02T09:30:00Z,true,1\n")
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
		"parents":    {func(p *PushCommit) { p.Parents = -2 }, "parents"},
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
	writeAt(t, path, pushCommitsHead+"acme/app,"+pushAfter+","+pushCommitSHA+",acme-dev,yesterday,true,1\n")
	if _, err := LoadPushCommits(path); !malformedOn(err, 3, "authored_at") {
		t.Errorf("want line 3 refused for authored_at, got %v", err)
	}
}

// TestAPushCommitKeepsItsFirstParentFlagAndParentCount (forsgren#463, step
// 3): format v2 round-trips false and true, a root commit's 0 parents, a
// merge's 2, and unknown parents as an empty column.
func TestAPushCommitKeepsItsFirstParentFlagAndParentCount(t *testing.T) {
	path := filepath.Join(t.TempDir(), "push_commits.csv")
	root, merge, unknown := pushCommit(), pushCommit(), pushCommit()
	root.SHA, root.FirstParent, root.Parents = "4444444444444444444444444444444444444444", false, 0
	merge.SHA, merge.AuthoredAt = "5555555555555555555555555555555555555555", merge.AuthoredAt.Add(time.Hour)
	merge.Parents = 2
	unknown.SHA, unknown.AuthoredAt = "6666666666666666666666666666666666666666", unknown.AuthoredAt.Add(2*time.Hour)
	unknown.Parents = ParentsUnknown
	if n, err := AppendPushCommits(path, []PushCommit{root, merge, unknown}); err != nil || n != 3 {
		t.Fatalf("want 3 lines written, got %d, %v", n, err)
	}
	wantFile(t, path, pushCommitsHead+
		"acme/app,"+pushAfter+",4444444444444444444444444444444444444444,acme-dev,2026-09-02T08:30:00Z,false,0\n"+
		"acme/app,"+pushAfter+",5555555555555555555555555555555555555555,acme-dev,2026-09-02T09:30:00Z,true,2\n"+
		"acme/app,"+pushAfter+",6666666666666666666666666666666666666666,acme-dev,2026-09-02T10:30:00Z,true,\n")
	wantPushCommits(t, path, []PushCommit{root, merge, unknown})
}

// TestAV1PushCommitsFileIsReadAsFirstParentWithUnknownParents: a v1 line is on
// the chain, its parents unknown; the first append rewrites the file as v2,
// unknown kept unknown.
func TestAV1PushCommitsFileIsReadAsFirstParentWithUnknownParents(t *testing.T) {
	path := filepath.Join(t.TempDir(), "push_commits.csv")
	writeAt(t, path, pushCommitsHeadV1+pushCommitLineV1)
	old := pushCommit()
	old.Parents = ParentsUnknown
	wantPushCommits(t, path, []PushCommit{old})
	next := pushCommit()
	next.SHA, next.AuthoredAt = "4444444444444444444444444444444444444444", next.AuthoredAt.Add(time.Hour)
	if n, err := AppendPushCommits(path, []PushCommit{next}); err != nil || n != 1 {
		t.Fatalf("want 1 line written, got %d, %v", n, err)
	}
	wantFile(t, path, pushCommitsHead+
		"acme/app,"+pushAfter+","+pushCommitSHA+",acme-dev,2026-09-02T08:30:00Z,true,\n"+
		"acme/app,"+pushAfter+",4444444444444444444444444444444444444444,acme-dev,2026-09-02T09:30:00Z,true,1\n")
}

// TestAPushCommitsFileWithABadFirstParentOrParentsIsRefusedOnRead names the
// line and the column.
func TestAPushCommitsFileWithABadFirstParentOrParentsIsRefusedOnRead(t *testing.T) {
	base := "acme/app," + pushAfter + "," + pushCommitSHA + ",acme-dev,2026-09-02T08:30:00Z,"
	for name, c := range map[string]struct{ tail, word string }{
		"first_parent": {"yes,1\n", "first_parent"},
		"negative":     {"true,-1\n", "parents"},
		"word":         {"true,two\n", "parents"},
	} {
		t.Run(name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "push_commits.csv")
			writeAt(t, path, pushCommitsHead+base+c.tail)
			if _, err := LoadPushCommits(path); !malformedOn(err, 3, c.word) {
				t.Errorf("want line 3 refused for %s, got %v", c.word, err)
			}
		})
	}
}
