package metrics

import (
	"fmt"
	"slices"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// The Mainline Interval over the commits pushed to main (forsgren#588, step
// 1, Yves's ruling: it replaces the interval over the deployed commits).

// authoredAgo is the first-parent commit sha that push brought, authored ago
// before now, whatever the push time.
func authoredAgo(push history.Push, sha string, ago time.Duration) history.PushCommit {
	c := brought(push, sha, "acme-dev", 0)
	c.AuthoredAt = now.Add(-ago)
	return c
}

// shopPushedAt is one push of acme/app, half an hour before now, that brought
// a first-parent commit authored each of ages before now, in that order.
func shopPushedAt(ages ...time.Duration) Data {
	p := pushed("tip", history.PushKindPush, 30*time.Minute, int64(len(ages)))
	data := Data{Pushes: []history.Push{p}}
	for i, ago := range ages {
		data.PushCommits = append(data.PushCommits, authoredAgo(p, fmt.Sprintf("a%d", i), ago))
	}
	return data
}

// shopAt is shopPushedAt with the ages in hours.
func shopAt(hoursAgo ...int) Data {
	ages := make([]time.Duration, len(hoursAgo))
	for i, h := range hoursAgo {
		ages[i] = time.Duration(h) * time.Hour
	}
	return shopPushedAt(ages...)
}

// pushedOnce is a push of repository pushed pushedAgo before now that brought
// the one first-parent commit sha, authored ago before now.
func pushedOnce(repository, sha string, ago, pushedAgo time.Duration) (history.Push, history.PushCommit) {
	p := pushed("tip-"+sha, history.PushKindPush, pushedAgo, 1)
	p.Repository = repository
	return p, authoredAgo(p, sha, ago)
}

// pushedEach is one push per commit, of the repositories and SHAs, each
// authored and pushed as given.
func pushedEach(commits ...pushedCommitAt) Data {
	var data Data
	for _, c := range commits {
		p, pc := pushedOnce(c.repository, c.sha, c.ago, c.pushedAgo)
		data.Pushes = append(data.Pushes, p)
		data.PushCommits = append(data.PushCommits, pc)
	}
	return data
}

// pushedCommitAt is a commit of pushedEach.
type pushedCommitAt struct {
	repository, sha string
	ago, pushedAgo  time.Duration
}

// mainlineOf is Acme Shop's Mainline Interval over data, in the 30 day window.
func mainlineOf(data Data) MainlineInterval { return MainlineIntervals(projects, data, now)[0] }

// TestMainlineIntervalMeanMedianAndCount (forsgren#253, step 3; over the
// pushed commits since forsgren#588): the gaps between the commits sorted by
// author date, whatever the order they are stored in; the mean, the median
// and the count of gaps. Fewer than two commits have no gap, "-"; two commits
// have a gap and no median. The commits of one push are apart by their author
// dates, not at the one push time.
func TestMainlineIntervalMeanMedianAndCount(t *testing.T) {
	h := time.Hour
	cases := []struct {
		name string
		data Data
		want MainlineInterval
		cell string
	}{
		{"no commit", Data{}, MainlineInterval{}, "- | - | -"},
		{"one commit", shopAt(5), MainlineInterval{Commits: 1}, "- | - | -"},
		{"two commits", shopAt(5, 3), MainlineInterval{Commits: 2, Gaps: 1, Mean: 2 * h}, "2 h | - | -"},
		{"gaps 1, 2 and 3 hours", shopAt(10, 9, 7, 4), MainlineInterval{Commits: 4, Gaps: 3, Mean: 2 * h,
			Median: 2 * h}, "2 h | 2 h | -"},
		{"out of order", shopAt(4, 10, 7, 9), MainlineInterval{Commits: 4, Gaps: 3, Mean: 2 * h,
			Median: 2 * h}, "2 h | 2 h | -"},
		{"equal gaps", shopAt(8, 6, 4, 2), MainlineInterval{Commits: 4, Gaps: 3, Mean: 2 * h, Median: 2 * h},
			"2 h | 2 h | -"},
		{"gaps 1 and 3 hours", shopAt(5, 4, 1), MainlineInterval{Commits: 3, Gaps: 2, Mean: 2 * h,
			Median: 2 * h}, "2 h | 2 h | -"},
		{"same author date twice", shopAt(5, 5, 3), MainlineInterval{Commits: 3, Gaps: 2, Mean: h, Median: h},
			"1 h | 1 h | -"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := mainlineOf(c.data)
			c.want.Project = "Acme Shop"
			if got != c.want {
				t.Errorf("want %+v, got %+v", c.want, got)
			}
			if intervalCells(got) != c.cell {
				t.Errorf("want cell %q, got %q", c.cell, intervalCells(got))
			}
		})
	}
}

