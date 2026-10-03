package metrics

import (
	"slices"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// The two environments of acme/app the recovery tests deploy to: two
// streams that never mix.
const (
	deployAPI   = "deploy-api"
	deployAdmin = "deploy-admin"
)

// to is a deployment of acme/app to the environment name, in state,
// created ago before now.
func to(name string, state history.State, ago time.Duration) history.Record {
	r := deployed("acme/app", state, ago)
	r.Name = name
	return r
}

// failed is a failed deployment of deploy-api, ago before now.
func failed(ago time.Duration) history.Record { return to(deployAPI, history.StateFailure, ago) }

// fixed is a successful deployment of deploy-api, ago before now.
func fixed(ago time.Duration) history.Record { return to(deployAPI, history.StateSuccess, ago) }

// shopRecovery returns Acme Shop's recovery time for records.
func shopRecovery(t *testing.T, records ...history.Record) Recovery {
	t.Helper()
	got := RecoveryTimes(projects, records, now)
	if len(got) != 2 {
		t.Fatalf("want one Recovery per project, 2, got %d", len(got))
	}
	return got[0]
}

// outcome is what a Recovery measured, to compare in one step.
type outcome struct {
	recoveries  int
	median      time.Duration
	band        LeadTimeBand
	unrecovered int
	text        string
}

func outcomeOf(r Recovery) outcome {
	return outcome{r.Recoveries, r.Median, r.Band, r.Unrecovered, r.BandText()}
}

// wantOutcome fails the test unless Acme Shop's recovery for records is
// want.
func wantOutcome(t *testing.T, want outcome, records ...history.Record) {
	t.Helper()
	if got := outcomeOf(shopRecovery(t, records...)); got != want {
		t.Errorf("want %+v,\n got %+v", want, got)
	}
}

// TestOneFailureAndItsRecovery (forsgren#17): a failed deployment recovered
// by the next success of its stream recovers in the time between their
// creation times.
func TestOneFailureAndItsRecovery(t *testing.T) {
	wantOutcome(t, outcome{1, 3 * time.Hour, LessThanOneDay, 0,
		"Less than one day — median 3 hours over 1 recovery in the last 30 days"},
		fixed(10*time.Hour), failed(5*time.Hour), fixed(2*time.Hour))
}

// TestARunOfFailuresIsOneRecovery: failures one after the other before a
// success are one recovery, timed from the first failure of the run, when
// the service was first degraded. A success before the run recovers
// nothing, and an other state neither starts nor ends a run.
func TestARunOfFailuresIsOneRecovery(t *testing.T) {
	other := to(deployAPI, history.StateOther, 3*time.Hour)
	wantOutcome(t, outcome{1, 6 * time.Hour, LessThanOneDay, 0,
		"Less than one day — median 6 hours over 1 recovery in the last 30 days"},
		fixed(12*time.Hour), failed(8*time.Hour), failed(5*time.Hour), other, failed(4*time.Hour), fixed(2*time.Hour))
}

// TestMedianOfTheRecoveries: the median of two recoveries is their mean, as
// for lead time, and the text uses the plural.
func TestMedianOfTheRecoveries(t *testing.T) {
	wantOutcome(t, outcome{2, 3 * time.Hour, LessThanOneDay, 0,
		"Less than one day — median 3 hours over 2 recoveries in the last 30 days"},
		failed(20*time.Hour), fixed(18*time.Hour), failed(10*time.Hour), fixed(6*time.Hour))
}

// TestFailureNotRecoveredYet: a failure with no later success of its
// stream is not recovered yet. It is counted and shown, but it is not in
// the median, whatever its age.
func TestFailureNotRecoveredYet(t *testing.T) {
	t.Run("alone", func(t *testing.T) {
		wantOutcome(t, outcome{0, 0, 0, 1, "No recovery in the last 30 days; 1 failure not recovered yet"},
			fixed(10*time.Hour), failed(2*time.Hour), failed(time.Hour))
	})
	t.Run("old", func(t *testing.T) {
		wantOutcome(t, outcome{0, 0, 0, 1, "No recovery in the last 30 days; 1 failure not recovered yet"},
			failed(90*day))
	})
	t.Run("next to a recovery", func(t *testing.T) {
		admin := to(deployAdmin, history.StateFailure, time.Hour)
		wantOutcome(t, outcome{1, 30 * time.Minute, LessThanOneHour, 2,
			"Less than one hour — median 30 minutes over 1 recovery in the last 30 days; " +
				"2 failures not recovered yet"},
			failed(5*time.Hour), fixed(270*time.Minute), failed(2*time.Hour), admin)
	})
}

// TestStreamsDoNotMix: a success recovers only a failure of its own
// stream, the stream as collect defines it (forsgren#16): the repository
// ignoring case, the kind, the environment or workflow, and the task; a
// repository's releases are one stream, whatever their tags.
func TestStreamsDoNotMix(t *testing.T) {
	t.Run("deploy-api versus deploy-admin", func(t *testing.T) {
		admin := to(deployAdmin, history.StateSuccess, 4*time.Hour)
		wantOutcome(t, outcome{1, 4 * time.Hour, LessThanOneDay, 0,
			"Less than one day — median 4 hours over 1 recovery in the last 30 days"},
			failed(5*time.Hour), admin, fixed(time.Hour))
	})
	t.Run("repository ignoring case", func(t *testing.T) {
		upper := failed(5 * time.Hour)
		upper.Repository = "Acme/App"
		wantOutcome(t, outcome{1, 4 * time.Hour, LessThanOneDay, 0,
			"Less than one day — median 4 hours over 1 recovery in the last 30 days"},
			upper, fixed(time.Hour))
	})
	t.Run("kind and task", func(t *testing.T) {
		workflow, task := fixed(3*time.Hour), fixed(2*time.Hour)
		workflow.Kind, task.Task = history.KindWorkflow, "migrate"
		wantOutcome(t, outcome{0, 0, 0, 1, "No recovery in the last 30 days; 1 failure not recovered yet"},
			failed(5*time.Hour), workflow, task)
	})
	t.Run("releases are one stream", func(t *testing.T) {
		tagged := func(r history.Record, tag string) history.Record {
			r.Kind, r.Name, r.Task = history.KindRelease, "", tag
			return r
		}
		wantOutcome(t, outcome{1, 4 * time.Hour, LessThanOneDay, 0,
			"Less than one day — median 4 hours over 1 recovery in the last 30 days"},
			tagged(failed(5*time.Hour), "v1.0.0"), tagged(fixed(time.Hour), "v1.0.1"))
	})
}

// TestRecoveryWindowEdges: a recovery counts when its success was created
// in the last 30 days, both ends included, counted back from now as the
// other numbers are; a deployment after now is not there yet.
func TestRecoveryWindowEdges(t *testing.T) {
	cases := []struct {
		name string
		ago  time.Duration
		want int
	}{
		{"now", 0, 1},
		{"exactly 30 days", 30 * day, 1},
		{"30 days and a second", 30*day + time.Second, 0},
		{"a second after now", -time.Second, 0},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := shopRecovery(t, failed(c.ago+time.Hour), fixed(c.ago))
			if got.Recoveries != c.want {
				t.Errorf("want %d recoveries, got %+v", c.want, got)
			}
		})
	}
}

