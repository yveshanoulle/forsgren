package metrics

import (
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// LeadTime is one project's lead time for changes at the render time
// (forsgren#16, step 4).
type LeadTime struct {
	Project string
	Commits int
	Median  time.Duration
	Band    LeadTimeBand
}

// HasCommits says whether any commit was deployed in the window.
func (l LeadTime) HasCommits() bool { return l.Commits > 0 }

// BandText is the band with the median, the count and the period. Stub.
func (l LeadTime) BandText() string { return "" }

// LeadTimes returns the lead time of each project. Stub: one empty
// LeadTime per project, unnamed.
func LeadTimes(projects []config.Project, commits []history.Commit, now time.Time) []LeadTime {
	_, _ = commits, now
	return make([]LeadTime, len(projects))
}

// humanDuration writes d for the page. Stub: empty.
func humanDuration(d time.Duration) string {
	_ = d
	return ""
}
