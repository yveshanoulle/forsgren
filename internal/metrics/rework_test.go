package metrics

import (
	"strconv"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// Deployment rework rate (forsgren#39): a rework deployment is a successful
// deployment that is the first success of its stream after a failed
// deployment, or was created while a failure issue of its repository was
// open; each counted once. The rate is the rework deployments out of the
// successful deployments of the last 30 days, banded on change fail rate's
// six labels, as DORA's Quick Check scales rework rate the same way
// (dora.dev/quickcheck/quickcheck.js).

// reworkWant is what a ReworkRate measured, to compare in one step.
type reworkWant struct {
	deployments, rework, percent int
	band                         ChangeFailBand
	text                         string
}

func reworkOf(r ReworkRate) reworkWant {
	return reworkWant{r.Deployments, r.Rework, r.Percent(), r.Band, r.Cell()}
}

// shopRework is Acme Shop's rework rate for records and failures; it fails
// the test unless Acme Tools follows it with none.
func shopRework(t *testing.T, records []history.Record, failures []history.Failure) ReworkRate {
	t.Helper()
	all := ReworkRates(projects, records, failures, now)
	if len(all) != 2 || all[0].Project != "Acme Shop" || all[1] != (ReworkRate{Project: "Acme Tools"}) {
		t.Fatalf("want Acme Shop's rate, then Acme Tools with nothing, got %+v", all)
	}
	return all[0]
}

// wantRework fails the test unless Acme Shop's rework rate is want.
func wantRework(t *testing.T, want reworkWant, records []history.Record, failures ...history.Failure) {
	t.Helper()
	if got := reworkOf(shopRework(t, records, failures)); got != want {
		t.Errorf("want %+v,\n got %+v", want, got)
	}
}

// plain is n successful deployments of acme/app, ten days before now: in
// the window, after no failure and before any issue of these tests.
func plain(n int) []history.Record {
	return times(n, deployed("acme/app", history.StateSuccess, 10*day))
}

// withPlain is records and n plain successes.
func withPlain(n int, records ...history.Record) []history.Record {
	return append(records, plain(n)...)
}

// openFor is a failure issue of repository opened ago before now and closed
// closedAgo before now; a closedAgo of 0 is not closed yet.
func openFor(repository string, ago, closedAgo time.Duration) history.Failure {
	f := filed(repository, ago)
	if closedAgo != 0 {
		f.ClosedAt = now.Add(-closedAgo)
	}
	return f
}

func TestAFirstSuccessAfterAFailedDeploymentIsRework(t *testing.T) {
	wantRework(t, reworkWant{7, 1, 14, TwentyPercent, "20% · 14% (1 of 7)"},
		withPlain(6, failed(3*day), fixed(day)))
}

func TestOnlyTheFirstSuccessAfterTheFailuresIsRework(t *testing.T) {
	wantRework(t, reworkWant{2, 1, 50, SixtyPercent, "60% · 50% (1 of 2)"},
		[]history.Record{failed(4 * day), failed(3 * day), fixed(2 * day), fixed(day)})
}

func TestAFailureInAnotherStreamMakesNoRework(t *testing.T) {
	wantRework(t, reworkWant{1, 0, 0, ZeroPercent, "0% · 0% (0 of 1)"},
		[]history.Record{to(deployAdmin, history.StateFailure, 2*day), fixed(day)})
}

func TestADeploymentWhileAFailureIssueIsOpenIsRework(t *testing.T) {
	wantRework(t, reworkWant{7, 1, 14, TwentyPercent, "20% · 14% (1 of 7)"},
		withPlain(6, success(day)), openFor("acme/app", 2*day, 0))
}

func TestEveryDeploymentWhileAnIssueIsOpenIsRework(t *testing.T) {
	wantRework(t, reworkWant{7, 3, 42, FortyPercent, "40% · 42% (3 of 7)"},
		withPlain(4, success(day), success(2*day), success(3*day)), openFor("ACME/app", 4*day, 0))
}

func TestADeploymentOfBothKindsCountsOnce(t *testing.T) {
	wantRework(t, reworkWant{7, 1, 14, TwentyPercent, "20% · 14% (1 of 7)"},
		withPlain(6, failed(3*day), fixed(day)), openFor("acme/app", 2*day, 0))
}

func TestAnIssueMakesReworkOnlyWhileItIsOpenAtTheDeployment(t *testing.T) {
	for name, issue := range map[string]history.Failure{
		"closed before it":     openFor("acme/app", 3*day, 2*day),
		"closed at it":         openFor("acme/app", 3*day, day),
		"opened after it":      openFor("acme/app", day/2, 0),
		"opened after now":     filed("acme/app", -time.Second),
		"of another repo":      openFor("stranger/app", 3*day, 0),
		"of a repo not listed": openFor("acme/other", 3*day, 0),
	} {
		t.Run(name, func(t *testing.T) {
			wantRework(t, reworkWant{1, 0, 0, ZeroPercent, "0% · 0% (0 of 1)"},
				[]history.Record{success(day)}, issue)
		})
	}
	for name, issue := range map[string]history.Failure{
		"closed after it": openFor("acme/app", 3*day, day/2),
		"opened at it":    openFor("acme/app", day, 0),
	} {
		t.Run(name, func(t *testing.T) {
			wantRework(t, reworkWant{1, 1, 100, HundredPercent, "100% · 100% (1 of 1)"},
				[]history.Record{success(day)}, issue)
		})
	}
}

func TestTheRepositoriesOfAProjectAddUpInRework(t *testing.T) {
	records := []history.Record{
		deployed("acme/app", history.StateFailure, 2*day), deployed("acme/app", history.StateSuccess, day),
		deployed("acme/api", history.StateSuccess, day),
		deployed("stranger/app", history.StateFailure, 2*day), deployed("stranger/app", history.StateSuccess, day),
	}
	wantRework(t, reworkWant{2, 1, 50, SixtyPercent, "60% · 50% (1 of 2)"}, records)
}

func TestOnlySuccessesOfTheLast30DaysCountInRework(t *testing.T) {
	wantRework(t, reworkWant{1, 1, 100, HundredPercent, "100% · 100% (1 of 1)"},
		[]history.Record{failed(40 * day), fixed(30 * day)})
	wantRework(t, reworkWant{text: "No successful deployments"},
		[]history.Record{failed(40 * day), fixed(30*day + time.Second)})
	wantRework(t, reworkWant{text: "No successful deployments"},
		[]history.Record{failed(day), fixed(-time.Second)})
	wantRework(t, reworkWant{1, 0, 0, ZeroPercent, "0% · 0% (0 of 1)"},
		[]history.Record{success(day), failed(-time.Second)})
}

func TestNoSuccessfulDeploymentIsNoReworkRate(t *testing.T) {
	wantRework(t, reworkWant{text: "No successful deployments"}, nil)
	wantRework(t, reworkWant{text: "No successful deployments"},
		[]history.Record{failed(day)}, openFor("acme/app", 2*day, 0))
}

// TestReworkBandEdges: rework out of successes is banded on the six labels
// of the Quick Check, a rate halfway between two by the higher one.
func TestReworkBandEdges(t *testing.T) {
	for _, c := range []struct {
		rework, successes int
		want              ChangeFailBand
	}{
		{0, 10, ZeroPercent}, {1, 11, ZeroPercent}, {1, 10, TwentyPercent}, {3, 11, TwentyPercent},
		{3, 10, FortyPercent}, {1, 2, SixtyPercent}, {7, 10, EightyPercent}, {9, 10, HundredPercent},
	} {
		var records []history.Record
		for i := 0; i < c.rework; i++ {
			name := "env" + strconv.Itoa(i)
			records = append(records, to(name, history.StateFailure, 3*day), to(name, history.StateSuccess, 2*day))
		}
		records = append(records, plain(c.successes-c.rework)...)
		got := ReworkRates(projects, records, nil, now)[0]
		if got.Deployments != c.successes || got.Rework != c.rework || got.Band != c.want {
			t.Errorf("%d of %d: want band %q, got %d of %d, %q", c.rework, c.successes, c.want,
				got.Rework, got.Deployments, got.Band)
		}
	}
}
