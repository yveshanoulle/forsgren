package metrics

// The Mainline Interval (forsgren#253, step 3 of 7) is the first number of
// the TBD page: how often a project gets a change onto what it deploys, as
// the mean and the spread of the time between those changes. It reads the
// commits `forsgren collect` stores in data/commits.csv, which are the
// commits a deployment shipped, so it is an interval between deployed
// commits, not between every commit of the mainline. Since forsgren#254 it
// counts only the commits of each deployment's first-parent chain, placed at
// their committer dates, and keeps the old approximation, every commit at its
// author date, for the deployments whose lineage is not known (lineage.go).
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
//   - a commit counts when it is on its deployment's first-parent chain, or
//     when that deployment's lineage is not known (lineage.go), and the
//     commits are distinct only among those that count;
//   - the commits are put in the order of the times they are placed at (the
//     committer date, or the author date: lineage.go), whatever the order they
//     are stored in, and a gap is the time between two consecutive ones; two
//     commits placed at the same time have a gap of 0;
//   - the mean cell names the commits placed at their author date
//     (ByAuthorDate), and in the table that shows the median alone the median
//     cell does (forsgren#423);
//   - the mean is the mean of the gaps; the deviation and the count of gaps
//     are not on the page any more (forsgren#423, decision #424);
//   - fewer than two commits have no gap, so no interval, "-"; two commits
//     have one gap, a mean but no median (shown as "-").
//
// The result is per project; the label rows of the table get theirs when the
// page is wired.

import (
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
	// Commits counts the distinct commits deployed in the DORA window that
	// count (on the first-parent chain, or of a deployment without a known
	// lineage).
	Commits int
	// Gaps counts the gaps between consecutive commits by the time they are
	// placed at: one
	// fewer than Commits, none below two commits.
	Gaps int
	// Mean is the mean gap; zero without a gap.
	Mean time.Duration
	// Median is the median gap; zero below two gaps (see HasMedian).
	Median time.Duration
	// P90 is the 90th percentile of the gaps, nearest rank; zero below ten
	// gaps (see HasP90).
	P90 time.Duration
	// ByAuthorDate counts the commits placed by their author date, the old
	// approximation (forsgren#254): those of a deployment without a known
	// lineage, and those of the first-parent chain without a committer date.
	ByAuthorDate int
}

// Notes are the notes on the mean cell (forsgren#394, step 2): none without a
// commit timed by author date; when they are more than half of the commits
// counted, the figure is mostly the old approximation and the note says so
// (forsgren#345, step 3, Yves's wording on #344), with the commits it is part
// of; else the plain count.
func (m MainlineInterval) Notes() []Note {
	switch {
	case m.ByAuthorDate == 0:
		return nil
	case mostOf(m.ByAuthorDate, m.Commits):
		return []Note{{Kind: NoteMostlyEstimated, Count: m.ByAuthorDate, Of: m.Commits}}
	}
	return []Note{{Kind: NoteByAuthorDate, Count: m.ByAuthorDate}}
}

// mostOf says whether part is more than half of whole: at half, or below, it
// is not (forsgren#345, step 3, #344).
func mostOf(part, whole int) bool { return 2*part > whole }

// HasInterval says whether there is a gap, so a mean to show.
func (m MainlineInterval) HasInterval() bool { return m.Gaps > 0 }

// minP90Gaps is how many gaps the 90th percentile needs: under ten, the
// nearest rank is the longest gap, which says nothing the maximum does not.
const minP90Gaps = 10

// HasMedian says whether the median is shown: it needs two gaps (one gap is
// the mean).
func (m MainlineInterval) HasMedian() bool { return m.Gaps > 1 }

// HasP90 says whether the 90th percentile is shown: it needs minP90Gaps gaps.
func (m MainlineInterval) HasP90() bool { return m.Gaps >= minP90Gaps }

// The Mainline Interval is three columns of the TBD page, one number each,
// the mean, the median and the p90, or the median alone (forsgren#423, Yves's
// decision #424 C: the deviation and the gaps left the table, they were five
// columns from forsgren#387). A figure that is not shown yet is a dash in its
// own cell, and so is every cell of a project with no gap.

