package metrics

// The cells of the TBD page's push and deployment groups (forsgren#397, step
// 5, Yves's ruling on #401): numbers only, no sentence but the two states, a
// dash where a value is not shown (a median below two values, a 90th
// percentile below ten, a share without a commit). Durations are
// shortDuration's, counts have one decimal where not whole, shares are whole
// percent like 99%.

import (
	"fmt"
	"strconv"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// The two states of a project's push groups, each one cell across them,
// never deployment numbers in their place.
const (
	PushesNotReadable  = "Push activity not readable"
	PushesNotCollected = "Pushes not collected yet"
)

// State is PushesNotReadable for a project whose push read was refused,
// PushesNotCollected when no push has been collected, else empty.
func (m PushMeasures) State() string {
	switch {
	case m.NotReadable:
		return PushesNotReadable
	case m.Uncollected:
		return PushesNotCollected
	}
	return ""
}

// CommitsCell is the distinct commits the pushes brought; a dash in a state.
func (m PushMeasures) CommitsCell() string { return m.volume(m.Commits) }

// PushesCell is the pushes of the window; a dash in a state.
func (m PushMeasures) PushesCell() string { return m.volume(m.Pushes) }

// volume is n as a cell, a dash in a state.
func (m PushMeasures) volume(n int) string {
	if m.State() != "" {
		return noNumber
	}
	return strconv.Itoa(n)
}

// DirectCell, PullRequestCell, UnknownAuthorCell and BotCell are the shares of the
// commits, "99%", a dash without a commit.
func (m PushMeasures) DirectCell() string { return m.shareCell(m.DirectShare()) }

// PullRequestCell is the share of the commits that came through a pull request.
func (m PushMeasures) PullRequestCell() string { return m.shareCell(m.PullRequestShare()) }

// BotCell is the share of the commits whose author is a bot.
func (m PushMeasures) BotCell() string { return m.shareCell(m.BotShare()) }

// UnknownAuthorCell is the share of the commits of an unknown author.
func (m PushMeasures) UnknownAuthorCell() string { return m.shareCell(m.UnknownAuthorShare()) }

// shareCell is percent as a cell, a dash without a commit.
func (m PushMeasures) shareCell(percent int) string {
	if m.Commits == 0 {
		return noNumber
	}
	return fmt.Sprintf("%d%%", percent)
}

// MeanCell is the mean time, a dash for none.
func (s DurationSpread) MeanCell() string { return s.cell(s.Count > 0, s.Mean) }

// MedianCell is the median time, a dash below two times.
func (s DurationSpread) MedianCell() string { return s.cell(s.HasMedian(), s.Median) }

// P90Cell is the 90th percentile, a dash below ten times.
func (s DurationSpread) P90Cell() string { return s.cell(s.HasP90(), s.P90) }

// cell is d in shortDuration's words, a dash when it is not shown.
func (s DurationSpread) cell(shown bool, d time.Duration) string {
	if !shown {
		return noNumber
	}
	return shortDuration(d)
}

// MeanCell is the mean count, a dash for none.
func (s CountSpread) MeanCell() string { return s.cell(s.Count > 0, s.Mean) }

// MedianCell is the median count, a dash below two counts.
func (s CountSpread) MedianCell() string { return s.cell(s.HasMedian(), s.Median) }

// P90Cell is the 90th percentile, a dash below ten counts.
func (s CountSpread) P90Cell() string { return s.cell(s.HasP90(), s.P90) }

// cell is v with one decimal where it is not whole, a dash when it is not
// shown.
func (s CountSpread) cell(shown bool, v float64) string {
	switch {
	case !shown:
		return noNumber
	case v == float64(int(v)):
		return strconv.Itoa(int(v))
	}
	return strconv.FormatFloat(v, 'f', 1, 64)
}

// DeploymentVolume is one project's deployments of the DORA window for the
// TBD page's Deployments column: the successful ones, and whether the
// project is measured by releases alone.
type DeploymentVolume struct {
	Project  string
	Count    int
	Releases bool
}

// Cell is the count, "85 releases" for a project measured by releases (Yves's
// ruling on #397), a bare number for any other.
func (v DeploymentVolume) Cell() string {
	if v.Releases {
		return plural(v.Count, "release")
	}
	return strconv.Itoa(v.Count)
}

// DeploymentVolumes returns the deployment volume of each project, in the
// order of projects, over the data's DORA window at the render time now.
func DeploymentVolumes(projects []config.Project, data Data, now time.Time) []DeploymentVolume {
	frequencies := DeploymentFrequency(projects, data, now)
	out := make([]DeploymentVolume, len(projects))
	for i, p := range projects {
		out[i] = DeploymentVolume{Project: p.Name, Count: frequencies[i].InWindow, Releases: byReleases(p)}
	}
	return out
}

// byReleases says whether every repository of p is measured by releases.
func byReleases(p config.Project) bool {
	for _, r := range p.Repositories {
		if r.Deployment.Kind != config.Release {
			return false
		}
	}
	return len(p.Repositories) > 0
}
