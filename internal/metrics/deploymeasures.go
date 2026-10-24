package metrics

// The deployment measures (forsgren#397, step 4), next to the push measures:
// the same two figures per deployment, each as a spread (spread.go), by the
// rules of the direct column and the batch size, which stay for the page
// until the cells replace them.
//
//   - time to deploy is over every commit of a deployment's first-parent
//     chain, pull request merge commits included (the pull request share is
//     its own column now); each commit once, at the earliest deployment that
//     contains it, created in the DORA window, author date to that
//     deployment, a negative time 0; the commits of a deployment without a
//     known lineage are taken at their author date and counted in
//     ByAuthorDate;
//   - commits per deployment is the number of first-parent commits of each
//     deployment created in the window; a deployment without a known lineage
//     is left out and counted in Legacy.

import (
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// DeployMeasures is one project's deployment measures at the render time.
type DeployMeasures struct {
	Project string
	// Commits counts the distinct commits timed, ByAuthorDate those taken at
	// their author date for want of a known lineage.
	Commits, ByAuthorDate int
	// TimeToDeploy is the spread of their times to deploy.
	TimeToDeploy DurationSpread
	// Deployments counts the deployments of the window whose lineage is
	// known, Legacy those left out for want of one.
	Deployments, Legacy int
	// PerDeployment is the spread of their first-parent commits.
	PerDeployment CountSpread
}

// DeployMeasuresOf returns the deployment measures of each project, in the
// order of projects, from the data's stored commits at the render time now,
// over its DORA window.
func DeployMeasuresOf(projects []config.Project, data Data, now time.Time) []DeployMeasures {
	out := make([]DeployMeasures, len(projects))
	for i, p := range projects {
		out[i].Project = p.Name
	}
	index := indexOf(projects)
	times := timesToDeploy(out, data, index, now)
	sizes := commitsPerDeployment(out, data, index, now)
	for i := range out {
		out[i].Commits, out[i].Deployments = len(times[i]), len(sizes[i])
		out[i].TimeToDeploy, out[i].PerDeployment = durationSpreadOf(times[i]), countSpreadOf(sizes[i])
	}
	return out
}

// timesToDeploy are, per project, the times to deploy in nanoseconds of the
// commits first deployed in the window, counting in out the commits taken at
// their author date.
func timesToDeploy(out []DeployMeasures, data Data, index projectIndex, now time.Time) [][]float64 {
	in := data.window()
	counting := directCounting{index: index, lines: lineageOf(data.Commits)}
	times := make([][]float64, len(out))
	for _, d := range firstDeployments(data.Commits, counting) {
		if in.holds(d.deployed, now) {
			times[d.project] = append(times[d.project], float64(d.lead))
			out[d.project].ByAuthorDate += boolCount(d.legacy)
		}
	}
	return times
}

// commitsPerDeployment are, per project, the first-parent commits of each
// deployment of known lineage created in the window, counting in out the
// deployments of unknown lineage left out.
func commitsPerDeployment(out []DeployMeasures, data Data, index projectIndex, now time.Time) [][]float64 {
	in := data.window()
	sizes := make([][]float64, len(out))
	for _, b := range batchesOf(data.Commits, index) {
		switch {
		case !in.holds(b.deployed, now):
		case !b.known:
			out[b.project].Legacy++
		default:
			sizes[b.project] = append(sizes[b.project], float64(b.commits))
		}
	}
	return sizes
}
