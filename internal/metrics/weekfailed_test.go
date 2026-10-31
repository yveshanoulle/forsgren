package metrics

import (
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// The Failed and Fail rate columns of the Week table (forsgren#545, decision
// #546): Failed is the share of the row's failed deployments (state failure)
// on a weekday, a count in Total; Fail rate is the failures of the weekday
// over its successful plus failed deployments (other states left out,
// forsgren#547), over the window in Total; the highest weekday value of each is marked.

// TestWeekFailedAreTheFailuresOfTheWindow: a failure before the window is
// left out, an other deployment is not failed, and Deployments stays the
// successes.
func TestWeekFailedAreTheFailuresOfTheWindow(t *testing.T) {
	w := WeekOf(weekProjects(), weekData(), now)
	for _, c := range []struct {
		row    string
		failed [weekdays]int
	}{
		{"Website", [weekdays]int{0, 1, 0, 0, 0, 0, 0}},
		{"Acme Shop", [weekdays]int{0, 1, 1, 0, 0, 0, 0}},
		{"API", [weekdays]int{0, 0, 1, 0, 0, 0, 0}},
		{"ADMIN", [weekdays]int{}},
		{"Extra", [weekdays]int{}},
	} {
		got := weekRowNamed(t, w, c.row)
		if got.Failed != c.failed {
			t.Errorf("%s failed Mon..Sun: want %v, got %v", c.row, c.failed, got.Failed)
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
}

func TestWeekFailedCellsAreSharesOfTheFailuresAndACountInTotal(t *testing.T) {
	row := WeekRow{Failed: [weekdays]int{1, 0, 3, 0, 0, 0, 0}, Deployments: [weekdays]int{4, 2, 9, 0, 0, 0, 0}}
	if got, want := row.FailedTotalCell(), "4"; got != want {
		t.Errorf("failed total: want %q, got %q", want, got)
	}
	for day, want := range []string{"25%", "0%", "75%", "0%", "0%", "0%", "0%"} {
		if got := row.FailedShareCell(day); got != want {
			t.Errorf("failed day %d: want %q, got %q", day, want, got)
		}
	}
}

func TestWeekFailRateIsFailedOverSuccessfulPlusFailedPerWeekdayAndInTotal(t *testing.T) {
	row := WeekRow{Failed: [weekdays]int{1, 0, 3, 0, 0, 0, 0}, Deployments: [weekdays]int{4, 2, 9, 0, 0, 0, 0}}
	for day, want := range []string{"20%", "0%", "25%", "-", "-", "-", "-"} {
		if got := row.FailRateCell(day); got != want {
			t.Errorf("fail rate day %d: want %q, got %q", day, want, got)
		}
	}
	if got, want := row.FailRateTotalCell(), "21%"; got != want {
		t.Errorf("fail rate total: want %q, got %q", want, got)
	}
}

// Yves's example (decision #546): 8 successes, 2 failures and 5 other
// deployments are 20%, not 13.3%; a weekday with only other reads a dash.
func TestWeekFailRateLeavesOtherStatesOut(t *testing.T) {
	var recs []history.Record
	add := func(day int, state history.State, n int) {
		for range n {
			recs = append(recs, history.Record{Repository: "acme/app", State: state, CreatedAt: now.AddDate(0, 0, -day)})
		}
	}
	add(0, history.StateSuccess, 8)
	add(0, history.StateFailure, 2)
	add(0, history.StateOther, 5)
	add(1, history.StateOther, 3)
	projects := []config.Project{{Name: "Acme Shop", Repositories: []config.Repository{{Name: "acme/app"}}}}
	row := weekRowNamed(t, WeekOf(projects, Data{Records: recs}, now), "Acme Shop")
	if got, want := row.FailRateCell(weekdayOf(now)), "20%"; got != want {
		t.Errorf("fail rate with other states: want %q, got %q", want, got)
	}
	if got, want := row.FailRateCell(weekdayOf(now.AddDate(0, 0, -1))), "-"; got != want {
		t.Errorf("fail rate of a weekday with only other: want %q, got %q", want, got)
	}
	if got, want := row.FailRateTotalCell(), "20%"; got != want {
		t.Errorf("fail rate total: want %q, got %q", want, got)
	}
}

func TestWeekRowWithoutFailuresReadsDashesForFailedAndZeroRatesWhereItDeployed(t *testing.T) {
	row := WeekRow{Deployments: [weekdays]int{0, 4, 0, 0, 0, 0, 0}}
	for _, c := range []struct{ name, got, want string }{
		{"failed total", row.FailedTotalCell(), "0"},
		{"failed share", row.FailedShareCell(1), "-"},
		{"fail rate on a day with successes", row.FailRateCell(1), "0%"},
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
	row := WeekRow{Failed: [weekdays]int{1, 0, 3, 0, 0, 0, 3}, Deployments: [weekdays]int{4, 5, 9, 1, 0, 3, 7}}
	wantHighestDays(t, "failed highest", row.FailedHighest, [weekdays]bool{2: true, 6: true})
}

func TestWeekHighestFailRateIsTheHighestRateNotTheHighestCount(t *testing.T) {
	row := WeekRow{Failed: [weekdays]int{1, 0, 3, 0, 0, 0, 3}, Deployments: [weekdays]int{4, 5, 9, 1, 0, 3, 7}}
	wantHighestDays(t, "fail rate highest", row.FailRateHighest, [weekdays]bool{6: true})
	tied := WeekRow{Failed: [weekdays]int{1, 2, 0, 0, 0, 0, 0}, Deployments: [weekdays]int{1, 2, 7, 0, 0, 0, 0}}
	wantHighestDays(t, "tied fail rate highest", tied.FailRateHighest, [weekdays]bool{0: true, 1: true})
}

func TestWeekHighestMarksNothingForARowWithoutFailures(t *testing.T) {
	row := WeekRow{Deployments: [weekdays]int{3, 1, 0, 0, 0, 0, 2}}
	for day := range weekdays {
		if row.FailedHighest(day) || row.FailRateHighest(day) {
			t.Errorf("day %d: want nothing marked for a row without failures", day)
		}
	}
}
