package metrics

import (
	"fmt"
	"math"
	"slices"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// authored is a commit of repository with the given sha, authored ago before
// now and shipped by a deployment created deployedAgo before now.
func authored(repository, sha string, ago, deployedAgo time.Duration) history.Commit {
	return history.Commit{
		Repository: repository, Kind: history.KindEnvironment, DeploymentID: 1, SHA: sha,
		AuthoredAt: now.Add(-ago), DeployedAt: now.Add(-deployedAgo),
	}
}

// shopAuthored is a commit of acme/app authored ago before now, deployed an
// hour ago.
func shopAuthored(sha string, ago time.Duration) history.Commit {
	return authored("acme/app", sha, ago, time.Hour)
}

// shopAt are commits of acme/app authored the given hours before now, in that
// order, deployed an hour ago, each its own commit.
func shopAt(hoursAgo ...int) []history.Commit {
	commits := make([]history.Commit, len(hoursAgo))
	for i, h := range hoursAgo {
		commits[i] = shopAuthored(fmt.Sprintf("a%d", i), time.Duration(h)*time.Hour)
	}
	return commits
}

// mainlineOf is Acme Shop's Mainline Interval over the commits, in the
// 30 day window.
func mainlineOf(commits ...history.Commit) MainlineInterval {
	return MainlineIntervals(projects, Data{Commits: commits}, now)[0]
}

// sqrt2Hours is the square root of 2 hours, to the nanosecond: the sample
// deviation of gaps of 1 and 3 hours (mean 2 h, squares 1 and 1, over n-1 = 1,
// in hours squared: 2).
func sqrt2Hours() time.Duration {
	hour := float64(time.Hour)
	return time.Duration(math.Round(math.Sqrt2 * hour))
}

// TestMainlineIntervalMeanDeviationAndCount (forsgren#253, step 3): the gaps
// between the commits sorted by author date, whatever the order they are
// stored in; the mean, the sample standard deviation (n-1) and the count of
// gaps. Fewer than two commits have no gap, "-"; two commits have a gap and
// no deviation.
func TestMainlineIntervalMeanDeviationAndCount(t *testing.T) {
	h, dev := time.Hour, sqrt2Hours()
	cases := []struct {
		name    string
		commits []history.Commit
		want    MainlineInterval
		cell    string
	}{
		{"no commit", nil, MainlineInterval{}, "-"},
		{"one commit", shopAt(5), MainlineInterval{Commits: 1}, "-"},
		{"two commits", shopAt(5, 3), MainlineInterval{Commits: 2, Gaps: 1, Mean: 2 * h},
			"2 h ± - (1) · median - · p90 -"},
		{"gaps 1, 2 and 3 hours", shopAt(10, 9, 7, 4), MainlineInterval{Commits: 4, Gaps: 3, Mean: 2 * h,
			Deviation: h, Median: 2 * h}, "2 h ± 1 h (3) · median 2 h · p90 -"},
		{"out of order", shopAt(4, 10, 7, 9), MainlineInterval{Commits: 4, Gaps: 3, Mean: 2 * h,
			Deviation: h, Median: 2 * h}, "2 h ± 1 h (3) · median 2 h · p90 -"},
		{"equal gaps", shopAt(8, 6, 4, 2), MainlineInterval{Commits: 4, Gaps: 3, Mean: 2 * h, Median: 2 * h},
			"2 h ± less than 1 min (3) · median 2 h · p90 -"},
		{"gaps 1 and 3 hours", shopAt(5, 4, 1), MainlineInterval{Commits: 3, Gaps: 2, Mean: 2 * h,
			Deviation: dev, Median: 2 * h}, "2 h ± 1 h 24 min (2) · median 2 h · p90 -"},
		{"same author date twice", shopAt(5, 5, 3), MainlineInterval{Commits: 3, Gaps: 2, Mean: h, Deviation: dev, Median: h},
			"1 h ± 1 h 24 min (2) · median 1 h · p90 -"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := mainlineOf(c.commits...)
			c.want.Project = "Acme Shop"
			if got != c.want {
				t.Errorf("want %+v, got %+v", c.want, got)
			}
			if got.Cell() != c.cell {
				t.Errorf("want cell %q, got %q", c.cell, got.Cell())
			}
		})
	}
}

