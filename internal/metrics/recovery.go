package metrics

import (
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// Recovery is one project's failed deployment recovery time at the render
// time (forsgren#17). Not computed yet: the tests are red.
type Recovery struct {
	Project     string
	Recoveries  int
	Median      time.Duration
	Band        LeadTimeBand
	Unrecovered int
}

// BandText is not written yet.
func (r Recovery) BandText() string { return "" }

// RecoveryTimes returns one empty Recovery per project for now.
func RecoveryTimes(projects []config.Project, _ []history.Record, _ time.Time) []Recovery {
	return make([]Recovery, len(projects))
}
