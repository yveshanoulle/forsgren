package metrics

import (
	"slices"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// now is the pinned render time of these tests.
var now = time.Date(2026, 10, 3, 12, 0, 0, 0, time.UTC)

// projects are two made-up projects, in config order.
var projects = []config.Project{
	{Name: "Acme Shop", Repositories: []config.Repository{{Name: "acme/app"}, {Name: "acme/api"}}},
	{Name: "Acme Tools", Repositories: []config.Repository{{Name: "acme/cli"}}},
}

// deployed is a record of repository in state, created ago before now.
func deployed(repository string, state history.State, ago time.Duration) history.Record {
	return history.Record{
		Project: "any", Repository: repository, Kind: history.KindEnvironment, Name: "production",
		ID: 1, Commit: "0123456789abcdef0123456789abcdef01234567", CreatedAt: now.Add(-ago), State: state,
	}
}

// success is a successful deployment of acme/app, ago before now.
func success(ago time.Duration) history.Record {
	return deployed("acme/app", history.StateSuccess, ago)
}

// shopOf returns Acme Shop's frequency for records.
func shopOf(t *testing.T, records ...history.Record) Frequency {
	t.Helper()
	got := DeploymentFrequency(projects, records, now)
	if len(got) != 2 {
		t.Fatalf("want one Frequency per project, 2, got %d", len(got))
	}
	return got[0]
}

// counts is what a Frequency counted, to compare in one step.
type counts struct {
	last7, last30, last180 int
	has                    bool
}

func countsOf(f Frequency) counts { return counts{f.Last7, f.Last30, f.Last180, f.HasDeployments()} }

// TestWindowEdges pins the windows: at or after now minus 7 (30, 180) days
// of 24 hours, and not after now. Exactly 7 days old is in the 7-day count;
// one second older is not.
func TestWindowEdges(t *testing.T) {
	cases := []struct {
		name string
		ago  time.Duration
		want counts
	}{
		{"now", 0, counts{1, 1, 1, true}},
		{"exactly 7 days", 7 * day, counts{1, 1, 1, true}},
		{"7 days and a second", 7*day + time.Second, counts{0, 1, 1, true}},
		{"exactly 30 days", 30 * day, counts{0, 1, 1, true}},
		{"30 days and a second", 30*day + time.Second, counts{0, 0, 1, true}},
		{"exactly 180 days", 180 * day, counts{0, 0, 1, true}},
		{"180 days and a second", 180*day + time.Second, counts{0, 0, 0, true}},
		{"a second after now", -time.Second, counts{0, 0, 0, true}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := countsOf(shopOf(t, success(c.ago))); got != c.want {
				t.Errorf("want %+v, got %+v", c.want, got)
			}
		})
	}
}

// TestCountsEverySuccessOfEveryRepository: each success of each of the
// project's repositories counts on its own (forsgren#11 splits later).
func TestCountsEverySuccessOfEveryRepository(t *testing.T) {
	f := shopOf(t, success(time.Hour), success(2*day),
		deployed("acme/api", history.StateSuccess, 3*day), success(10*day), success(40*day), success(200*day))
	if got := countsOf(f); got != (counts{3, 4, 5, true}) {
		t.Errorf("want 3 in 7 days, 4 in 30 and 5 in 180, got %+v", got)
	}
}

// TestFailureAndOtherDoNotCount: only success is a deployment; a project
// with failures alone has no deployment and no latest date.
func TestFailureAndOtherDoNotCount(t *testing.T) {
	f := shopOf(t, deployed("acme/app", history.StateFailure, time.Hour),
		deployed("acme/app", history.StateOther, 2*time.Hour))
	if got := countsOf(f); got != (counts{}) {
		t.Errorf("want nothing counted, got %+v", got)
	}
}

// TestLatestIsTheNewestSuccess: the latest is the newest success's,
// whatever the file order, and a newer failure does not move it.
func TestLatestIsTheNewestSuccess(t *testing.T) {
	f := shopOf(t, success(40*day), success(2*day+13*time.Hour), success(9*day),
		deployed("acme/app", history.StateFailure, time.Hour))
	if want := now.Add(-2*day - 13*time.Hour); !f.Latest.Equal(want) {
		t.Errorf("want the latest %v, got %v (%+v)", want, f.Latest, f)
	}
}

