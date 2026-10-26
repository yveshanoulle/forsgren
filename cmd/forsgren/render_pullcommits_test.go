package main

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// The pull commits reach the page data (forsgren#463, step 9), read beside the
// history like pulls.csv.

const pullCommitsH = "# forsgren pull commits v1\nrepository,number,sha,author,authored_at\n"

const (
	pullShaOne = "4444444444444444444444444444444444444444"
	pullShaTwo = "5555555555555555555555555555555555555555"
)

// writeSquash writes, beside the history at data, the pull request 5 of
// acme/api whose merge commit is the one commit of writePushes' push, and its
// two commits, authored 3 hours and 1 hour before that push.
func writeSquash(t *testing.T, data string) {
	t.Helper()
	dir := filepath.Dir(data)
	merged := time.Date(2026, 10, 2, 10, 0, 0, 0, time.UTC)
	pull := history.PullRequest{Repository: "acme/api", Number: 5, CreatedAt: merged.Add(-4 * time.Hour),
		MergedAt: merged, MergeCommit: pushShaCommit, UpdatedAt: merged, FirstCommitAt: merged.Add(-3 * time.Hour),
		Bot: history.ByHuman}
	if _, err := history.AppendPullRequests(filepath.Join(dir, "pulls.csv"), []history.PullRequest{pull}); err != nil {
		t.Fatal(err)
	}
	commit := func(sha string, before time.Duration) history.PullCommit {
		return history.PullCommit{Repository: "acme/api", Number: 5, SHA: sha, Author: "acme-dev",
			AuthoredAt: merged.Add(-before)}
	}
	commits := []history.PullCommit{commit(pullShaOne, 3*time.Hour), commit(pullShaTwo, time.Hour)}
	if _, err := history.AppendPullCommits(filepath.Join(dir, "pull_commits.csv"), commits); err != nil {
		t.Fatal(err)
	}
}

// TestRenderReadsThePullCommitsBesideTheHistory: with pull_commits.csv beside
// --data, the squash commit of pull request 5 is replaced by its two commits in
// the Mainline Lead Time of Acme Shop (2 h from their author dates to the
// push, not the 25 minutes of the squash commit).
func TestRenderReadsThePullCommitsBesideTheHistory(t *testing.T) {
	data := writeHistory(t, acmeHistory())
	writePushes(t, data)
	writeSquash(t, data)
	got := pushData(t, data).TbdMetrics[0].MainLead
	want := metrics.DurationSpread{Count: 2, Mean: 2 * time.Hour}
	if got.Squashed != 2 || got.Commits != 2 || got.Lead.Mean != want.Mean {
		t.Errorf("want 2 squashed commits of mean 2h, got %+v", got)
	}
}

// TestRenderShowsTheMainlineLeadTimeOfASquashOnTheTbdPage: Acme Shop's cells
// of the new group, right before Time to main, are the two commits' 2 h mean
// and median, while Time to main keeps the squash commit's 25 min; the group
// has its header.
func TestRenderShowsTheMainlineLeadTimeOfASquashOnTheTbdPage(t *testing.T) {
	pinNow(t)
	data := writeData(t, acmeHistory(), acmeCommits())
	writePushes(t, data)
	writeSquash(t, data)
	wantIn(t, tbdSiteOf(t, validConfig, data), `<th scope="colgroup" colspan="3">Mainline Lead Time</th>`,
		tdRow("2 h", "2 h", "-")+"\n            "+tdRow("25 m", "-", "-"))
}

// TestRenderRefusesABadPullCommitsFile: a malformed or unknown-version pull
// commits file fails render with its own message, naming it; never read as
// none.
func TestRenderRefusesABadPullCommitsFile(t *testing.T) {
	wantBadFileRefused(t, "pull_commits.csv", map[string]badFile{
		"unknown version": {"# forsgren pull commits v2\n", "unknown history format version"},
		"malformed line":  {pullCommitsH + "acme/api,x\n", "line 3: malformed history"},
	})
}
