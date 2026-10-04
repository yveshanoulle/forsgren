package metrics

// STUB (forsgren#39, step 2, red): the fifth number is deployment rework
// rate, per configured project. The green fills it in.

import (
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// ReworkRate is one project's deployment rework rate at the render time.
type ReworkRate struct {
	Project string
	// Deployments counts the successful deployments created in the last 30
	// days.
	Deployments int
	// Rework counts those that are rework.
	Rework int
	// Band is the DORA band of Rework out of Deployments, the Quick Check's
	// six labels as for change fail rate; no band without deployments.
	Band ChangeFailBand
}

// Percent is Rework out of Deployments in whole percent, rounded down.
func (r ReworkRate) Percent() int { return 0 }

// Cell is the band, the rate and the counts, "20% · 14% (1 of 7)".
func (r ReworkRate) Cell() string { return "" }

// ReworkRates returns the rework rate of each project, in the order of
// projects, from the history records and the failure issues at now.
func ReworkRates(projects []config.Project, _ []history.Record, _ []history.Failure, _ time.Time) []ReworkRate {
	out := make([]ReworkRate, len(projects))
	for i, p := range projects {
		out[i].Project = p.Name
	}
	return out
}
