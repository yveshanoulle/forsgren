package metrics

// The cells of the TBD page's push and deployment groups (forsgren#397, step
// 5, Yves's ruling on #401): numbers only, no sentence but the two states, a
// dash where a value is not shown (a median below two values, a 90th
// percentile below ten, a share without a commit). Durations are
// tbdDuration's, counts have two significant digits (countCell), shares are whole
// percent like 99%.

import (
	"fmt"
	"math"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// The two states of a project's push groups, each one cell across them,
// never deployment numbers in their place.
const (
	PushesNotReadable  = "Push activity not readable"
	PushesNotCollected = "Pushes not collected yet"
)

// words is PushesNotReadable for a refused push read, PushesNotCollected when
// no push has been collected, else empty: the State of every measure read
// from the pushes (the push measures, the Mainline Lead Time).
func (s pushState) words() string {
	switch {
	case s.notReadable:
		return PushesNotReadable
	case s.uncollected:
		return PushesNotCollected
	}
	return ""
}

// State is PushesNotReadable for a project whose push read was refused,
// PushesNotCollected when no push has been collected, else empty.
func (m PushMeasures) State() string { return pushState{m.NotReadable, m.Uncollected}.words() }

// CommitsCell is the distinct commits the pushes brought; a dash in a state.
func (m PushMeasures) CommitsCell() string { return m.volume(m.Commits) }

// PushesCell is the pushes of the window; a dash in a state.
func (m PushMeasures) PushesCell() string { return m.volume(m.Pushes) }

// volume is n as a cell, a dash in a state.
func (m PushMeasures) volume(n int) string {
	if m.State() != "" {
		return noNumber
	}
	return GroupDigits(n)
}

// DirectCell is the share of the commits pushed straight to main, shown as
// shareCell does.
func (m PushMeasures) DirectCell() string { return m.shareCell(m.Direct) }

// PullRequestCell is the share of the commits that came through a pull request.
func (m PushMeasures) PullRequestCell() string { return m.shareCell(m.PullRequests) }

// BotCell is the share of the commits whose author is a bot.
func (m PushMeasures) BotCell() string { return m.shareCell(m.Bots) }

// UnknownAuthorCell is the share of the commits of an unknown author.
func (m PushMeasures) UnknownAuthorCell() string { return m.shareCell(m.UnknownAuthors) }

// shareCell is part out of the commits to two significant digits, rounded
// down and computed from the counts (forsgren#477): from 10% a whole percent
// ("19%"), from 1% one decimal always shown ("3.0%"), under 1% two decimals
// ("0.63%", "< 0.01%" below that), exactly none "0%"; a dash without a commit.
func (m PushMeasures) shareCell(part int) string {
	switch hundredths := part * 10000 / max(m.Commits, 1); {
	case m.Commits == 0:
		return noNumber
	case part == 0:
		return "0%"
	case hundredths == 0:
		return "< 0.01%"
	case hundredths >= 1000:
		return fmt.Sprintf("%d%%", hundredths/100)
	case hundredths >= 100:
		return fmt.Sprintf("%d.%d%%", hundredths/100, hundredths/10%10)
	default:
		return fmt.Sprintf("%d.%02d%%", hundredths/100, hundredths%100)
	}
}

// MeanCell is the mean time, a dash for none.
func (s DurationSpread) MeanCell() string { return s.cell(s.Count > 0, s.Mean) }

// MedianCell is the median time, a dash below two times.
func (s DurationSpread) MedianCell() string { return s.cell(s.HasMedian(), s.Median) }

// P90Cell is the 90th percentile, a dash below ten times.
func (s DurationSpread) P90Cell() string { return s.cell(s.HasP90(), s.P90) }

// cell is d in tbdDuration's words, a dash when it is not shown.
func (s DurationSpread) cell(shown bool, d time.Duration) string {
	if !shown {
		return noNumber
	}
	return tbdDuration(d)
}

// MeanCell is the mean count, a dash for none.
func (s CountSpread) MeanCell() string { return s.cell(s.Count > 0, s.Mean) }

// MedianCell is the median count, a dash below two counts.
func (s CountSpread) MedianCell() string { return s.cell(s.HasMedian(), s.Median) }

// P90Cell is the 90th percentile, a dash below ten counts.
func (s CountSpread) P90Cell() string { return s.cell(s.HasP90(), s.P90) }

// cell is v as countCell writes it, a dash when it is not shown.
func (s CountSpread) cell(shown bool, v float64) string {
	if !shown {
		return noNumber
	}
	return countCell(v)
}

// countCell is a count to two significant digits, rounded to the nearest with
// a half rounded up (forsgren#492, decision #493 A): under 10 one decimal
// always shown ("1.0", "2.5"), from 10 a whole number ("10", "11"). A value
// that rounds to 10.0 is 10. The half is rounded on the value times 10 (or the
// value itself from 10): a mean or median is a whole number over a whole
// number, so a half in decimal (2.45, 9.95, 10.5) multiplies to exactly that
// half in float, which TestCountSpreadCellsShowTwoSignificantDigits pins.
func countCell(v float64) string {
	if tenths := int(math.Floor(v*10 + 0.5)); tenths < 100 {
		return fmt.Sprintf("%d.%d", tenths/10, tenths%10)
	}
	return GroupDigits(int(math.Floor(v + 0.5)))
}

// DeploymentVolume is one project's deployments of the DORA window for the
// TBD page's Deployments column: the successful ones.
type DeploymentVolume struct {
	Project string
	Count   int
	// Final counts the final deployments of the window, failures included
	// (forsgren#394, step 3, decision #442): any one is data.
	Final int
}

// Cell is the count, a bare number for every project (forsgren#403: 87,
// never "87 releases").
func (v DeploymentVolume) Cell() string { return GroupDigits(v.Count) }

// DeploymentVolumes returns the deployment volume of each project, in the
// order of projects, over the data's DORA window at the render time now.
func DeploymentVolumes(projects []config.Project, data Data, now time.Time) []DeploymentVolume {
	frequencies := DeploymentFrequency(projects, data, now)
	rates := ChangeFailRates(projects, data, now)
	out := make([]DeploymentVolume, len(projects))
	for i, p := range projects {
		out[i] = DeploymentVolume{Project: p.Name, Count: frequencies[i].InWindow, Final: rates[i].Deployments}
	}
	return out
}
