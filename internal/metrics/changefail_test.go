package metrics

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// filed is a failure issue of repository, opened ago before now.
func filed(repository string, ago time.Duration) history.Failure {
	return history.Failure{Repository: repository, Issue: 42, OpenedAt: now.Add(-ago)}
}

// times is n copies of r.
func times[T any](n int, r T) []T {
	out := make([]T, n)
	for i := range out {
		out[i] = r
	}
	return out
}

// mixed is successes successful and failures failed deployments of
// repository, all a day before now.
func mixed(repository string, successes, failures int) []history.Record {
	return append(times(successes, deployed(repository, history.StateSuccess, day)),
		times(failures, deployed(repository, history.StateFailure, day))...)
}

// rate is what a ChangeFailRate measured, to compare in one step.
type rate struct {
	deployments, failedDeployments, failureIssues, failed, percent int
	band                                                           ChangeFailBand
	text                                                           string
}

func rateOf(r ChangeFailRate) rate {
	return rate{r.Deployments, r.FailedDeployments, r.FailureIssues, r.Failed, r.Percent(), r.Band, r.BandText()}
}

// wantRate fails the test unless Acme Shop's change fail rate for records
// and failures is want, and Acme Tools has none.
func wantRate(t *testing.T, want rate, records []history.Record, failures ...history.Failure) {
	t.Helper()
	got := ChangeFailRates(projects, records, failures, now)
	if len(got) != 2 {
		t.Fatalf("want one ChangeFailRate per project, 2, got %d", len(got))
	}
	if r := rateOf(got[0]); r != want {
		t.Errorf("want %+v,\n got %+v", want, r)
	}
	if got[0].Project != "Acme Shop" || got[1] != (ChangeFailRate{Project: "Acme Tools"}) {
		t.Errorf("want Acme Shop, then Acme Tools with nothing, got %+v", got)
	}
}

// TestChangeFailRateCountsFailedDeploymentsOfAllFinalOnes (forsgren#18):
// the share of the final deployments of the last 30 days, successes and
// failures, that failed; whole percent, rounded down.
func TestChangeFailRateCountsFailedDeploymentsOfAllFinalOnes(t *testing.T) {
	wantRate(t, rate{25, 2, 0, 2, 8, ZeroPercent,
		"0% — 8% of 25 deployments failed (2 failed deployments, 0 failure issues) in the last 30 days"},
		mixed("acme/app", 23, 2))
}

// TestAFailureIssueAndAFailedDeploymentOfOneRepositoryCountOnce: per
// repository, the failed changes are the larger of its failed deployments
// and its failure issues, so an issue filed about a failed deployment is
// not counted twice; both counts are shown.
func TestAFailureIssueAndAFailedDeploymentOfOneRepositoryCountOnce(t *testing.T) {
	wantRate(t, rate{25, 2, 1, 2, 8, ZeroPercent,
		"0% — 8% of 25 deployments failed (2 failed deployments, 1 failure issue) in the last 30 days"},
		mixed("acme/app", 23, 2), filed("acme/app", day))
}

// TestTheRepositoriesOfAProjectAddUp: each repository's larger count, then
// their sum: a failed deployment of acme/app and a failure issue of
// acme/api are two failed changes.
func TestTheRepositoriesOfAProjectAddUp(t *testing.T) {
	wantRate(t, rate{10, 1, 1, 2, 20, TwentyPercent,
		"20% — 20% of 10 deployments failed (1 failed deployment, 1 failure issue) in the last 30 days"},
		append(mixed("acme/app", 4, 1), mixed("acme/api", 5, 0)...), filed("acme/api", day))
}

// TestFailureIssuesAloneAreTheFailedChanges: a repository whose
// deployments all succeed (a crash users hit after a good upload) fails by
// its issues.
func TestFailureIssuesAloneAreTheFailedChanges(t *testing.T) {
	wantRate(t, rate{10, 0, 3, 3, 30, FortyPercent,
		"40% — 30% of 10 deployments failed (0 failed deployments, 3 failure issues) in the last 30 days"},
		mixed("acme/app", 10, 0), times(3, filed("acme/app", 2*day))...)
}

