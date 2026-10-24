package page

import (
	"errors"
	"fmt"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// The TBD page (forsgren#253): one table with a row per project, in column
// groups under two-level headers (forsgren#397, step 5, Yves's ruling on
// #401): volume, shares of the commits, time to main per commit, commits per
// push, time to deploy per commit and commits per deployment, then the
// Mainline Lead Time (forsgren#256), the Mainline Interval (five columns,
// forsgren#387, step 1) and the Developers count (forsgren#273); or one line
// that says why there is none.

// tbdTitle is the TBD page's title, its h1 and the legend's heading for it,
// as Yves wrote it (forsgren#271): the name, then the beta marker the History
// page has too (betaMarker, " (BETA)", in capitals).
const tbdTitle = "Trunk-based development [TBD]" + betaMarker

// pullsUncollectedCell is the Mainline Lead Time cell while data/pulls.csv
// is absent: no collect has stored pull requests yet (forsgren#256, step 2).
const pullsUncollectedCell = "No pull requests have been collected yet"

// TbdTitle is tbdTitle, for the templates that name the TBD page.
func (d Data) TbdTitle() string { return tbdTitle }

// TbdMessage is the one line the TBD page shows in place of its table: there
// are no projects, or no Mainline Interval has been read.
func (d Data) TbdMessage() string {
	if d.NoProjects {
		return "No projects are listed yet, so there is no Mainline Interval to show."
	}
	return "No commits have been collected yet, so there is no Mainline Interval to show."
}

// TbdRow is one project's row of the TBD page (forsgren#397, step 5): its
// volume, shares and push and deployment measures, its Mainline Lead Time
// (forsgren#256, step 2; the pull requests column alone), its Mainline
// Interval and its Developers count (forsgren#273).
type TbdRow struct {
	Interval   metrics.MainlineInterval
	Lead       metrics.MainlineLeadTime
	Developers metrics.Developers
	Push       metrics.PushMeasures
	Deploy     metrics.DeployMeasures
	Volume     metrics.DeploymentVolume
	// pullsUncollected is Data.PullsUncollected.
	pullsUncollected bool
}

// LeadCell is the row's pull requests cell, in the Mainline Lead Time group:
// MainlineLeadTime.Cell, or
// pullsUncollectedCell while the pull requests have not been collected,
// unless a refused read makes the project not readable (forsgren#337, step
// 2), which Cell says.
func (r TbdRow) LeadCell() string {
	if r.pullsUncollected && !r.Lead.NotReadable {
		return pullsUncollectedCell
	}
	return r.Lead.Cell()
}

// TbdRows pairs each Mainline Interval with the Mainline Lead Time, push and
// deployment measures, deployment volume and Developers of its project, in the
// Mainline's order. All come from the config's projects in its order, so one
// that is missing or names another project in a row is an error, which fails
// the render, never a number shown in the wrong row.
func (d Data) TbdRows() ([]TbdRow, error) {
	if err := d.pairedProjects(); err != nil {
		return nil, err
	}
	rows := make([]TbdRow, len(d.Mainline))
	for i, m := range d.Mainline {
		rows[i] = TbdRow{Interval: m, Lead: d.MainlineLead[i], Developers: d.Developers[i],
			Push: d.PushMeasures[i], Deploy: d.DeployMeasures[i], Volume: d.DeploymentVolumes[i],
			pullsUncollected: d.PullsUncollected}
	}
	return rows, nil
}

// pairedProjects says why the TBD page's measures do not name the Mainline's
// projects one each in its order, or nil when they do.
func (d Data) pairedProjects() error {
	checks := []error{
		pairedWithMainline(d.Mainline, "Mainline Lead Times", d.MainlineLead,
			func(m metrics.MainlineLeadTime) string { return m.Project }),
		pairedWithMainline(d.Mainline, "push measures", d.PushMeasures,
			func(m metrics.PushMeasures) string { return m.Project }),
		pairedWithMainline(d.Mainline, "deployment measures", d.DeployMeasures,
			func(m metrics.DeployMeasures) string { return m.Project }),
		pairedWithMainline(d.Mainline, "deployment volumes", d.DeploymentVolumes,
			func(m metrics.DeploymentVolume) string { return m.Project }),
		pairedWithMainline(d.Mainline, "Developers", d.Developers,
			func(m metrics.Developers) string { return m.Project }),
	}
	return errors.Join(checks...)
}

// pairedWithMainline says why others, kind on the page, do not name the
// Mainline's projects one each in its order, or nil when they do.
func pairedWithMainline[T any](mainline []metrics.MainlineInterval, kind string, others []T,
	project func(T) string,
) error {
	if len(others) != len(mainline) {
		return fmt.Errorf("the TBD page has %d Mainline Intervals and %d %s", len(mainline), len(others), kind)
	}
	for i, m := range mainline {
		if other := project(others[i]); other != m.Project {
			return fmt.Errorf("the TBD page's row %d has the Mainline Interval of %q and the %s of %q",
				i+1, m.Project, kind, other)
		}
	}
	return nil
}
