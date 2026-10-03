package metrics

import (
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// ChangeFailBand is a DORA band for change fail rate (forsgren#18).
type ChangeFailBand int

// The six bands, lowest rate first.
const (
	ZeroPercent ChangeFailBand = iota + 1
	TwentyPercent
	FortyPercent
	SixtyPercent
	EightyPercent
	HundredPercent
)

// ChangeFailBandOf is a stub of forsgren#18 step 4's red.
func ChangeFailBandOf(failed, deployments int) ChangeFailBand { return 0 }

// String is a stub of forsgren#18 step 4's red.
func (b ChangeFailBand) String() string { return "" }

// ChangeFailRate is one project's change fail rate (forsgren#18).
type ChangeFailRate struct {
	Project           string
	Deployments       int
	FailedDeployments int
	FailureIssues     int
	Failed            int
	Band              ChangeFailBand
}

// Percent is a stub of forsgren#18 step 4's red.
func (r ChangeFailRate) Percent() int { return 0 }

// BandText is a stub of forsgren#18 step 4's red.
func (r ChangeFailRate) BandText() string { return "" }

// ChangeFailRates is a stub of forsgren#18 step 4's red.
func ChangeFailRates(projects []config.Project, records []history.Record, failures []history.Failure,
	now time.Time,
) []ChangeFailRate {
	return nil
}
