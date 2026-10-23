package page

import (
	"fmt"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// The TBD page (forsgren#253): a table of the Mainline Interval of each
// project and its Developers (forsgren#273), or one line that says why there
// is none.

// tbdTitle is the TBD page's title, its h1 and the legend's heading for it,
// as Yves wrote it (forsgren#271): the name, then the beta marker the History
// page has too (betaMarker, " (BETA)", in capitals).
const tbdTitle = "Trunk-based development [TBD]" + betaMarker

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

// TbdRow is one project's row of the TBD page: its Mainline Interval and its
// Developers (forsgren#273, step 3).
type TbdRow struct {
	Interval   metrics.MainlineInterval
	Developers metrics.Developers
}

// TbdRows pairs each Mainline Interval with the Developers of its project, in
// the Mainline's order. Both come from the config's projects in its order, so
// Developers that are missing or name another project in a row are an error,
// which fails the render, never a count shown in the wrong row.
func (d Data) TbdRows() ([]TbdRow, error) {
	if len(d.Developers) != len(d.Mainline) {
		return nil, fmt.Errorf("the TBD page has %d Mainline Intervals and %d Developers", len(d.Mainline), len(d.Developers))
	}
	rows := make([]TbdRow, len(d.Mainline))
	for i, m := range d.Mainline {
		if m.Project != d.Developers[i].Project {
			return nil, fmt.Errorf("the TBD page's row %d has the Mainline Interval of %q and the Developers of %q",
				i+1, m.Project, d.Developers[i].Project)
		}
		rows[i] = TbdRow{Interval: m, Developers: d.Developers[i]}
	}
	return rows, nil
}