// TestProjectsInConfigOrderWithTheirOwnRecords: one Frequency per project,
// in config order, each with its own repositories' records only (names
// compared ignoring case, as the config does); a repository no project
// lists is left out.
func TestProjectsInConfigOrderWithTheirOwnRecords(t *testing.T) {
	got := DeploymentFrequency(projects, []history.Record{
		deployed("Acme/CLI", history.StateSuccess, time.Hour),
		deployed("acme/gone", history.StateSuccess, time.Hour),
		success(time.Hour), success(2 * time.Hour),
	}, now)
	want := []struct {
		project string
		last30  int
	}{{"Acme Shop", 2}, {"Acme Tools", 1}}
	if len(got) != len(want) {
		t.Fatalf("want %d projects, got %+v", len(want), got)
	}
	for i, w := range want {
		if got[i].Project != w.project || got[i].Last30 != w.last30 {
			t.Errorf("project %d: want %s with %d, got %+v", i, w.project, w.last30, got[i])
		}
	}
}

// TestEmptyHistory: every project is there, with no deployment and the
// slowest band; no project gives no Frequency.
func TestEmptyHistory(t *testing.T) {
	got := DeploymentFrequency(projects, nil, now)
	want := []Frequency{
		{Project: "Acme Shop", Band: LessThanSixMonthly},
		{Project: "Acme Tools", Band: LessThanSixMonthly},
	}
	if !slices.Equal(got, want) {
		t.Errorf("want %+v, got %+v", want, got)
	}
	if none := DeploymentFrequency(nil, []history.Record{success(time.Hour)}, now); len(none) != 0 {
		t.Errorf("want no Frequency without projects, got %+v", none)
	}
}

// shopWithSuccessesAt is Acme Shop's frequency with one success at each age.
func shopWithSuccessesAt(t *testing.T, ages ...time.Duration) Frequency {
	t.Helper()
	records := make([]history.Record, 0, len(ages))
	for _, ago := range ages {
		records = append(records, success(ago))
	}
	return shopOf(t, records...)
}

// daysAgo is one age per day from first to last days ago, both included.
func daysAgo(first, last int) []time.Duration {
	ages := make([]time.Duration, 0, last-first+1)
	for d := first; d <= last; d++ {
		ages = append(ages, time.Duration(d)*day)
	}
	return ages
}

// TestBandFollowsTheThirtyDayCount: the band comes from Last30 whenever it
// holds a deployment, whatever else the 180 days hold.
func TestBandFollowsTheThirtyDayCount(t *testing.T) {
	cases := []struct {
		name string
		ages []time.Duration
		want Band
	}{
		{"30 in 30 days", daysAgo(0, 29), HourlyToDaily},
		{"5 in 30 days", daysAgo(0, 4), DailyToWeekly},
		{"1 in 30 days and 10 older", daysAgo(30, 40), WeeklyToMonthly},
	}
	for _, c := range cases {
		if f := shopWithSuccessesAt(t, c.ages...); f.Band != c.want {
			t.Errorf("%s: want %v, got %+v", c.name, c.want, f)
		}
	}
}

// TestBandFallsBackToTheLast180Days (forsgren#16, step 6): with no
// deployment in the last 30 days, the 180-day count tells the two slowest
// bands apart.
func TestBandFallsBackToTheLast180Days(t *testing.T) {
	if f := shopWithSuccessesAt(t, 31*day, 100*day, 200*day); f.Band != MonthlyToSixMonthly || f.Last180 != 2 {
		t.Errorf("want 2 in 180 days between once per month and once every six months, got %+v", f)
	}
	if f := shopWithSuccessesAt(t, 181*day); f.Band != LessThanSixMonthly || !f.HasDeployments() {
		t.Errorf("want a deployment older than 180 days less than once per six months, got %+v", f)
	}
}
