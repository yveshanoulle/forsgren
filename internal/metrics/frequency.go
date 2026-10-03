// Package metrics computes the DORA numbers the page shows, from the
// history `forsgren collect` stores (forsgren#12, step 7).
//
// RED STUB: the types the tests name, with no computation yet.
package metrics

import (
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// day is one window day: 24 hours.
const day = 24 * time.Hour

// Frequency is one project's deployment frequency at the render time.
type Frequency struct {
	Project       string
	Last7, Last30 int
	Latest        time.Time
	Band          Band
}

// HasDeployments says whether the project has any successful deployment
// recorded. RED STUB: never.
func (f Frequency) HasDeployments() bool { return false }

// LatestDate is Latest as a UTC calendar date. RED STUB: empty.
func (f Frequency) LatestDate() string { return "" }

// DeploymentFrequency returns the deployment frequency of each project.
// RED STUB: nothing.
func DeploymentFrequency([]config.Project, []history.Record, time.Time) []Frequency { return nil }