// TestMainlineIntervalHasIntervalAndMedianFromTheGaps (forsgren#253): an
// interval needs a gap, so two commits; a median needs two gaps.
func TestMainlineIntervalHasIntervalAndMedianFromTheGaps(t *testing.T) {
	ages := []time.Duration{9 * time.Hour, 7 * time.Hour, 4 * time.Hour}
	for commits, want := range map[int][2]bool{0: {false, false}, 1: {false, false}, 2: {true, false}, 3: {true, true}} {
		got := mainlineOf(shopPushedAt(ages[:commits]...))
		if [2]bool{got.HasInterval(), got.HasMedian()} != want {
			t.Errorf("%d commits: want interval and median %v, got %+v", commits, want, got)
		}
	}
}

// TestMainlineIntervalCountsADistinctCommitOnce (forsgren#253, #588): a
// commit two pushes brought is one commit, so it adds no zero gap; the
// repository is compared ignoring case; the same SHA in another repository is
// another commit.
func TestMainlineIntervalCountsADistinctCommitOnce(t *testing.T) {
	h := time.Hour
	first := pushedCommitAt{"acme/app", "a1", 5 * h, h}
	second := pushedCommitAt{"acme/app", "a2", 3 * h, h}
	cases := map[string]struct {
		again pushedCommitAt
		want  int
	}{
		"pushed twice": {pushedCommitAt{"acme/app", "a2", 3 * h, 2 * h}, 2},
		"another case": {pushedCommitAt{"ACME/App", "a2", 3 * h, 2 * h}, 2},
		"another repo": {pushedCommitAt{"acme/api", "a2", 3 * h, h}, 3},
	}
	for name, c := range cases {
		data := pushedEach(first, second, c.again)
		if got := mainlineOf(data); got.Commits != c.want || got.Gaps != c.want-1 {
			t.Errorf("%s: want %d commits and %d gaps, got %+v", name, c.want, c.want-1, got)
		}
	}
}

// TestMainlineIntervalIsPerProject (forsgren#253): the commits of a project's
// repositories are one sequence; another project's, and a repository no
// project lists, are not in it. The result is in the order of projects.
func TestMainlineIntervalIsPerProject(t *testing.T) {
	h := time.Hour
	data := pushedEach(
		pushedCommitAt{"acme/app", "a1", 6 * h, h}, pushedCommitAt{"acme/api", "b1", 3 * h, h},
		pushedCommitAt{"acme/cli", "c1", 9 * h, h}, pushedCommitAt{"acme/cli", "c2", 2 * h, h},
		pushedCommitAt{"acme/gone", "d1", 4 * h, h},
	)
	want := []MainlineInterval{
		{Project: "Acme Shop", Commits: 2, Gaps: 1, Mean: 3 * h},
		{Project: "Acme Tools", Commits: 2, Gaps: 1, Mean: 7 * h},
	}
	if got := MainlineIntervals(projects, data, now); !slices.Equal(got, want) {
		t.Errorf("want %+v, got %+v", want, got)
	}
}

