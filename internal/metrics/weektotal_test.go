package metrics

import "testing"

// The Total row of the Week table (forsgren#552, decision #553 A).

// weekForTotal has two projects, the first with a label row whose counts are
// already in its project's row.
func weekForTotal() Week {
	return Week{Rows: []WeekRow{
		{Level: ProjectRow, Name: "Acme Shop", Project: "Acme Shop",
			Commits: [weekdays]int{3, 0, 1, 0, 0, 0, 2}, Deployments: [weekdays]int{1, 2, 0, 0, 4, 0, 0},
			Failed: [weekdays]int{0, 1, 0, 0, 0, 0, 1}},
		{Level: LabelRow, Name: "Website", Project: "Acme Shop", Service: true, PerRepository: true,
			Deployments: [weekdays]int{1, 2, 0, 0, 0, 0, 0}, Failed: [weekdays]int{0, 1, 0, 0, 0, 0, 0}},
		{Level: ProjectRow, Name: "Acme Docs", Project: "Acme Docs",
			Commits: [weekdays]int{0, 5, 0, 0, 0, 0, 1}, Deployments: [weekdays]int{0, 0, 3, 0, 0, 0, 1},
			Failed: [weekdays]int{2, 0, 0, 0, 0, 0, 0}},
	}}
}

// TestWeekTotalSumsTheProjectRowsOnly: the label row is not counted twice.
func TestWeekTotalSumsTheProjectRowsOnly(t *testing.T) {
	got := weekForTotal().Total()
	want := WeekRow{Level: ProjectRow, Name: "Total", Project: "Total",
		Commits: [weekdays]int{3, 5, 1, 0, 0, 0, 3}, Deployments: [weekdays]int{1, 2, 3, 0, 4, 0, 1},
		Failed: [weekdays]int{2, 1, 0, 0, 0, 0, 1}}
	if got != want {
		t.Errorf("Total row: want %+v, got %+v", want, got)
	}
}

// TestWeekTotalFailRateIsTheRateOfTheSums: 4 failed of 15 successful plus
// failed, not a mean of the projects' rates.
func TestWeekTotalFailRateIsTheRateOfTheSums(t *testing.T) {
	if got, want := weekForTotal().Total().FailRateTotalCell(), "26%"; got != want {
		t.Errorf("Total fail rate: want %q, got %q", want, got)
	}
}
