package metrics

// The fourth number is change fail rate (forsgren#18), per configured
// project: DORA's share of deployments that cause a failure in production
// requiring remediation, over the last 30 days, both ends included, the
// window of lead time and recovery time.
//
//   - the deployments are the stored final deployments, successes and
//     failures, created in the window; another final state (a cancelled
//     run) is neither, and a deployment created after the render time is
//     not there yet;
//   - a failed change is a stored deployment whose state is failure, as
//     recovery time counts them, or an issue labelled failure (forsgren#6)
//     opened in the window, in a repository the project lists;
//   - matching an issue to the deployment it is about is not possible from
//     what is stored, so an issue filed about a failed deployment would
//     count twice. Per repository, the failed changes are therefore the
//     larger of its failed deployments and its failure issues: an issue is
//     taken to be about a failed deployment of its repository as long as
//     there are as many of those. A project adds up its repositories, and
//     has at most as many failed changes as deployments, so the rate is at
//     most 100%. Both counts are shown as they are.
//
// DORA's Quick Check asks for change fail rate as a percentage, on a slider
// from 0 to 100, and shows the answer on a scale labelled 0%, 20%, 40%,
// 60%, 80% and 100%; ChangeFailBandOf bands a rate by those six labels.

import (
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// ChangeFailBand is a DORA band for change fail rate: the nearest of the six
// labels of the Quick Check's change fail rate scale
// (dora.dev/quickcheck/quickcheck.js), word for word, as mutually exclusive
// ranges of the rate. A rate halfway between two labels is the higher one,
// as an edge of lead time's bands is the slower band:
//
//   - 0%: below 10%.
//   - 20%: 10% to below 30%.
//   - 40%: 30% to below 50%.
//   - 60%: 50% to below 70%.
//   - 80%: 70% to below 90%.
//   - 100%: 90% and more.
type ChangeFailBand int

// The six bands, lowest rate first. The zero ChangeFailBand is no band.
const (
	ZeroPercent ChangeFailBand = iota + 1
	TwentyPercent
	FortyPercent
	SixtyPercent
	EightyPercent
	HundredPercent
)

// changeFailEdges are the lowest rates, in percent, of the bands from
// TwentyPercent up.
var changeFailEdges = [...]int{10, 30, 50, 70, 90}

// ChangeFailBandOf is the band of failed changes out of deployments,
// compared exactly; no band without deployments.
func ChangeFailBandOf(failed, deployments int) ChangeFailBand {
	if deployments <= 0 {
		return 0
	}
	band := ZeroPercent
	for _, edge := range changeFailEdges {
		if 100*failed >= edge*deployments {
			band++
		}
	}
	return band
}

// changeFailBandNames are the bands' names, indexed by band; index 0 is no
// band.
var changeFailBandNames = [...]string{"No band", "0%", "20%", "40%", "60%", "80%", "100%"}

// String is the band's name as the page shows it.
func (b ChangeFailBand) String() string { return bandName(b, changeFailBandNames[:]) }

// ChangeFailRate is one project's change fail rate at the render time.
type ChangeFailRate struct {
	Project string
	// Deployments counts the final deployments, successes and failures,
	// created in the last 30 days.
	Deployments int
	// FailedDeployments counts those that failed.
	FailedDeployments int
	// FailureIssues counts the failure issues opened in the last 30 days.
	FailureIssues int
	// Failed counts the failed changes: per repository the larger of its
	// failed deployments and its failure issues, added up, at most
	// Deployments.
	Failed int
	// Band is the DORA band of Failed out of Deployments; no band without
	// deployments.
	Band ChangeFailBand
}

// Percent is Failed out of Deployments in whole percent, rounded down, so
// it never shows a band's edge the rate has not reached; 0 without
// deployments.
func (r ChangeFailRate) Percent() int {
	if r.Deployments == 0 {
		return 0
	}
	return 100 * r.Failed / r.Deployments
}

// ChangeFailRates returns the change fail rate of each project, in the
// order of projects, from the history records and the failure issues at the
// render time now.
func ChangeFailRates(projects []config.Project, records []history.Record, failures []history.Failure,
	now time.Time,
) []ChangeFailRate {
	repos := map[string]*changes{}
	of := func(repository string) *changes {
		key := strings.ToLower(repository)
		if repos[key] == nil {
			repos[key] = &changes{}
		}
		return repos[key]
	}
	for _, r := range records {
		if last30.holds(r.CreatedAt, now) {
			of(r.Repository).deployed(r.State)
		}
	}
	for _, f := range failures {
		of(f.Repository).failureIssues += last30.count(f.OpenedAt, now)
	}
	return ratesOf(projects, repos)
}

// changes is what one repository did in the window.
type changes struct{ deployments, failedDeployments, failureIssues int }

// deployed counts one deployment of the window by its final state.
func (c *changes) deployed(state history.State) {
	switch state {
	case history.StateSuccess:
		c.deployments++
	case history.StateFailure:
		c.deployments++
		c.failedDeployments++
	}
}

// ratesOf adds up each project's repositories.
func ratesOf(projects []config.Project, repos map[string]*changes) []ChangeFailRate {
	index := indexOf(projects)
	out := make([]ChangeFailRate, len(projects))
	for i, p := range projects {
		out[i].Project = p.Name
	}
	for repository, c := range repos {
		if i, ok := index.of(repository); ok {
			out[i].add(*c)
		}
	}
	for i := range out {
		out[i].Failed = min(out[i].Failed, out[i].Deployments)
		out[i].Band = ChangeFailBandOf(out[i].Failed, out[i].Deployments)
	}
	return out
}

// add counts one repository's changes into the project's rate.
func (r *ChangeFailRate) add(c changes) {
	r.Deployments += c.deployments
	r.FailedDeployments += c.failedDeployments
	r.FailureIssues += c.failureIssues
	r.Failed += max(c.failedDeployments, c.failureIssues)
}