// TestMainlineIntervalOverTheWindow (forsgren#253, #588): as for the push
// measures, a commit counts when its push was in the DORA window, both ends
// included, whatever its author date; 0 is 30 days.
func TestMainlineIntervalOverTheWindow(t *testing.T) {
	data := pushedEach(
		pushedCommitAt{"acme/app", "a1", 40 * day, 2 * day}, pushedCommitAt{"acme/app", "a2", 3 * day, 30 * day},
		pushedCommitAt{"acme/app", "a3", 2 * day, 31 * day}, pushedCommitAt{"acme/app", "a4", 60 * day, 45 * day},
	)
	for days, want := range map[int]int{0: 2, 30: 2, 90: 4, 180: 4} {
		data.DoraDays = days
		if got := MainlineIntervals(projects[:1], data, now)[0]; got.Commits != want {
			t.Errorf("%d days: want %d commits, got %+v", days, want, got)
		}
	}
	data.DoraDays = 30
	if got := MainlineIntervals(projects[:1], data, now)[0]; got.Mean != 37*day {
		t.Errorf("the window counts by push, not author date: want a gap of 37 days, got %+v", got)
	}
}

// TestMainlineIntervalCountsThePushedCommitsNotTheDeployedOnes (forsgren#588):
// the deployed commits are not read: a1 and a2 pushed and not yet deployed
// count, d1, deployed and never pushed, does not.
func TestMainlineIntervalCountsThePushedCommitsNotTheDeployedOnes(t *testing.T) {
	data := shopAt(5, 2)
	data.Commits = []history.Commit{shopAuthored("d1", 9*time.Hour)}
	if got := mainlineOf(data); got.Commits != 2 || got.Mean != 3*time.Hour {
		t.Errorf("want the 2 pushed commits 3 h apart, got %+v", got)
	}
}

// TestMainlineIntervalNeedsNoDeployment (forsgren#588): a project with pushes
// and no deployment has its interval.
func TestMainlineIntervalNeedsNoDeployment(t *testing.T) {
	data := shopAt(5, 4, 1)
	if len(data.Records) != 0 || len(data.Commits) != 0 {
		t.Fatalf("the fixture must have no deployment, got %+v", data)
	}
	if got := mainlineOf(data); !got.HasInterval() || got.Mean != 2*time.Hour {
		t.Errorf("want an interval of 2 h without a deployment, got %+v", got)
	}
}

// TestMainlineIntervalLeavesOutTheCommitsOffTheFirstParentChain (forsgren#254,
// #588): the commits a merge brought in are not mainline commits.
func TestMainlineIntervalLeavesOutTheCommitsOffTheFirstParentChain(t *testing.T) {
	data := shopAt(5, 3)
	branch := authoredAgo(data.Pushes[0], "b1", 4*time.Hour)
	branch.FirstParent = false
	data.PushCommits = append(data.PushCommits, branch)
	if got := mainlineOf(data); got.Commits != 2 || got.Mean != 2*time.Hour {
		t.Errorf("want the 2 first-parent commits, got %+v", got)
	}
}

// TestMainlineIntervalShowsThePushStates (forsgren#588): read from the
// pushes, the interval has the push measures' states, the same words, and
// never falls back to the deployed commits: a refused push read (any case) is
// not readable, even without a pushes file; no pushes file is not collected;
// pushes collected is no state.
func TestMainlineIntervalShowsThePushStates(t *testing.T) {
	deployed := []history.Commit{shopAuthored("d1", 9*time.Hour), shopAuthored("d2", 2*time.Hour)}
	cases := map[string]struct {
		data Data
		want string
	}{
		"refused":       {Data{PushesUncollected: true, PushesDenied: history.Reach{"ACME/App": now}}, PushesNotReadable},
		"not collected": {Data{PushesUncollected: true}, PushesNotCollected},
		"collected":     {shopAt(5, 2), ""},
	}
	for name, c := range cases {
		c.data.Commits = deployed
		got := mainlineOf(c.data)
		if got.State() != c.want {
			t.Errorf("%s: want the state %q, got %q", name, c.want, got.State())
		}
		if c.want != "" && got.HasInterval() {
			t.Errorf("%s: want no interval from the deployed commits, got %+v", name, got)
		}
	}
}