// MeanCell is the mean gap, "2 h"; "-" without a gap. It carries the Notes,
// so the note stays on the mean when the gaps leave the table (forsgren#423).
func (m MainlineInterval) MeanCell() NotedCell {
	if !m.HasInterval() {
		return NotedCell{Value: noNumber}
	}
	return NotedCell{Value: tbdDuration(m.Mean), Notes: m.Notes()}
}

// MedianCell is the median gap; "-" below two gaps.
func (m MainlineInterval) MedianCell() string { return m.shown(m.HasMedian(), m.Median) }

// P90Cell is the 90th percentile of the gaps; "-" below ten gaps.
func (m MainlineInterval) P90Cell() string { return m.shown(m.HasP90(), m.P90) }

// MedianNotedCell is the median gap with the Notes, for the table that shows
// the median alone, where the mean cell is not there to carry them
// (forsgren#423): a dash below two gaps, the notes while there is a gap.
func (m MainlineInterval) MedianNotedCell() NotedCell {
	if !m.HasInterval() {
		return NotedCell{Value: noNumber}
	}
	return NotedCell{Value: m.MedianCell(), Notes: m.Notes()}
}

// shown is d written for a cell when there is one, else a dash.
func (m MainlineInterval) shown(has bool, d time.Duration) string {
	if !has {
		return noNumber
	}
	return tbdDuration(d)
}

// MainlineIntervals returns the Mainline Interval of each project, in the
// order of projects, from the data's stored commits at the render time now,
// over its DORA window (30, 90 or 180 days).
func MainlineIntervals(projects []config.Project, data Data, now time.Time) []MainlineInterval {
	index := indexOf(projects)
	times := make([]projectTimes, len(projects))
	lines := lineageOf(data.Commits)
	counted := distinctInWindow{window: data.window(), now: now, seen: map[string]bool{}}
	for _, c := range data.Commits {
		i, ok := index.of(c.Repository)
		if !ok {
			continue
		}
		if p, counts := lines.place(c); counts && counted.admits(c) {
			times[i].add(p)
		}
	}
	out := make([]MainlineInterval, len(projects))
	for i, p := range projects {
		out[i] = mainlineOver(p.Name, times[i].at)
		out[i].ByAuthorDate = times[i].byAuthor
	}
	return out
}

// projectTimes are the times of one project's counted commits, and how many
// of them are author dates.
type projectTimes struct {
	at       []time.Time
	byAuthor int
}

// add counts the commit placed at p.
func (t *projectTimes) add(p placed) {
	t.at = append(t.at, p.at)
	if p.byAuthor {
		t.byAuthor++
	}
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

// mainlineOver is project's MainlineInterval over the times its distinct
// counted commits are placed at.
func mainlineOver(project string, dates []time.Time) MainlineInterval {
	m := MainlineInterval{Project: project, Commits: len(dates)}
	if len(dates) < 2 {
		return m
	}
	gaps := gapsOf(dates)
	m.Gaps = len(gaps)
	mean := meanOf(gaps)
	m.Mean = time.Duration(math.Round(mean))
	m.Median, m.P90 = medianAndP90(gaps)
	return m
}

// medianAndP90 are the median of the gaps, when there are two, and their 90th
// percentile by nearest rank, when there are minP90Gaps: the gap at position
// ceil(0.9 n) of the n gaps sorted from the shortest, so nine tenths of them are
// no longer. The rank is worked in integers, (9n + 9) / 10, so no float rounds
// it. Each is zero while it is not shown.
func medianAndP90(gaps []float64) (median, p90 time.Duration) {
	sorted := make([]time.Duration, len(gaps))
	for i, g := range gaps {
		sorted[i] = time.Duration(math.Round(g))
	}
	slices.Sort(sorted)
	if len(sorted) > 1 {
		median = middleOf(sorted)
	}
	if len(sorted) >= minP90Gaps {
		p90 = sorted[(9*len(sorted)+9)/10-1]
	}
	return median, p90
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