// TestMoreFailedChangesThanDeploymentsIsAllOfThem: a change fail rate is at
// most 100%; the counts still show what was found.
func TestMoreFailedChangesThanDeploymentsIsAllOfThem(t *testing.T) {
	wantRate(t, rate{2, 0, 3, 2, 100, HundredPercent,
		"100% — 100% of 2 deployments failed (0 failed deployments, 3 failure issues) in the last 30 days"},
		mixed("acme/app", 2, 0), times(3, filed("acme/app", day))...)
}

// TestOnlyTheLast30DaysOfConfiguredRepositoriesCount: a deployment or an
// issue older than 30 days, or after the render time, is not counted, nor
// one of a repository no project lists, nor a deployment in another final
// state; repository names ignore case.
func TestOnlyTheLast30DaysOfConfiguredRepositoriesCount(t *testing.T) {
	records := []history.Record{
		deployed("Acme/App", history.StateSuccess, 30*day),
		deployed("acme/app", history.StateFailure, 30*day),
		deployed("acme/app", history.StateFailure, 30*day+time.Second),
		deployed("acme/app", history.StateFailure, -time.Second),
		deployed("acme/app", history.StateOther, day),
		deployed("stranger/app", history.StateFailure, day),
	}
	wantRate(t, rate{2, 1, 1, 1, 50, SixtyPercent,
		"60% — 50% of 2 deployments failed (1 failed deployment, 1 failure issue) in the last 30 days"},
		records, filed("ACME/app", 30*day), filed("acme/app", 30*day+time.Second), filed("acme/app", -time.Second),
		filed("stranger/app", day))
}

// TestNoDeploymentsInTheWindowIsNoRate: no band, and a failure issue of
// the window is still named.
func TestNoDeploymentsInTheWindowIsNoRate(t *testing.T) {
	wantRate(t, rate{text: "No deployments in the last 30 days"}, nil)
	wantRate(t, rate{failureIssues: 1, text: "No deployments in the last 30 days; 1 failure issue"},
		[]history.Record{deployed("acme/app", history.StateSuccess, 40*day)}, filed("acme/app", day))
}

// TestChangeFailBandOf pins the bands: DORA's Quick Check asks for change
// fail rate as a percentage and shows it on a scale labelled 0%, 20%, 40%,
// 60%, 80% and 100%; a rate is banded by the nearest label, and a rate
// halfway between two (10%, 30%, ...) by the higher one. Compared exactly,
// never as a rounded number.
func TestChangeFailBandOf(t *testing.T) {
	for _, c := range []struct {
		failed, deployments int
		want                ChangeFailBand
		name                string
	}{
		{0, 0, 0, "No band"},
		{0, 10, ZeroPercent, "0%"},
		{99, 1000, ZeroPercent, "0%"},
		{1, 10, TwentyPercent, "20%"},
		{299, 1000, TwentyPercent, "20%"},
		{3, 10, FortyPercent, "40%"},
		{1, 3, FortyPercent, "40%"},
		{1, 2, SixtyPercent, "60%"},
		{2, 3, SixtyPercent, "60%"},
		{7, 10, EightyPercent, "80%"},
		{899, 1000, EightyPercent, "80%"},
		{9, 10, HundredPercent, "100%"},
		{3, 3, HundredPercent, "100%"},
	} {
		got := ChangeFailBandOf(c.failed, c.deployments)
		if got != c.want || got.String() != c.name {
			t.Errorf("%d of %d: want %d %q, got %d %q", c.failed, c.deployments, c.want, c.name, got, got)
		}
	}
}

// TestThePercentIsRoundedDown, so the percent shown and its band always
// agree: 199 of 200 is 99%, 2 of 3 is 66%.
func TestThePercentIsRoundedDown(t *testing.T) {
	for _, c := range []struct{ failed, deployments, want int }{{199, 200, 99}, {2, 3, 66}, {1, 3, 33}, {0, 7, 0}} {
		r := ChangeFailRate{Deployments: c.deployments, Failed: c.failed}
		if got := r.Percent(); got != c.want {
			t.Errorf("%d of %d: want %d%%, got %d%%", c.failed, c.deployments, c.want, got)
		}
	}
}
