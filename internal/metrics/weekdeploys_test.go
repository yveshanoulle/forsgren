package metrics

import (
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// The highest Deploys share of a Week row (forsgren#597): the weekday with
// the most deployments of the row, successful plus failed (forsgren#601),
// every tied day, none for a row without deployments, as the highest Failed
// is marked (forsgren#545).

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
	row := WeekRow{Deployments: [weekdays]int{4, 5, 9, 1, 0, 3, 7}}
	wantHighestDays(t, "deployments highest", row.DeploymentsHighest, [weekdays]bool{2: true})
}

// TestWeekHighestDeploymentsCountsTheFailedOnesToo: Sunday's 7 successful
// and 30 failed deployments are the most (forsgren#601).
func TestWeekHighestDeploymentsCountsTheFailedOnesToo(t *testing.T) {
	row := WeekRow{Deployments: [weekdays]int{4, 5, 9, 1, 0, 3, 7}, Failed: [weekdays]int{0, 0, 0, 0, 0, 0, 30}}
	wantHighestDays(t, "deployments highest with failures", row.DeploymentsHighest, [weekdays]bool{6: true})
}

func TestWeekHighestDeploymentsMarksEveryTiedDay(t *testing.T) {
	row := WeekRow{Deployments: [weekdays]int{6, 0, 2, 6, 0, 0, 6}}
	wantHighestDays(t, "tied deployments highest", row.DeploymentsHighest, [weekdays]bool{0: true, 3: true, 6: true})
}

func TestWeekHighestDeploymentsMarksNothingForARowWithoutDeployments(t *testing.T) {
	wantHighestDays(t, "deployments highest without deployments", (WeekRow{}).DeploymentsHighest, [weekdays]bool{})
}

// TestWeekHighestDeploymentsMarksADayWithOnlyFailedOnes (forsgren#601).
func TestWeekHighestDeploymentsMarksADayWithOnlyFailedOnes(t *testing.T) {
	row := WeekRow{Failed: [weekdays]int{0, 2, 0, 0, 0, 0, 0}}
	wantHighestDays(t, "deployments highest with only failures", row.DeploymentsHighest, [weekdays]bool{1: true})
}

// TestWeekDeploymentsCellsCountSuccessfulPlusFailed: 5 successful and 8
// failed deployments are 13 deployments, the shares over 13, a weekday with
// only failed ones above 0%; Failed and Fail rate as before (forsgren#601).
func TestWeekDeploymentsCellsCountSuccessfulPlusFailed(t *testing.T) {
	row := WeekRow{Deployments: [weekdays]int{3, 2, 0, 0, 0, 0, 0}, Failed: [weekdays]int{2, 0, 6, 0, 0, 0, 0}}
	for _, c := range []struct{ name, got, want string }{
		{"deployments total", row.DeploymentsTotalCell(), "13"},
		{"failed total", row.FailedTotalCell(), "8"},
		{"fail rate total", row.FailRateTotalCell(), "61%"},
		{"Monday share", row.DeploymentsShareCell(0), "38%"},
		{"Tuesday share", row.DeploymentsShareCell(1), "15%"},
		{"Wednesday share, failed only", row.DeploymentsShareCell(2), "46%"},
		{"Thursday share", row.DeploymentsShareCell(3), "0%"},
	} {
		if c.got != c.want {
			t.Errorf("%s: want %q, got %q", c.name, c.want, c.got)
		}
	}
}

// TestWeekDeploymentsLeaveOtherStatesOut: a deployment of state other is not
// one of the row's deployments (forsgren#601).
func TestWeekDeploymentsLeaveOtherStatesOut(t *testing.T) {
	var recs []history.Record
	for _, state := range []history.State{history.StateSuccess, history.StateFailure, history.StateOther} {
		recs = append(recs, history.Record{Repository: "acme/app", State: state, CreatedAt: now})
	}
	projects := []config.Project{{Name: "Acme Shop", Repositories: []config.Repository{{Name: "acme/app"}}}}
	row := weekRowNamed(t, WeekOf(projects, Data{Records: recs}, now), "Acme Shop")
	if got, want := row.DeploymentsTotalCell(), "2"; got != want {
		t.Errorf("deployments total with an other state: want %q, got %q", want, got)
	}
}
