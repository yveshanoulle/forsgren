package metrics

import "testing"

// The Week table's cells (forsgren#531, step 2, decision #534 A): a day is
// `commits · deployments` with the thousands rule of forsgren#528, 0 · 0 for
// no activity, the dot between no-break spaces; a row Per repository writes
// an en dash for its commits (decision #539 A); the weekend share is written as the TBD shares are.

func TestWeekDayCellIsCommitsDotDeployments(t *testing.T) {
	row := WeekRow{Commits: [weekdays]int{3, 0, 1234, 0, 0, 0, 0}, Deployments: [weekdays]int{4, 0, 0, 12, 0, 0, 0}}
	for day, want := range []string{
		"3 · 4", "0 · 0", "1 234 · 0", "0 · 12", "0 · 0",
	} {
		if got := row.DayCell(day); got != want {
			t.Errorf("day %d: want %q, got %q", day, want, got)
		}
	}
}

func TestWeekDayCellOfARowPerRepositoryKeepsItsDeployments(t *testing.T) {
	row := WeekRow{PerRepository: true, Deployments: [weekdays]int{0, 3, 0, 0, 0, 0, 0}}
	if got, want := row.DayCell(1), "– · 3"; got != want {
		t.Errorf("want %q, got %q", want, got)
	}
	if got, want := row.DayCell(0), "– · 0"; got != want {
		t.Errorf("want %q, got %q", want, got)
	}
}

func TestWeekendShareCellIsAShareOfTheCommits(t *testing.T) {
	for name, c := range map[string]struct {
		row  WeekRow
		want string
	}{
		"3 of 5":         {WeekRow{Commits: [weekdays]int{1, 0, 1, 0, 0, 2, 1}}, "60%"},
		"none of 3":      {WeekRow{Commits: [weekdays]int{3, 0, 0, 0, 0, 0, 0}}, "0%"},
		"1 of 200":       {WeekRow{Commits: [weekdays]int{199, 0, 0, 0, 0, 1, 0}}, "0.50%"},
		"no commit":      {WeekRow{Deployments: [weekdays]int{0, 0, 0, 0, 0, 5, 0}}, "-"},
		"per repository": {WeekRow{PerRepository: true}, "Per repository"},
	} {
		if got := c.row.WeekendShareCell(); got != c.want {
			t.Errorf("%s: want %q, got %q", name, c.want, got)
		}
	}
}
