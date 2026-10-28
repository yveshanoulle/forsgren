package metrics

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// incident is a failure issue of acme/app: users were hit start before now
// (zero: the issue's body names no failure-start), the issue was opened
// opened before now and closed closed before now (zero: still open).
func incident(start, opened, closed time.Duration) history.Failure {
	f := openFor("acme/app", opened, closed)
	if start > 0 {
		f.FailureStart = now.Add(-start)
	}
	return f
}

// issueRecovery is Acme Shop's recovery time for records and issues over
// days.
func issueRecovery(days int, issues []history.Failure, records ...history.Record) Recovery {
	return RecoveryTimes(projects, Data{Records: records, Failures: issues, DoraDays: days}, now)[0]
}

// TestAFailureIssueIsARecoveryFromItsFailureStart (forsgren#53): a closed
// failure issue with no failed deployment is one recovery, from its
// `failure-start:` time to its closing.
func TestAFailureIssueIsARecoveryFromItsFailureStart(t *testing.T) {
	got := outcomeOf(issueRecovery(30, []history.Failure{incident(5*time.Hour, 4*time.Hour, 2*time.Hour)}))
	want := outcome{1, 3 * time.Hour, LessThanOneDay, 0, "Less than one day · 3 h (1)"}
	if got != want {
		t.Errorf("want %+v,\n got %+v", want, got)
	}
}

// TestAFailureIssueWithoutAStartIsTimedFromItsOpening (forsgren#53).
func TestAFailureIssueWithoutAStartIsTimedFromItsOpening(t *testing.T) {
	got := issueRecovery(30, []history.Failure{incident(0, 4*time.Hour, 2*time.Hour)})
	if got.Recoveries != 1 || got.Median != 2*time.Hour {
		t.Errorf("want 1 recovery of 2 h, got %d of %v", got.Recoveries, got.Median)
	}
}

// TestAnOpenFailureIssueIsARecoveryNotCompletedYet (forsgren#53): as a run
// of failed deployments with no success after it, whatever its age.
func TestAnOpenFailureIssueIsARecoveryNotCompletedYet(t *testing.T) {
	for _, days := range []int{30, 90, 180} {
		got := outcomeOf(issueRecovery(days, []history.Failure{incident(0, 300*day, 0)}))
		want := outcome{0, 0, 0, 1, "— · 1 recovery not completed yet"}
		if got != want {
			t.Errorf("%d days: want %+v,\n got %+v", days, want, got)
		}
	}
}

// TestAFailureIssueCountsWhenItWasClosedInTheWindow (forsgren#53): a close
// 45 days ago is in the 90-day window and not in the 30-day one.
func TestAFailureIssueCountsWhenItWasClosedInTheWindow(t *testing.T) {
	issues := []history.Failure{incident(0, 45*day+time.Hour, 45*day)}
	for days, want := range map[int]int{30: 0, 90: 1, 180: 1} {
		if got := issueRecovery(days, issues).Recoveries; got != want {
			t.Errorf("%d days: want %d recoveries, got %d", days, want, got)
		}
	}
}

// TestAnIssueAndAFailedDeploymentOfOneIncidentCountOnce (forsgren#53): an
// issue whose time overlaps a run of failed deployments of its repository
// is that incident, so the deployments' recovery counts and the issue's
// does not, as change fail rate counts the larger of the two, not both.
func TestAnIssueAndAFailedDeploymentOfOneIncidentCountOnce(t *testing.T) {
	issue := incident(0, 4*time.Hour, time.Hour) // inside the run below
	got := outcomeOf(issueRecovery(30, []history.Failure{issue}, failed(5*time.Hour), fixed(2*time.Hour)))
	want := outcome{1, 3 * time.Hour, LessThanOneDay, 0, "Less than one day · 3 h (1)"}
	if got != want {
		t.Errorf("want %+v,\n got %+v", want, got)
	}
}

// TestAnOpenIssueInsideAnOpenRunCountsOnce (forsgren#53).
func TestAnOpenIssueInsideAnOpenRunCountsOnce(t *testing.T) {
	got := issueRecovery(30, []history.Failure{incident(0, time.Hour, 0)}, failed(5*time.Hour))
	if got.Unrecovered != 1 || got.Recoveries != 0 {
		t.Errorf("want 1 not completed, 0 recovered, got %d, %d", got.Unrecovered, got.Recoveries)
	}
}

// TestAnIssueApartFromTheFailedDeploymentsIsAnotherRecovery (forsgren#53):
// a run of failed deployments and an issue that do not overlap are two
// incidents, the median of their two times.
func TestAnIssueApartFromTheFailedDeploymentsIsAnotherRecovery(t *testing.T) {
	issue := incident(0, 10*time.Hour, 8*time.Hour) // 2 h, before the run
	got := issueRecovery(30, []history.Failure{issue}, failed(5*time.Hour), fixed(2*time.Hour))
	if got.Recoveries != 2 || got.Median != 150*time.Minute {
		t.Errorf("want 2 recoveries, median 2 h 30, got %d, %v", got.Recoveries, got.Median)
	}
}

// TestAnIssueOfAnotherRepositoryNeverOverlaps (forsgren#53): the overlap
// is per repository; an issue of a repository the project does not list
// counts nowhere.
func TestAnIssueOfAnotherRepositoryNeverOverlaps(t *testing.T) {
	other := incident(0, 4*time.Hour, time.Hour)
	other.Repository = "acme/api"
	unlisted := incident(0, 4*time.Hour, time.Hour)
	unlisted.Repository = "acme/elsewhere"
	got := issueRecovery(30, []history.Failure{other, unlisted}, failed(5*time.Hour), fixed(2*time.Hour))
	if got.Recoveries != 2 {
		t.Errorf("want 2 recoveries (the run and acme/api's issue), got %d", got.Recoveries)
	}
}

// TestFailureIssuesLeaveReworkRateAsItWas (forsgren#53): rework reads the
// issues as before, whatever recovery time now counts.
func TestFailureIssuesLeaveReworkRateAsItWas(t *testing.T) {
	records := []history.Record{fixed(3 * time.Hour), fixed(time.Hour)}
	issues := []history.Failure{incident(0, 4*time.Hour, 2*time.Hour)}
	got := ReworkRates(projects, Data{Records: records, Failures: issues, DoraDays: 30}, now)[0]
	if got.Deployments != 2 || got.Rework != 1 {
		t.Errorf("want 1 rework of 2, got %d of %d", got.Rework, got.Deployments)
	}
}
