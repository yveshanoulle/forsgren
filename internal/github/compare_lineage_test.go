package github

import (
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"
)

// shaFeature is a commit of another line of history, below shaMiddle in
// SHA order, so a sorted list of parents is not GitHub's order.
const shaFeature = "0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f"

// authoredJSON is the git author of a commit as GitHub gives it, authored on
// 2026-09-03 at 07:00.
const authoredJSON = `"author": {"name": "Acme Dev", "email": "dev@acme.example", "date": "2026-09-03T07:00:00Z"}`

// answerEntry is one commit of a comparison answer: its SHA, the fields of
// its git commit object (commit) and its parents, each as given.
type answerEntry struct{ sha, commit, parents string }

// json is the commit as GitHub's answer holds it.
func (e answerEntry) json() string {
	return `{"sha": "` + e.sha + `", "commit": {` + e.commit + `, "message": "More"}, "parents": ` + e.parents + `}`
}

// parentsJSON is the parents of a commit as GitHub lists them, in order.
func parentsJSON(shas ...string) string {
	parents := make([]string, 0, len(shas))
	for _, sha := range shas {
		parents = append(parents, `{"sha": "`+sha+`", "url": "https://api.github.com/repos/acme/app/commits/`+sha+`"}`)
	}
	return "[" + strings.Join(parents, ", ") + "]"
}

// answerOf is a whole comparison, ahead, of the commits given.
func answerOf(entries ...answerEntry) string {
	commits := make([]string, 0, len(entries))
	for _, e := range entries {
		commits = append(commits, e.json())
	}
	n := strconv.Itoa(len(commits))
	return `{"status": "ahead", "ahead_by": ` + n + `, "behind_by": 0, "total_commits": ` + n +
		`, "commits": [` + strings.Join(commits, ", ") + `], "files": []}`
}

// sameCommit says whether a and b agree on every field.
func sameCommit(a, b Commit) bool {
	return a.SHA == b.SHA && a.AuthoredAt.Equal(b.AuthoredAt) && a.Author == b.Author &&
		slices.Equal(a.Parents, b.Parents) && a.CommittedAt.Equal(b.CommittedAt)
}

// compareOne runs Compare on an answer and fails unless it read the commits.
func compareOne(t *testing.T, body string) []Commit {
	t.Helper()
	f := newFake(t)
	f.on(comparePath, reply{body: body})
	got, _, err := compare(f.client(t, DefaultMaxPages), shaBase, shaHead)
	if err != nil {
		t.Fatalf("want the commits, got %v", err)
	}
	return got
}

// TestCompareReadsTheParentsInOrder (forsgren#254): each commit's parents
// are the SHAs of GitHub's parents list in its order, the first parent first,
// as a merge records them (the line merged into, then the line merged): never
// sorted, never reversed. A root commit has none.
func TestCompareReadsTheParentsInOrder(t *testing.T) {
	got := compareOne(t, answerOf(
		answerEntry{shaMiddle, authoredJSON, parentsJSON(shaBase)},
		answerEntry{shaFeature, authoredJSON, parentsJSON()},
		answerEntry{shaHead, authoredJSON, parentsJSON(shaMiddle, shaFeature)},
	))
	want := [][]string{{shaBase}, nil, {shaMiddle, shaFeature}}
	if len(got) != len(want) {
		t.Fatalf("want %d commits, got %v", len(want), got)
	}
	for i, c := range got {
		if !slices.Equal(c.Parents, want[i]) {
			t.Errorf("%s: want the parents %q, got %q", c.SHA, want[i], c.Parents)
		}
	}
}

// TestCompareReadsTheCommitterDate (forsgren#254): CommittedAt is the git
// committer date (commit.committer.date) in UTC, which a rebase or the merge
// button sets, and never the author date. GitHub's schema lets the committer
// be null; a commit without a committer date has a zero CommittedAt, unknown,
// and is still read with its author date.
func TestCompareReadsTheCommitterDate(t *testing.T) {
	for name, tc := range map[string]committerCase{
		"a later committer": {`"committer": {"name": "GitHub", "email": "noreply@github.com", ` +
			`"date": "2026-09-04T10:15:00+02:00"}`, at(4, 8, 15, 0)},
		"a null committer":  {`"committer": null`, time.Time{}},
		"no committer":      {``, time.Time{}},
		"no committer date": {`"committer": {"name": "GitHub", "email": "noreply@github.com", "date": null}`, time.Time{}},
	} {
		t.Run(name, func(t *testing.T) { wantCommittedAt(t, tc) })
	}
}

// committerCase is a committer as a commit's git commit object gives it
// (none when empty) and the committer date Compare must read from it.
type committerCase struct {
	committer string
	want      time.Time
}

// wantCommittedAt fails unless a commit with tc's committer is read with
// tc's committer date, in UTC, and keeps its author date and parent.
func wantCommittedAt(t *testing.T, tc committerCase) {
	t.Helper()
	commit := authoredJSON
	if tc.committer != "" {
		commit += ", " + tc.committer
	}
	got := compareOne(t, answerOf(answerEntry{shaMiddle, commit, parentsJSON(shaBase)}))
	want := Commit{SHA: shaMiddle, AuthoredAt: at(3, 7, 0, 0), Parents: []string{shaBase}, CommittedAt: tc.want}
	if len(got) != 1 || !sameCommit(got[0], want) {
		t.Fatalf("want %v, got %v", want, got)
	}
	if got[0].CommittedAt.Location() != time.UTC {
		t.Errorf("want the committer date in UTC, got %v", got[0].CommittedAt.Location())
	}
}