// TestDeploymentsAfterNowAreNotThereYet: a success created after the render
// time does not recover a failure, which stays not recovered yet, and a
// failure created after it is not counted at all.
func TestDeploymentsAfterNowAreNotThereYet(t *testing.T) {
	wantOutcome(t, outcome{0, 0, 0, 1, "No recovery in the last 30 days; 1 failure not recovered yet"},
		failed(time.Hour), fixed(-time.Second))
	wantOutcome(t, outcome{0, 0, 0, 0, "No failed deployments in the last 30 days"},
		fixed(time.Hour), failed(-time.Second))
}

// TestRecoveryBandOfEachEdge (forsgren#17): DORA's Quick Check answers for
// failure recovery are lead time's six, so a median recovery time falls in
// lead time's bands, on the same edges; a month is 30 days.
func TestRecoveryBandOfEachEdge(t *testing.T) {
	cases := []struct {
		median time.Duration
		want   LeadTimeBand
	}{
		{0, LessThanOneHour},
		{time.Hour - time.Second, LessThanOneHour},
		{time.Hour, LessThanOneDay},
		{day - time.Second, LessThanOneDay},
		{day, OneDayToOneWeek},
		{7*day - time.Second, OneDayToOneWeek},
		{7 * day, OneWeekToOneMonth},
		{30*day - time.Second, OneWeekToOneMonth},
		{30 * day, OneToSixMonths},
		{180*day - time.Second, OneToSixMonths},
		{180 * day, MoreThanSixMonths},
	}
	for _, c := range cases {
		got := shopRecovery(t, failed(c.median+time.Hour), fixed(time.Hour))
		if got.Band != c.want || got.Median != c.median {
			t.Errorf("recovered in %v: want band %v, got %v (median %v)", c.median, c.want, got.Band, got.Median)
		}
	}
}

// projectTexts is each Recovery's project and text, in order.
func projectTexts(recoveries []Recovery) []string {
	out := make([]string, 0, len(recoveries))
	for _, r := range recoveries {
		out = append(out, r.Project+": "+r.BandText())
	}
	return out
}

// TestNoFailedDeployments: without a failure, each project, in config
// order, says so; a failure of a repository no project lists is left out.
func TestNoFailedDeployments(t *testing.T) {
	gone := deployed("acme/gone", history.StateFailure, time.Hour)
	want := []string{
		"Acme Shop: No failed deployments in the last 30 days",
		"Acme Tools: No failed deployments in the last 30 days",
	}
	for _, records := range [][]history.Record{nil, {fixed(time.Hour), gone}} {
		if got := projectTexts(RecoveryTimes(projects, records, now)); !slices.Equal(got, want) {
			t.Errorf("want %q, got %q", want, got)
		}
	}
}

// TestRecoveryPerProject: a recovery belongs to the project whose config
// lists its repository.
func TestRecoveryPerProject(t *testing.T) {
	cli := func(state history.State, ago time.Duration) history.Record { return deployed("acme/cli", state, ago) }
	got := RecoveryTimes(projects, []history.Record{cli(history.StateFailure, 3*time.Hour),
		cli(history.StateSuccess, time.Hour)}, now)
	want := []string{
		"Acme Shop: No failed deployments in the last 30 days",
		"Acme Tools: Less than one day — median 2 hours over 1 recovery in the last 30 days",
	}
	if texts := projectTexts(got); !slices.Equal(texts, want) {
		t.Errorf("want the recovery in Acme Tools only, %q, got %q", want, texts)
	}
}