// TestMainlineIntervalHasIntervalAndDeviationFromTheGaps (forsgren#253): an
// interval needs a gap, so two commits; a deviation needs two gaps (n-1 is 0
// for one).
func TestMainlineIntervalHasIntervalAndDeviationFromTheGaps(t *testing.T) {
	for commits, want := range map[int][2]bool{0: {false, false}, 1: {false, false}, 2: {true, false}, 3: {true, true}} {
		got := mainlineOf(shopAt(9, 7, 4)[:commits]...)
		if [2]bool{got.HasInterval(), got.HasDeviation()} != want {
			t.Errorf("%d commits: want interval and deviation %v, got %+v", commits, want, got)
		}
	}
}

// TestMainlineIntervalDeviationDividesByNMinusOne (forsgren#253): the
// deviation of gaps 1 and 3 hours is sqrt(2) hours with n-1, a population
// deviation (n) would be exactly 1 hour; a mutation to n fails here.
func TestMainlineIntervalDeviationDividesByNMinusOne(t *testing.T) {
	got := mainlineOf(shopAt(5, 4, 1)...)
	if got.Deviation == time.Hour {
		t.Fatalf("the deviation is the population deviation (n), 1 h; want the sample deviation (n-1)")
	}
	if want := sqrt2Hours(); got.Deviation != want {
		t.Errorf("want the sample deviation %v, got %v", want, got.Deviation)
	}
}

// TestMainlineIntervalCountsADistinctCommitOnce (forsgren#253): a commit
// shipped by two deployments (two tasks of one repository) is one commit, so
// it adds no zero gap; a commit of the same SHA in another repository is
// another commit; the repository is compared ignoring case.
func TestMainlineIntervalCountsADistinctCommitOnce(t *testing.T) {
	first, second := shopAuthored("a1", 5*time.Hour), shopAuthored("a2", 3*time.Hour)
	twice := second
	twice.DeploymentID = 2
	upper := second
	upper.Repository = "ACME/App"
	other := authored("acme/api", "a2", 3*time.Hour, time.Hour)
	cases := map[string]struct {
		commits []history.Commit
		want    int
	}{
		"deployed twice": {[]history.Commit{first, second, twice}, 2},
		"another case":   {[]history.Commit{first, second, upper}, 2},
		"another repo":   {[]history.Commit{first, second, other}, 3},
	}
	for name, c := range cases {
		if got := mainlineOf(c.commits...); got.Commits != c.want || got.Gaps != c.want-1 {
			t.Errorf("%s: want %d commits and %d gaps, got %+v", name, c.want, c.want-1, got)
		}
	}
}

// TestMainlineIntervalIsPerProject (forsgren#253): the commits of a project's
// repositories are one sequence; another project's, and a repository no
// project lists, are not in it. The result is in the order of projects.
func TestMainlineIntervalIsPerProject(t *testing.T) {
	commits := []history.Commit{
		authored("acme/app", "a1", 6*time.Hour, time.Hour), authored("acme/api", "b1", 3*time.Hour, time.Hour),
		authored("acme/cli", "c1", 9*time.Hour, time.Hour), authored("acme/cli", "c2", 2*time.Hour, time.Hour),
		authored("acme/gone", "d1", 4*time.Hour, time.Hour),
	}
	want := []MainlineInterval{
		{Project: "Acme Shop", Commits: 2, Gaps: 1, Mean: 3 * time.Hour},
		{Project: "Acme Tools", Commits: 2, Gaps: 1, Mean: 7 * time.Hour},
	}
	if got := MainlineIntervals(projects, Data{Commits: commits}, now); !slices.Equal(got, want) {
		t.Errorf("want %+v, got %+v", want, got)
	}
}

// TestMainlineIntervalOverTheWindow (forsgren#253): as for lead time, a commit
// counts when its deployment was created in the DORA window, both ends
// included, whatever its author date; 0 is 30 days.
func TestMainlineIntervalOverTheWindow(t *testing.T) {
	commits := []history.Commit{
		authored("acme/app", "a1", 40*day, 2*day), authored("acme/app", "a2", 3*day, 30*day),
		authored("acme/app", "a3", 2*day, 31*day), authored("acme/app", "a4", 60*day, 45*day),
	}
	for days, want := range map[int]int{0: 2, 30: 2, 90: 4, 180: 4} {
		got := MainlineIntervals(projects[:1], Data{Commits: commits, DoraDays: days}, now)[0]
		if got.Commits != want {
			t.Errorf("%d days: want %d commits, got %+v", days, want, got)
		}
	}
	if got := MainlineIntervals(projects[:1], Data{Commits: commits, DoraDays: 30}, now)[0]; got.Mean != 37*day {
		t.Errorf("the window counts by deployment, not author date: want a gap of 37 days, got %+v", got)
	}
}
