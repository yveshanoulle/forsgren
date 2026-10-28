package metrics

// The Total row of the Week table (forsgren#552, decision #553 A): the sum of
// every project row, so a label, service or rule row, already in its
// project's row, is not counted twice. Its cells are a project row's cells,
// the Fail rate the failed over the successful plus failed deployments of the
// sums (forsgren#547).

// weekTotalName is the Total row's name and header.
const weekTotalName = "Total"

// Total is the Week table's Total row: per weekday, the commits, the
// successful and the failed deployments of every project row added up.
func (w Week) Total() WeekRow {
	total := WeekRow{Level: ProjectRow, Name: weekTotalName, Project: weekTotalName}
	for _, row := range w.Rows {
		if row.Level == ProjectRow {
			total.Commits = addDays(total.Commits, row.Commits)
			total.Deployments = addDays(total.Deployments, row.Deployments)
			total.Failed = addDays(total.Failed, row.Failed)
		}
	}
	return total
}

// addDays is the per-weekday sum of two rows of counts.
func addDays(a, b [weekdays]int) [weekdays]int {
	for day := range weekdays {
		a[day] += b[day]
	}
	return a
}
