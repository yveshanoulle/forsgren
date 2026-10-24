package history

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"testing"
	"time"
)

// landedAs is c with the author, parents and committer date GitHub gives.
func landedAs(c Commit, author string, committed time.Time, parents ...string) Commit {
	c.Author, c.Parents, c.CommittedAt = author, parents, committed
	return c
}

// textOf is the content of the file at path, empty when it cannot be read.
func textOf(path string) string {
	data, _ := os.ReadFile(filepath.Clean(path))
	return string(data)
}

// TestLegacyIsACommitWithNeitherParentsNorACommitterDate (forsgren#385): the
// author does not matter, a v2 line is legacy too; a parent or a committer
// date makes a commit current.
func TestLegacyIsACommitWithNeitherParentsNorACommitterDate(t *testing.T) {
	stored := cmt(1001, sha1, 0)
	cases := map[string]struct {
		c    Commit
		want bool
	}{
		"stored": {stored, true},
		"author": {landedAs(stored, "ada-dev", time.Time{}), true},
		"parent": {landedAs(stored, "", time.Time{}, sha3), false},
		"date":   {landedAs(stored, "", day), false},
	}
	for name, tc := range cases {
		if got := tc.c.Legacy(); got != tc.want {
			t.Errorf("%s: want Legacy %v, got %v", name, tc.want, got)
		}
	}
}

// TestBackfillCommitsFillsOnlyTheEmptyColumnsOfLegacyLines (forsgren#385): a
// legacy line gets the parents and the committer date, and the author when it
// has none; a commit GitHub links to no account keeps an empty login; a line
// that is not legacy, and a legacy line the known commits do not name, stay as
// they are; the order of the lines is the file's.
func TestBackfillCommitsFillsOnlyTheEmptyColumnsOfLegacyLines(t *testing.T) {
	path := commitsPath(t)
	current := merge()
	v2 := landedAs(cmt(1001, sha3, 2), "ada-dev", time.Time{})
	mustAppendCommits(t, path, cmt(1001, sha1, 0), cmt(1001, sha2, 1), v2, current, cmt(1003, sha1, 3))
	stamp := day.Add(time.Hour)
	known := []Commit{
		landedAs(cmt(1001, sha1, 0), "ada-dev", stamp, sha3),
		landedAs(cmt(1001, sha2, 1), "", stamp, sha1),
		landedAs(cmt(1001, sha3, 2), "someone-else", stamp, sha1),
		landedAs(current, "someone-else", stamp, sha1),
	}
	changed, err := BackfillCommits(path, known)
	if err != nil || changed != 3 {
		t.Fatalf("want 3 lines changed, got %d, %v", changed, err)
	}
	want := []Commit{
		landedAs(cmt(1001, sha1, 0), "ada-dev", stamp, sha3), landedAs(cmt(1001, sha2, 1), "", stamp, sha1),
		landedAs(v2, "ada-dev", stamp, sha1), inUTC(current), cmt(1003, sha1, 3),
	}
	same := func(a, b Commit) bool { return reflect.DeepEqual(a, b) }
	if got := mustLoadCommits(t, path); !slices.EqualFunc(got, want, same) {
		t.Errorf("want the commits\n%v\ngot\n%v", want, got)
	}
}

// TestBackfillCommitsWithNothingToFillWritesNothing (forsgren#385): the file
// keeps its bytes and its modification time when no line changes, also when
// the known commits are unrelated or a root commit gives nothing.
func TestBackfillCommitsWithNothingToFillWritesNothing(t *testing.T) {
	path := writeFile(t, commitsHead+commitLine)
	before, _ := os.Stat(path)
	root := cmt(1001, sha1, 0)
	changed, err := BackfillCommits(path, []Commit{root, landedAs(cmt(1002, sha2, 1), "ada-dev", day, sha1)})
	if err != nil || changed != 0 {
		t.Fatalf("want nothing changed, got %d, %v", changed, err)
	}
	after, _ := os.Stat(path)
	if !after.ModTime().Equal(before.ModTime()) {
		t.Errorf("want the file untouched, modified at %v", after.ModTime())
	}
}

// TestBackfillCommitsWritesAnOlderFileInTheCurrentVersion (forsgren#385): a
// v1 file is lifted to v3 by the backfill, its lines kept, even when no line
// changes.
func TestBackfillCommitsWritesAnOlderFileInTheCurrentVersion(t *testing.T) {
	path := v1File(t, commitLineV1)
	if _, err := BackfillCommits(path, nil); err != nil {
		t.Fatal(err)
	}
	if got := textOf(path); got != commitsHead+commitLine {
		t.Errorf("want the file as v3, got\n%s", got)
	}
}

// TestBackfillCommitsOfAMissingFileIsNothingToFill (forsgren#385): no file is
// created.
func TestBackfillCommitsOfAMissingFileIsNothingToFill(t *testing.T) {
	path := commitsPath(t)
	changed, err := BackfillCommits(path, []Commit{cmt(1001, sha1, 0)})
	if err != nil || changed != 0 {
		t.Fatalf("want nothing filled and no error, got %d, %v", changed, err)
	}
	if _, err := os.Stat(path); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("want no file created, got %v", err)
	}
}

// TestBackfillCommitsRefusesWhatItCannotStoreOrRead (forsgren#385): a known
// commit that cannot be stored, and a file that is malformed, are refused
// with the file untouched.
func TestBackfillCommitsRefusesWhatItCannotStoreOrRead(t *testing.T) {
	path := writeFile(t, commitsHead+commitLine)
	bad := landedAs(cmt(1001, sha1, 0), "not a login", day, sha3)
	if _, err := BackfillCommits(path, []Commit{bad}); !errors.Is(err, ErrInvalidRecord) {
		t.Errorf("want ErrInvalidRecord, got %v", err)
	}
	broken := writeFile(t, commitsHead+"not a line\n")
	if _, err := BackfillCommits(broken, nil); err == nil {
		t.Errorf("want a malformed file refused")
	}
	if got := textOf(path); got != commitsHead+commitLine {
		t.Errorf("want the file untouched, got\n%s", got)
	}
}
