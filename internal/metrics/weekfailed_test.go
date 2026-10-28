package metrics

import (
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// The Failed and Fail rate columns of the Week table (forsgren#545, decision
// #546): Failed is the share of the row's failed deployments (state failure)
// on a weekday, a count in Total; Fail rate is the failures of the weekday
// over its finished deployments (success, failure and other), over the
// window in Total; the highest weekday value of each is marked.

// TestWeekFailedAreTheFailuresOfTheWindowAndFinishedAreAllFinishedOnes: a
// failure before the window is left out, an other deployment is finished but
// not failed, and Deployments stays the successes.
func TestWeekFailedAreTheFailuresOfTheWindowAndFinishedAreAllFinishedOnes(t *testing.T) {
	w := WeekOf(weekProjects(), weekData(), now)
	for _, c := range []struct {
		row              string
		failed, finished [weekdays]int
	}{
		{"Website", [weekdays]int{0, 1, 0, 0, 0, 0, 0}, [weekdays]int{1, 1, 0, 2, 0, 0, 1}},
		{"Acme Shop", [weekdays]int{0, 1, 1, 0, 0, 0, 0}, [weekdays]int{1, 1, 2, 2, 1, 2, 2}},
		{"API", [weekdays]int{0, 0, 1, 0, 0, 0, 0}, [weekdays]int{0, 0, 1, 0, 1, 1, 0}},
		{"ADMIN", [weekdays]int{}, [weekdays]int{0, 0, 0, 0, 0, 1, 1}},
		{"Extra", [weekdays]int{}, [weekdays]int{0, 0, 1, 0, 0, 0, 0}},
	} {
		got := weekRowNamed(t, w, c.row)
		if got.Failed != c.failed {
			t.Errorf("%s failed Mon..Sun: want %v, got %v", c.row, c.failed, got.Failed)
		}
		if got.Finished != c.finished {
			t.Errorf("%s finished Mon..Sun: want %v, got %v", c.row, c.finished, got.Finished)
		}
	}
	if want := [weekdays]int{1, 0, 0, 1, 0, 0, 1}; weekRowNamed(t, w, "Website").Deployments != want {
		t.Errorf("Deployments stays the successes: want %v", want)
	}
}

// TestWeekFailedOfARuleAreItsOwn: the rule row counts its own deployments.
func TestWeekFailedOfARuleAreItsOwn(t *testing.T) {
	production := config.Deployment{Kind: config.Environment, Name: "production"}
	projects := []config.Project{{Name: "Acme Shop", Repositories: []config.Repository{
		{Name: "acme/app", Rules: []config.Rule{{Label: "Prod", Deployment: production}}},
	}}}
	got := weekRowNamed(t, WeekOf(projects, weekData(), now), "Prod")
	if want := [weekdays]int{0, 0, 1, 0, 0, 0, 0}; got.Failed != want {
		t.Errorf("Prod failed Mon..Sun: want %v, got %v", want, got.Failed)
	}
	if want := [weekdays]int{0, 0, 1, 0, 1, 2, 1}; got.Finished != want {
		t.Errorf("Prod finished Mon..Sun: want %v, got %v", want, got.Finished)
	}
}

func TestWeekFailedCellsAreSharesOfTheFailuresAndACountInTotal(t *testing.T) {
	row := WeekRow{Failed: [weekdays]int{1, 0, 3, 0, 0, 0, 0}, Finished: [weekdays]int{5, 2, 12, 0, 0, 0, 0}}
	if got, want := row.FailedTotalCell(), "4"; got != want {
		t.Errorf("failed total: want %q, got %q", want, got)
	}
	for day, want := range []string{"25%", "0%", "75%", "0%", "0%", "0%", "0%"} {
		if got := row.FailedShareCell(day); got != want {
			t.Errorf("failed day %d: want %q, got %q", day, want, got)
		}
	}
}

func TestWeekFailRateIsFailedOverFinishedPerWeekdayAndOverTheWindowInTotal(t *testing.T) {
	row := WeekRow{Failed: [weekdays]int{1, 0, 3, 0, 0, 0, 0}, Finished: [weekdays]int{5, 2, 12, 0, 0, 0, 0}}
	for day, want := range []string{"20%", "0%", "25%", "-", "-", "-", "-"} {
		if got := row.FailRateCell(day); got != want {
			t.Errorf("fail rate day %d: want %q, got %q", day, want, got)
		}
	}
	if got, want := row.FailRateTotalCell(), "21%"; got != want {
		t.Errorf("fail rate total: want %q, got %q", want, got)
	}
}

func TestWeekRowWithoutFailuresReadsDashesForFailedAndZeroRatesWhereItDeployed(t *testing.T) {
	row := WeekRow{Finished: [weekdays]int{0, 4, 0, 0, 0, 0, 0}}
	for _, c := range []struct{ name, got, want string }{
		{"failed total", row.FailedTotalCell(), "0"},
		{"failed share", row.FailedShareCell(1), "-"},
		{"fail rate on a day with deployments", row.FailRateCell(1), "0%"},
		{"fail rate on a day without", row.FailRateCell(0), "-"},
		{"fail rate total", row.FailRateTotalCell(), "0%"},
		{"fail rate total without any deployment", (WeekRow{}).FailRateTotalCell(), "-"},
	} {
		if c.got != c.want {
			t.Errorf("%s: want %q, got %q", c.name, c.want, c.got)
		}
	}
}

func TestWeekHighestMarksTheDayWithTheMostFailuresAndEveryTiedDay(t *testing.T) {
	row := WeekRow{Failed: [weekdays]int{1, 0, 3, 0, 0, 0, 3}, Finished: [weekdays]int{5, 5, 12, 1, 0, 3, 10}}
	for day, want := range []bool{false, false, true, false, false, false, true} {
		if got := row.FailedHighest(day); got != want {
			t.Errorf("failed highest day %d: want %v, got %v", day, want, got)
		}
	}
}

func TestWeekHighestFailRateIsTheHighestRateNotTheHighestCount(t *testing.T) {
	row := WeekRow{Failed: [weekdays]int{1, 0, 3, 0, 0, 0, 3}, Finished: [weekdays]int{5, 5, 12, 1, 0, 3, 10}}
	for day, want := range []bool{false, false, false, false, false, false, true} {
		if got := row.FailRateHighest(day); got != want {
			t.Errorf("fail rate highest day %d: want %v, got %v", day, want, got)
		}
	}
	tied := WeekRow{Failed: [weekdays]int{1, 2, 0, 0, 0, 0, 0}, Finished: [weekdays]int{2, 4, 7, 0, 0, 0, 0}}
	for day, want := range []bool{true, true, false, false, false, false, false} {
		if got := tied.FailRateHighest(day); got != want {
			t.Errorf("tied fail rate highest day %d: want %v, got %v", day, want, got)
		}
	}
}

func TestWeekHighestMarksNothingForARowWithoutFailures(t *testing.T) {
	row := WeekRow{Finished: [weekdays]int{3, 1, 0, 0, 0, 0, 2}}
	for day := range weekdays {
		if row.FailedHighest(day) || row.FailRateHighest(day) {
			t.Errorf("day %d: want nothing marked for a row without failures", day)
		}
	}
}
