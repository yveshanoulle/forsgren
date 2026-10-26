package github

import (
	"context"
	"slices"
	"strconv"
	"testing"
)

// pullCommitsOf is PullCommits of pull request 45 of acme/app on the fake,
// read up to maxPages pages, failing the test on an error.
func pullCommitsOf(t *testing.T, f *fakeGitHub, maxPages int) ([]PullCommit, bool) {
	t.Helper()
	got, cut, err := f.client(t, maxPages).PullCommits(context.Background(), "acme/app", 45)
	if err != nil {
		t.Fatalf("want the commits, got %v", err)
	}
	return got, cut
}

// TestPullCommitsReturnsEveryCommitWithItsLoginAndAuthorDate (forsgren#463,
// step 5): every page is read, each commit gives its SHA, the login of
// GitHub's top-level author (null or missing is empty, never the name or
// email of commit.author) and the git author date in UTC, in the list's
// order.
func TestPullCommitsReturnsEveryCommitWithItsLoginAndAuthorDate(t *testing.T) {
	f := newFake(t)
	f.on(pullCommitsPath, reply{header: next(pullCommitsPath, "2"), body: fixture(t, "pull-commits.json")})
	f.onPage(pullCommitsPath, "2", reply{body: pullCommitItems(1, "2026-07-27T22:00:00+02:00")})
	got, cut := pullCommitsOf(t, f, DefaultMaxPages)
	want := []PullCommit{
		{SHA: "4545454545454545454545454545454545454501", Author: "acme-dev", AuthoredAt: utcOf(t, "2026-07-28T10:00:00Z")},
		{SHA: "4545454545454545454545454545454545454502", AuthoredAt: utcOf(t, "2026-07-29T07:00:00Z")},
		{SHA: shaHead, AuthoredAt: utcOf(t, "2026-07-27T20:00:00Z")},
	}
	if !slices.Equal(got, want) {
		t.Errorf("want %v, got %v", want, got)
	}
	if cut {
		t.Error("want an uncut answer")
	}
}

// wantCommitsCut holds PullCommits of the fake, read up to maxPages pages,
// to count commits and the cut flag.
func wantCommitsCut(t *testing.T, f *fakeGitHub, maxPages, count int, cut bool) {
	t.Helper()
	got, truncated := pullCommitsOf(t, f, maxPages)
	if len(got) != count || truncated != cut {
		t.Errorf("want %d commits, cut=%v, got %d, cut=%v", count, cut, len(got), truncated)
	}
}

// TestPullCommitsIsCutAtGitHubsCapOfTheList: 250 commits read is a cut
// answer that still returns what was read; 249 is complete.
func TestPullCommitsIsCutAtGitHubsCapOfTheList(t *testing.T) {
	for last, cut := range map[int]bool{49: false, 50: true} {
		f := newFake(t)
		f.on(pullCommitsPath, reply{header: next(pullCommitsPath, "2"), body: pullCommitItems(100, "2026-07-30T08:00:00Z")})
		f.onPage(pullCommitsPath, "2", reply{header: next(pullCommitsPath, "3"),
			body: pullCommitItems(100, "2026-07-30T08:00:00Z")})
		f.onPage(pullCommitsPath, "3", reply{body: pullCommitItems(last, "2026-07-29T08:00:00Z")})
		t.Run(strconv.Itoa(200+last), func(t *testing.T) { wantCommitsCut(t, f, DefaultMaxPages, 200+last, cut) })
	}
}

// TestPullCommitsIsCutAtThePageLimit: a next page left unread at the limit
// is a cut answer that still returns the page read.
func TestPullCommitsIsCutAtThePageLimit(t *testing.T) {
	f := newFake(t)
	f.on(pullCommitsPath, reply{header: next(pullCommitsPath, "2"), body: fixture(t, "pull-commits.json")})
	wantCommitsCut(t, f, 1, 2, true)
}
