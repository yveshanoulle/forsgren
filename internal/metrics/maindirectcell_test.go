package metrics

import (
	"fmt"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// TestMainlineDirectCell (forsgren#390, step 2): the median time to main and
// the count, "20 min (4)", then the note on the commits timed by author date
// as the Mainline Interval words it, plain from one and "Mostly estimated"
// above half; a dash without a direct commit.
func TestMainlineDirectCell(t *testing.T) {
	m := 20 * time.Minute
	cases := map[string]struct {
		direct MainlineDirect
		want   string
	}{
		"none":      {MainlineDirect{}, "-"},
		"all known": {MainlineDirect{Commits: 4, Median: m}, "20 min (4)"},
		"half legacy": {MainlineDirect{Commits: 4, Median: m, ByAuthorDate: 2},
			"20 min (4) · 2 commits timed by author date"},
		"most legacy": {MainlineDirect{Commits: 4, Median: m, ByAuthorDate: 3},
			"20 min (4) · Mostly estimated: 3 of 4 commits timed by author date."},
		"under a min":  {MainlineDirect{Commits: 1}, "less than 1 min (1)"},
		"a day and up": {MainlineDirect{Commits: 2, Median: 30 * time.Hour}, "1 d 6 h (2)"},
	}
	for name, c := range cases {
		if got := c.direct.Cell(); got != c.want {
			t.Errorf("%s: want %q, got %q", name, c.want, got)
		}
	}
}

// TestBatchSizeCell (forsgren#390, step 2): the median commits per deployment
// with its count of deployments, a half written as 1.5, then the deployments
// left out for want of a known lineage, in the singular and the plural; a
// dash without a deployment, the note still said.
func TestBatchSizeCell(t *testing.T) {
	cases := map[string]struct {
		batch BatchSize
		want  string
	}{
		"none":  {BatchSize{}, "-"},
		"whole": {BatchSize{Deployments: 45, Median: 2}, "2 (45)"},
		"half":  {BatchSize{Deployments: 45, Median: 1.5}, "1.5 (45)"},
		"one legacy": {BatchSize{Deployments: 2, Median: 3, Legacy: 1},
			"3 (2) · 1 deployment of unknown lineage not counted"},
		"only legacy": {BatchSize{Legacy: 3}, "- · 3 deployments of unknown lineage not counted"},
		"two legacy": {BatchSize{Deployments: 1, Median: 1, Legacy: 2},
			"1 (1) · 2 deployments of unknown lineage not counted"},
	}
	for name, c := range cases {
		if got := c.batch.Cell(); got != c.want {
			t.Errorf("%s: want %q, got %q", name, c.want, got)
		}
	}
}

// TestBatchSizeMedianOfAnOddCountIsTheMiddleOne (forsgren#390, step 2): three
// deployments of 1, 5 and 2 commits have a median of 2, and the deployments
// outside the DORA window are not counted.
func TestBatchSizeMedianOfAnOddCountIsTheMiddleOne(t *testing.T) {
	h := time.Hour
	commits := trunkCommits(1, 1, h)
	commits = append(commits, trunkCommits(2, 5, 2*h)...)
	commits = append(commits, trunkCommits(3, 2, 3*h)...)
	commits = append(commits, trunkCommits(4, 9, 40*24*h)...)
	got := BatchSizes(projects, Data{Commits: commits}, now)[0]
	if want := (BatchSize{Project: "Acme Shop", Deployments: 3, Median: 2}); got != want {
		t.Errorf("want %+v, got %+v", want, got)
	}
}

// TestDirectAndBatchLeaveOutARepositoryNoProjectLists (forsgren#390, step 2):
// a commit of a repository the config no longer lists belongs to no project,
// so it is in neither number.
func TestDirectAndBatchLeaveOutARepositoryNoProjectLists(t *testing.T) {
	gone := trunkCommit(1, "g1", time.Hour, time.Minute, "base")
	gone.Repository = "acme/gone"
	data := Data{Commits: []history.Commit{gone}}
	if got, want := MainlineDirects(projects, data, now)[0], (MainlineDirect{Project: "Acme Shop"}); got != want {
		t.Errorf("want no direct commit, got %+v", got)
	}
	if got, want := BatchSizes(projects, data, now)[0], (BatchSize{Project: "Acme Shop"}); got != want {
		t.Errorf("want no batch, got %+v", got)
	}
}

// trunkCommits are n commits of acme/app in the deployment id, deployed
// deployedAgo before now, each the parent of the next so the last is the tip
// of one first-parent chain.
func trunkCommits(id int64, n int, deployedAgo time.Duration) []history.Commit {
	commits := make([]history.Commit, n)
	for i := range commits {
		sha := fmt.Sprintf("t%d-%d", id, i)
		parent := "base"
		if i > 0 {
			parent = commits[i-1].SHA
		}
		commits[i] = trunkCommit(id, sha, deployedAgo, time.Minute, parent)
	}
	return commits
}
