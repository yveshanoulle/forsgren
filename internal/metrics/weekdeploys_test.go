package metrics

import "testing"

// The highest Deploys share of a Week row (forsgren#597): the weekday with
// the most successful deployments of the row, every tied day, none for a row
// without deployments, as the highest Failed is marked (forsgren#545).

// wantHighestDays checks highest against want for each weekday, Monday first.
func wantHighestDays(t *testing.T, what string, highest func(day int) bool, want [weekdays]bool) {
	t.Helper()
	for day := range weekdays {
		if got := highest(day); got != want[day] {
			t.Errorf("%s day %d: want %v, got %v", what, day, want[day], got)
		}
	}
}

func TestWeekHighestDeploymentsIsTheDayWithTheMostDeployments(t *testing.T) {
	row := WeekRow{Deployments: [weekdays]int{4, 5, 9, 1, 0, 3, 7}, Failed: [weekdays]int{0, 0, 0, 0, 0, 0, 30}}
	wantHighestDays(t, "deployments highest", row.DeploymentsHighest, [weekdays]bool{2: true})
}

func TestWeekHighestDeploymentsMarksEveryTiedDay(t *testing.T) {
	row := WeekRow{Deployments: [weekdays]int{6, 0, 2, 6, 0, 0, 6}}
	wantHighestDays(t, "tied deployments highest", row.DeploymentsHighest, [weekdays]bool{0: true, 3: true, 6: true})
}

func TestWeekHighestDeploymentsMarksNothingForARowWithoutDeployments(t *testing.T) {
	row := WeekRow{Failed: [weekdays]int{0, 2, 0, 0, 0, 0, 0}}
	wantHighestDays(t, "deployments highest without deployments", row.DeploymentsHighest, [weekdays]bool{})
}
