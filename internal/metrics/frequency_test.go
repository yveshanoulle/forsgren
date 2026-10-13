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
	got := DeploymentFrequency(projects, records, config.DefaultWorkingHours, now)
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
	}, config.DefaultWorkingHours, now)
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
	got := DeploymentFrequency(projects, nil, config.DefaultWorkingHours, now)
	want := []Frequency{
		{Project: "Acme Shop", Band: LessThanSixMonthly},
		{Project: "Acme Tools", Band: LessThanSixMonthly},
	}
	if !slices.Equal(got, want) {
		t.Errorf("want %+v, got %+v", want, got)
	}
	recorded := []history.Record{success(time.Hour)}
	if none := DeploymentFrequency(nil, recorded, config.DefaultWorkingHours, now); len(none) != 0 {
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
		{"5 in 30 days", append(daysAgo(0, 4), 40*day), DailyToWeekly},
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

// youngAges is one success first ago before now, and n-1 more an hour ago.
func youngAges(n int, first time.Duration) []time.Duration {
	ages := []time.Duration{first}
	for len(ages) < n {
		ages = append(ages, time.Hour)
	}
	return ages
}

// TestBandScalesAProjectYoungerThanThirtyDays (forsgren#69): when the first
// success is less than 30 days old, the band uses Last30 times 30 over the
// age in whole days, at least 1; an older project is not scaled.
func TestBandScalesAProjectYoungerThanThirtyDays(t *testing.T) {
	cases := []struct {
		name string
		ages []time.Duration
		want Band
	}{
		{"19 in 9 days is 63 in 30", youngAges(19, 9*day), HourlyToDaily},
		{"19 first 40 days ago is not scaled", youngAges(19, 40*day), DailyToWeekly},
		{"1 today is age 1, so 30", youngAges(1, 0), HourlyToDaily},
		{"5 in 5.5 days is age 5, so 30", youngAges(5, 5*day+12*time.Hour), HourlyToDaily},
	}
	for _, c := range cases {
		if f := shopWithSuccessesAt(t, c.ages...); f.Band != c.want {
			t.Errorf("%s: want %v, got %+v", c.name, c.want, f)
		}
	}
}

// TestFrequencyBandFollowsWorkingHours (forsgren#71): the working hours given
// to DeploymentFrequency reach the band, through Rows as well. A project
// first deployed 40 days ago is not scaled, so its 30-day count is as stored.
func TestFrequencyBandFollowsWorkingHours(t *testing.T) {
	cases := []struct {
		hours, count int
		want         Band
	}{
		{24, 720, HourlyToDaily},
		{24, 721, OnDemand},
		{1, 31, OnDemand},
		{config.DefaultWorkingHours, 240, HourlyToDaily},
	}
	for _, c := range cases {
		records := []history.Record{success(40 * day)}
		for range c.count {
			records = append(records, success(2*day))
		}
		if got := DeploymentFrequency(projects, records, c.hours, now)[0].Band; got != c.want {
			t.Errorf("%d hours, %d in 30 days: want %v, got %v", c.hours, c.count, c.want, got)
		}
		rows := Rows(projects[:1], Data{Records: records, WorkingHours: c.hours}, now)
		if got := rows[0].Frequency.Band; got != c.want {
			t.Errorf("Rows, %d hours, %d in 30 days: want %v, got %v", c.hours, c.count, c.want, got)
		}
	}
}

// TestWeekendDeploymentsCountOnlySaturdayAndSundayUTC pins forsgren#115:
// Weekend30 counts the successes of the last 30 days created on a UTC
// Saturday or Sunday, at the edges of both days; a failure, an other and a
// success older than 30 days do not count.
func TestWeekendDeploymentsCountOnlySaturdayAndSundayUTC(t *testing.T) {
	at := func(day, hour, min, sec int) time.Time { return time.Date(2026, 9, day, hour, min, sec, 0, time.UTC) }
	record := func(state history.State, created time.Time) history.Record {
		r := success(0)
		r.State, r.CreatedAt = state, created
		return r
	}
	// 2026-09-25 is a Friday, 26 a Saturday, 27 a Sunday, 28 a Monday.
	saturday := at(26, 12, 0, 0)
	got := shopOf(t,
		record(history.StateSuccess, at(25, 23, 59, 59)),
		record(history.StateSuccess, at(26, 0, 0, 0)),
		record(history.StateSuccess, at(27, 23, 59, 59)),
		record(history.StateSuccess, at(28, 0, 0, 0)),
		record(history.StateFailure, saturday),
		record(history.StateOther, saturday),
		record(history.StateSuccess, time.Date(2026, 8, 29, 12, 0, 0, 0, time.UTC)), // a Saturday, 35 days ago
	)
	if got.Weekend30 != 2 {
		t.Errorf("want 2 weekend successes in the last 30 days, got %d", got.Weekend30)
	}
}

// TestWeekendDeploymentsAlsoCountedOverTheLast180Days pins forsgren#115:
// with no success in the last 30 days, Weekend180 counts the successes of
// the last 180 days created on a UTC Saturday or Sunday: a Saturday 98 days
// ago counts, a Tuesday 60 days ago and a Saturday 196 days ago do not.
func TestWeekendDeploymentsAlsoCountedOverTheLast180Days(t *testing.T) {
	at := func(month time.Month, day int) history.Record {
		r := success(0)
		r.CreatedAt = time.Date(2026, month, day, 12, 0, 0, 0, time.UTC)
		return r
	}
	got := shopOf(t, at(time.June, 27), at(time.August, 4), at(time.March, 21))
	if got.Last30 != 0 || got.Last180 != 2 {
		t.Fatalf("want 0 successes in 30 days and 2 in 180, got %d and %d", got.Last30, got.Last180)
	}
	if got.Weekend180 != 1 {
		t.Errorf("want 1 weekend success in the last 180 days, got %d", got.Weekend180)
	}
}
