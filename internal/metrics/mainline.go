package metrics

// The Mainline Interval (forsgren#253, step 3 of 7) is the first number of
// the TBD page: how often a project gets a change onto what it deploys, as
// the mean and the spread of the time between those changes. It reads the
// commits `forsgren collect` stores in data/commits.csv, which are the
// commits a deployment shipped, so it is an interval between deployed
// commits, not between every commit of the mainline (a later issue stores the
// commit parents and the committer date).
//
//   - a commit counts when its deployment was created in the DORA window
//     (dora_days, both ends included), the rule of lead time for changes
//     (LeadTimes) and of deployment frequency (InWindow); its author date,
//     which can be far older, does not decide it;
//   - a commit belongs to the project whose config lists its repository,
//     compared ignoring case; a project's repositories are one sequence;
//   - commits are distinct by repository (ignoring case) and SHA: a commit
//     shipped by two deployments, two tasks of one repository, counts once,
//     unlike lead time, which counts each line; the same SHA in two
//     repositories is two commits;
//   - the commits are put in the order of their author dates, whatever the
//     order they are stored in, and a gap is the time between two
//     consecutive ones; two commits with the same author date have a gap of 0;
//   - the mean is the mean of the gaps and the deviation their sample
//     standard deviation, the sum of the squares of the differences from the
//     mean over n-1, n the count of gaps; the count shown is the count of gaps;
//   - fewer than two commits have no gap, so no interval, "-"; two commits
//     have one gap, a mean but no deviation (n-1 is 0), shown as "-".
//
// The result is per project; the label rows of the table get theirs when the
// page is wired.

import (
	"fmt"
	"math"
	"slices"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// MainlineInterval is one project's Mainline Interval at the render time.
type MainlineInterval struct {
	Project string
	// Commits counts the distinct commits deployed in the DORA window.
	Commits int
	// Gaps counts the gaps between consecutive commits by author date: one
	// fewer than Commits, none below two commits.
	Gaps int
	// Mean is the mean gap; zero without a gap.
	Mean time.Duration
	// Deviation is the sample standard deviation of the gaps; zero below
	// two gaps (see HasDeviation).
	Deviation time.Duration
}

// HasInterval says whether there is a gap, so a mean to show.
func (m MainlineInterval) HasInterval() bool { return m.Gaps > 0 }

// HasDeviation says whether the sample standard deviation exists: it needs
// two gaps.
func (m MainlineInterval) HasDeviation() bool { return m.Gaps > 1 }

// Cell is the mean, the deviation and the count of gaps, "2 h ± 1 h (3)", the
// deviation "-" below two gaps; "-" below two commits.
func (m MainlineInterval) Cell() string {
	if !m.HasInterval() {
		return noNumber
	}
	deviation := noNumber
	if m.HasDeviation() {
		deviation = shortDuration(m.Deviation)
	}
	return fmt.Sprintf("%s ± %s (%d)", shortDuration(m.Mean), deviation, m.Gaps)
}

// MainlineIntervals returns the Mainline Interval of each project, in the
// order of projects, from the data's stored commits at the render time now,
// over its DORA window (30, 90 or 180 days).
func MainlineIntervals(projects []config.Project, data Data, now time.Time) []MainlineInterval {
	index := indexOf(projects)
	authored := make([][]time.Time, len(projects))
	counted := distinctInWindow{window: data.window(), now: now, seen: map[string]bool{}}
	for _, c := range data.Commits {
		if i, ok := index.of(c.Repository); ok && counted.admits(c) {
			authored[i] = append(authored[i], c.AuthoredAt)
		}
	}
	out := make([]MainlineInterval, len(projects))
	for i, p := range projects {
		out[i] = mainlineOver(p.Name, authored[i])
	}
	return out
}

// distinctInWindow admits the commits whose deployment was created in the
// window at now, each commit once, distinct by repository ignoring case and SHA.
type distinctInWindow struct {
	window window
	now    time.Time
	seen   map[string]bool
}

// admits says whether c is in the window and was not admitted before, and
// notes it.
func (d distinctInWindow) admits(c history.Commit) bool {
	key := strings.ToLower(c.Repository) + "@" + c.SHA
	if d.seen[key] || !d.window.holds(c.DeployedAt, d.now) {
		return false
	}
	d.seen[key] = true
	return true
}

// mainlineOver is project's MainlineInterval over the author dates of its
// distinct commits.
func mainlineOver(project string, dates []time.Time) MainlineInterval {
	m := MainlineInterval{Project: project, Commits: len(dates)}
	if len(dates) < 2 {
		return m
	}
	gaps := gapsOf(dates)
	m.Gaps = len(gaps)
	mean := meanOf(gaps)
	m.Mean = time.Duration(math.Round(mean))
	if m.HasDeviation() {
		m.Deviation = time.Duration(math.Round(sampleDeviation(gaps, mean)))
	}
	return m
}

// gapsOf are the gaps in nanoseconds between neighbouring dates once sorted, so
// one fewer than dates, which hold at least two.
func gapsOf(dates []time.Time) []float64 {
	slices.SortFunc(dates, time.Time.Compare)
	gaps := make([]float64, len(dates)-1)
	for i := range gaps {
		gaps[i] = float64(dates[i+1].Sub(dates[i]))
	}
	return gaps
}

// meanOf is the mean of values, which hold at least one.
func meanOf(values []float64) float64 {
	sum := 0.0
	for _, v := range values {
		sum += v
	}
	return sum / float64(len(values))
}

// sampleDeviation is the sample standard deviation of values around their
// mean: the squares of the differences over n-1, so values hold at least two.
func sampleDeviation(values []float64, mean float64) float64 {
	squares := 0.0
	for _, v := range values {
		squares += (v - mean) * (v - mean)
	}
	return math.Sqrt(squares / float64(len(values)-1))
}
