package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// The fill marks reach the page data (forsgren#470, step 3, decision #484 A),
// read beside the history like the other mark files.

const (
	pullCommitsFilledH = "# forsgren pull commits filled v1\nrepository,filled_at\n"
	pushCommitsFilledH = "# forsgren push commits filled v1\nrepository,filled_at\n"
)

// writeUnlistedPull writes, beside the history at data, the pull request 5 of
// acme/api merged in the window with no line in pull_commits.csv, which sets
// note 7 (Filling) until the fill of its repository is done.
func writeUnlistedPull(t *testing.T, data string) {
	t.Helper()
	merged := time.Date(2026, 10, 2, 10, 0, 0, 0, time.UTC)
	pull := history.PullRequest{Repository: "acme/api", Number: 5, CreatedAt: merged.Add(-4 * time.Hour),
		MergedAt: merged, MergeCommit: pushShaCommit, UpdatedAt: merged, FirstCommitAt: merged.Add(-3 * time.Hour),
		Bot: history.ByHuman}
	if _, err := history.AppendPullRequests(filepath.Join(filepath.Dir(data), "pulls.csv"),
		[]history.PullRequest{pull}); err != nil {
		t.Fatal(err)
	}
}

// writeMark writes the mark file name with content beside the history at data.
func writeMark(t *testing.T, data, name, content string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(filepath.Dir(data), name), []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}

// TestRenderReadsThePullCommitsFilledMarkAndNote7Goes: a merged pull request
// without pull commits keeps note 7 for its project until its repository is
// in pull_commits_filled.csv beside --data, ignoring case; a missing file
// marks none; the push fill's mark does not stand in for it.
func TestRenderReadsThePullCommitsFilledMarkAndNote7Goes(t *testing.T) {
	for name, c := range map[string]struct {
		file, content string
		filling       bool
	}{
		"no mark file":       {"", "", true},
		"filled":             {"pull_commits_filled.csv", pullCommitsFilledH + "acme/api,2026-10-02T00:00:00Z\n", false},
		"filled, other case": {"pull_commits_filled.csv", pullCommitsFilledH + "ACME/Api,2026-10-02T00:00:00Z\n", false},
		"another repository": {"pull_commits_filled.csv", pullCommitsFilledH + "acme/cli,2026-10-02T00:00:00Z\n", true},
		"the push mark":      {"push_commits_filled.csv", pushCommitsFilledH + "acme/api,2026-10-02T00:00:00Z\n", true},
	} {
		t.Run(name, func(t *testing.T) {
			data := writeHistory(t, acmeHistory())
			writePushes(t, data)
			writeUnlistedPull(t, data)
			if c.file != "" {
				writeMark(t, data, c.file, c.content)
			}
			if got := pushData(t, data).TbdMetrics[0].MainLead.Filling; got != c.filling {
				t.Errorf("want Filling %v, got %v", c.filling, got)
			}
		})
	}
}

// TestRenderReadsThePushCommitsFilledMark: a merge push's line of unknown
// parents keeps note 7 until its repository is in push_commits_filled.csv.
func TestRenderReadsThePushCommitsFilledMark(t *testing.T) {
	for name, filled := range map[string]bool{"not filled": false, "filled": true} {
		t.Run(name, func(t *testing.T) {
			data := writeHistory(t, acmeHistory())
			writeMergePushOfUnknownParents(t, data)
			if filled {
				writeMark(t, data, "push_commits_filled.csv", pushCommitsFilledH+"acme/api,2026-10-02T00:00:00Z\n")
			}
			if got := pushData(t, data).TbdMetrics[0].MainLead.Filling; got != !filled {
				t.Errorf("want Filling %v, got %v", !filled, got)
			}
		})
	}
}

// writeMergePushOfUnknownParents writes a pr_merge push of acme/api in the
// window with one line of unknown parents.
func writeMergePushOfUnknownParents(t *testing.T, data string) {
	t.Helper()
	push := history.Push{Repository: "acme/api", PushedAt: time.Date(2026, 10, 2, 10, 0, 0, 0, time.UTC),
		Before: pushShaBefore, After: pushShaAfter, Kind: history.PushKindPRMerge, Bot: history.ByHuman, Commits: 1}
	commit := history.PushCommit{Repository: "acme/api", After: pushShaAfter, SHA: pushShaCommit,
		Author: "acme-dev", AuthoredAt: push.PushedAt.Add(-25 * time.Minute), FirstParent: true,
		Parents: history.ParentsUnknown}
	dir := filepath.Dir(data)
	if _, err := history.AppendPushes(filepath.Join(dir, "pushes.csv"), []history.Push{push}); err != nil {
		t.Fatal(err)
	}
	commits := filepath.Join(dir, "push_commits.csv")
	if _, err := history.AppendPushCommits(commits, []history.PushCommit{commit}); err != nil {
		t.Fatal(err)
	}
}

// TestRenderRefusesABadFillMarkFile: a malformed or unknown-version fill mark
// fails render, naming it, as the other mark files do.
func TestRenderRefusesABadFillMarkFile(t *testing.T) {
	wantBadFileRefused(t, "pull_commits_filled.csv", map[string]badFile{
		"unknown version": {"# forsgren pull commits filled v2\n", "unknown history format version"},
		"malformed line":  {pullCommitsFilledH + "acme/api\n", "line 3: malformed history"},
	})
	wantBadFileRefused(t, "push_commits_filled.csv", map[string]badFile{
		"unknown version": {"# forsgren push commits filled v2\n", "unknown history format version"},
		"malformed line":  {pushCommitsFilledH + "acme/api\n", "line 3: malformed history"},
	})
}
