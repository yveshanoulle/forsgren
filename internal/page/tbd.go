package page

// The TBD page (forsgren#253): a table of the Mainline Interval of each
// project, or one line that says why there is none.

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
