package metrics

// The fifth number is deployment rework rate (forsgren#39), per configured
// project: DORA's share of deployments that were not planned but made to
// address a user-facing bug, from the stored deployments and failure
// issues, over the last 30 days, both ends included, the window of lead
// time, recovery time and change fail rate.
//
// A rework deployment is a successful deployment that either
//
//   - (a) is the first success of its stream (history.Stream, collect's
//     stream) after a failed deployment, the recovery of recovery time
//     (forsgren#17), whatever the age of the failure; or
//   - (b) was created while an issue labelled failure of its repository
//     was open: opened at or before it, and closed after it or not yet.
//
// A deployment is counted once, though both apply. The rate is the rework
// deployments out of the successful deployments created in the window; a
// deployment created after the render time is not there yet. A service's
// row has no failure issues (the issues name no task), so only (a) applies
// there, as for change fail rate.
//
// DORA's Quick Check asks for rework rate as a percentage, "Approximately
// what percentage of deployments in the last 6 months were not planned but
// were performed to address a user-facing bug in the application?", and
// shows the answer on the same six labels as change fail rate
// (dora.dev/quickcheck/quickcheck.js), so ChangeFailBandOf bands it.

import (
	"fmt"
	"slices"
	"strings"
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

// Percent is Rework out of Deployments in whole percent, rounded down, so
// it never shows a band's edge the rate has not reached; 0 without
// deployments.
func (r ReworkRate) Percent() int {
	if r.Deployments == 0 {
		return 0
	}
	return 100 * r.Rework / r.Deployments
}

// Cell is the band, the rate in whole percent and the rework deployments of
// the successful ones, "20% · 14% (1 of 7)"; "No successful deployments"
// without any.
func (r ReworkRate) Cell() string {
	if r.Deployments == 0 {
		return "No successful deployments"
	}
	return cell(r.Band, fmt.Sprintf("%d%% (%d of %d)", r.Percent(), r.Rework, r.Deployments))
}

// ReworkRates returns the rework rate of each project, in the order of
// projects, from the history records and the failure issues at the render
// time now.
func ReworkRates(projects []config.Project, records []history.Record, failures []history.Failure,
	now time.Time,
) []ReworkRate {
	index := indexOf(projects)
	issues := issuesByRepository(failures)
	out := make([]ReworkRate, len(projects))
	for i, p := range projects {
		out[i].Project = p.Name
	}
	for s, deployments := range streamsOf(index, records, now) {
		i, _ := index.of(s.Repository)
		successes, rework := reworkIn(deployments, issues[s.Repository], now)
		out[i].Deployments += successes
		out[i].Rework += rework
	}
	for i := range out {
		out[i].Band = ChangeFailBandOf(out[i].Rework, out[i].Deployments)
	}
	return out
}

// issuesByRepository groups the failure issues by repository, lower-case.
func issuesByRepository(failures []history.Failure) map[string][]history.Failure {
	issues := map[string][]history.Failure{}
	for _, f := range failures {
		key := strings.ToLower(f.Repository)
		issues[key] = append(issues[key], f)
	}
	return issues
}

// reworkIn walks one stream's deployments oldest first and returns how
// many successes of the last 30 days it holds and how many of them are
// rework, given the failure issues of its repository.
func reworkIn(deployments []history.Record, issues []history.Failure, now time.Time) (successes, rework int) {
	eachSuccess(deployments, func(s streamSuccess) {
		if last30.holds(s.at, now) {
			successes++
			rework += reworkCount(s.recovered, issues, s.at)
		}
	})
	return successes, rework
}

// reworkCount is 1 for a success at at that recovered a failure or was
// created while one of the issues was open, else 0.
func reworkCount(recovered bool, issues []history.Failure, at time.Time) int {
	if recovered || openAt(issues, at) {
		return 1
	}
	return 0
}

// openAt says whether one of the issues was open at at: opened at or before
// it, and closed after it or not yet.
func openAt(issues []history.Failure, at time.Time) bool {
	return slices.ContainsFunc(issues, func(f history.Failure) bool {
		return !f.OpenedAt.After(at) && (f.ClosedAt.IsZero() || f.ClosedAt.After(at))
	})
}
