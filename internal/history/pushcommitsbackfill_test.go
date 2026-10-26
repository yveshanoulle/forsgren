package history

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// The fill of the lines of a stored merge push (forsgren#470, step 2).

const (
	otherAfter  = "4444444444444444444444444444444444444444"
	branchSHA   = "5555555555555555555555555555555555555555"
	unknownLine = "acme/app," + pushAfter + "," + pushCommitSHA + ",acme-dev,2026-09-02T08:30:00Z,true,\n"
	otherLine   = "acme/app," + otherAfter + "," + pushCommitSHA + ",,2026-09-01T08:30:00Z,true,\n"
)

// currentLines are the lines of the push that ended at pushAfter as a compare
// gives them today: a branch commit off the chain and the merge commit.
func currentLines() []PushCommit {
	at := time.Date(2026, 9, 2, 8, 0, 0, 0, time.UTC)
	return []PushCommit{
		{Repository: "acme/app", After: pushAfter, SHA: pushCommitSHA, Author: "acme-dev",
			AuthoredAt: at.Add(30 * time.Minute), FirstParent: true, Parents: 2},
		{Repository: "acme/app", After: pushAfter, SHA: branchSHA, AuthoredAt: at, Parents: 1},
	}
}

// currentText is currentLines as the file writes them, oldest first.
const currentText = "acme/app," + pushAfter + "," + branchSHA + ",,2026-09-02T08:00:00Z,false,1\n" +
	"acme/app," + pushAfter + "," + pushCommitSHA + ",acme-dev,2026-09-02T08:30:00Z,true,2\n"

// writePushCommits writes text as the push commits file under a temporary
// directory and returns its path.
func writePushCommits(t *testing.T, text string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "push_commits.csv")
	if err := os.WriteFile(path, []byte(text), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

// TestBackfillPushCommitsReplacesThePushWhoseLinesHaveUnknownParents: the
// lines of a push with a line of unknown parents are replaced, in the place of
// the push's first line, by the known lines, oldest first; the lines of every
// other push, current or not, stay as they are.
func TestBackfillPushCommitsReplacesThePushWhoseLinesHaveUnknownParents(t *testing.T) {
	path := writePushCommits(t, pushCommitsHead+otherLine+unknownLine)
	changed, err := BackfillPushCommits(path, currentLines())
	if err != nil || changed != 1 {
		t.Fatalf("want 1 push replaced, got %d, %v", changed, err)
	}
	wantFile(t, path, pushCommitsHead+otherLine+currentText)
}

// TestBackfillPushCommitsLeavesAPushWithKnownParentsAlone: a push whose lines
// all have their parents known is not replaced, and nothing is written.
func TestBackfillPushCommitsLeavesAPushWithKnownParentsAlone(t *testing.T) {
	path := writePushCommits(t, pushCommitsHead+pushCommitLine)
	changed, err := BackfillPushCommits(path, currentLines())
	if err != nil || changed != 0 {
		t.Fatalf("want nothing replaced, got %d, %v", changed, err)
	}
	wantFile(t, path, pushCommitsHead+pushCommitLine)
}

// TestBackfillPushCommitsLeavesAPushItIsNotGivenAlone: a legacy push with no
// known lines keeps its own, whatever else was replaced.
func TestBackfillPushCommitsLeavesAPushItIsNotGivenAlone(t *testing.T) {
	path := writePushCommits(t, pushCommitsHead+otherLine+unknownLine)
	if changed, err := BackfillPushCommits(path, nil); err != nil || changed != 0 {
		t.Fatalf("want nothing replaced, got %d, %v", changed, err)
	}
	wantFile(t, path, pushCommitsHead+otherLine+unknownLine)
}

// TestBackfillPushCommitsWritesAV1FileOnceAsV2: a file of the version 1 is
// written whole in the current one even when no push is replaced, as the
// first append does.
func TestBackfillPushCommitsWritesAV1FileOnceAsV2(t *testing.T) {
	path := writePushCommits(t, pushCommitsHeadV1+pushCommitLineV1)
	if changed, err := BackfillPushCommits(path, nil); err != nil || changed != 0 {
		t.Fatalf("want nothing replaced, got %d, %v", changed, err)
	}
	wantFile(t, path, pushCommitsHead+unknownLine)
}

// TestBackfillPushCommitsOfAMissingFileIsNothing: a file that does not exist is
// not created.
func TestBackfillPushCommitsOfAMissingFileIsNothing(t *testing.T) {
	path := filepath.Join(t.TempDir(), "push_commits.csv")
	if changed, err := BackfillPushCommits(path, currentLines()); err != nil || changed != 0 {
		t.Fatalf("want nothing replaced, got %d, %v", changed, err)
	}
	if _, err := os.Stat(path); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("want no file created, got %v", err)
	}
}

// TestBackfillPushCommitsRefusesAKnownLineThatCannotBeStored: nothing is
// written when a known line is invalid.
func TestBackfillPushCommitsRefusesAKnownLineThatCannotBeStored(t *testing.T) {
	path := writePushCommits(t, pushCommitsHead+unknownLine)
	bad := currentLines()
	bad[0].SHA = "not-a-sha"
	if _, err := BackfillPushCommits(path, bad); !errors.Is(err, ErrInvalidRecord) {
		t.Errorf("want ErrInvalidRecord, got %v", err)
	}
	wantFile(t, path, pushCommitsHead+unknownLine)
}

// A push and the lines it brought share one tip, whatever the case of the
// repository's name, and a push that ended elsewhere has another
// (forsgren#470: the fill of collect finds its merge pushes by it).
func TestAPushHasTheTipOfItsLines(t *testing.T) {
	line := currentLines()[0]
	if got := (Push{Repository: "Acme/App", After: pushAfter}).Tip(); got != line.Tip() {
		t.Errorf("tip of the push = %v, want %v, the tip of its line", got, line.Tip())
	}
	if (Push{Repository: "acme/app", After: otherAfter}).Tip() == line.Tip() {
		t.Error("a push that ended at another SHA has the tip of the line")
	}
}
