package page

import (
	"fmt"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// The TBD page (forsgren#253): a table of the Mainline Interval of each
// project, its Mainline Lead Time (forsgren#256) and its Developers
// (forsgren#273), or one line that says why there is none.

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

// TbdRow is one project's row of the TBD page: its Mainline Interval, its
// Mainline Lead Time (forsgren#256, step 2) and its Developers (forsgren#273,
// step 3).
type TbdRow struct {
	Interval   metrics.MainlineInterval
	Lead       metrics.MainlineLeadTime
	Developers metrics.Developers
	// pullsUncollected is Data.PullsUncollected.
	pullsUncollected bool
}

// LeadCell is the row's Mainline Lead Time cell: MainlineLeadTime.Cell, or
// pullsUncollectedCell while the pull requests have not been collected,
// unless a refused read makes the project not readable (forsgren#337, step
// 2), which Cell says.
func (r TbdRow) LeadCell() string {
	if r.pullsUncollected && !r.Lead.NotReadable {
		return pullsUncollectedCell
	}
	return r.Lead.Cell()
}

// TbdRows pairs each Mainline Interval with the Mainline Lead Time and the
// Developers of its project, in the Mainline's order. All three come from the
// config's projects in its order, so a Mainline Lead Time or Developers that
// is missing or names another project in a row is an error, which fails the
// render, never a number shown in the wrong row.
func (d Data) TbdRows() ([]TbdRow, error) {
	if err := pairedWithMainline(d.Mainline, "Mainline Lead Times", d.MainlineLead,
		func(m metrics.MainlineLeadTime) string { return m.Project }); err != nil {
		return nil, err
	}
	if err := pairedWithMainline(d.Mainline, "Developers", d.Developers,
		func(m metrics.Developers) string { return m.Project }); err != nil {
		return nil, err
	}
	rows := make([]TbdRow, len(d.Mainline))
	for i, m := range d.Mainline {
		rows[i] = TbdRow{Interval: m, Lead: d.MainlineLead[i], Developers: d.Developers[i],
			pullsUncollected: d.PullsUncollected}
	}
	return rows, nil
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
