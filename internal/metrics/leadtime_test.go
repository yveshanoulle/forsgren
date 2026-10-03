package metrics

import (
	"slices"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// shippedCommit is a commit of repository, deployed ago before now and
// authored lead before that deployment.
func shippedCommit(repository string, ago, lead time.Duration) history.Commit {
	deployedAt := now.Add(-ago)
	return history.Commit{
		Repository: repository, Kind: history.KindEnvironment, DeploymentID: 1,
		SHA: "0123456789abcdef0123456789abcdef01234567", AuthoredAt: deployedAt.Add(-lead), DeployedAt: deployedAt,
	}
}

// shopCommit is a commit of acme/app deployed an hour ago, with lead time
// lead.
func shopCommit(lead time.Duration) history.Commit { return shippedCommit("acme/app", time.Hour, lead) }

// shopLeadTime returns Acme Shop's lead time for commits.
func shopLeadTime(t *testing.T, commits ...history.Commit) LeadTime {
	t.Helper()
	got := LeadTimes(projects, commits, now)
	if len(got) != 2 {
		t.Fatalf("want one LeadTime per project, 2, got %d", len(got))
	}
	return got[0]
}

// spread is what a LeadTime measured, to compare in one step.
type spread struct {
	commits int
	median  time.Duration
}

func spreadOf(l LeadTime) spread { return spread{l.Commits, l.Median} }

// TestMedianOfTheCommits pins the median: the middle lead time of an odd
// count, whatever the order; the mean of the two middle ones of an even
// count; a single commit's own lead time.
func TestMedianOfTheCommits(t *testing.T) {
	cases := []struct {
		name  string
		leads []time.Duration
		want  spread
	}{
		{"odd", []time.Duration{30 * time.Minute, 10 * time.Minute, 2 * day}, spread{3, 30 * time.Minute}},
		{"even", []time.Duration{50 * time.Minute, 10 * time.Minute, 20 * time.Minute, 30 * time.Minute},
			spread{4, 25 * time.Minute}},
		{"single", []time.Duration{17 * time.Minute}, spread{1, 17 * time.Minute}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			commits := make([]history.Commit, 0, len(c.leads))
			for _, lead := range c.leads {
				commits = append(commits, shopCommit(lead))
			}
			if got := spreadOf(shopLeadTime(t, commits...)); got != c.want {
				t.Errorf("want %+v, got %+v", c.want, got)
			}
		})
	}
}

// TestLeadTimeWindowEdges: a commit counts when its deployment is in the
// last 30 days, both ends included, as for deployment frequency.
func TestLeadTimeWindowEdges(t *testing.T) {
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
			if got := shopLeadTime(t, shippedCommit("acme/app", c.ago, time.Hour)).Commits; got != c.want {
				t.Errorf("want %d commits, got %d", c.want, got)
			}
		})
	}
}

// TestNegativeLeadTimeCountsAsZero: a commit authored after its deployment
// (a skewed clock) did ship, so it counts, with a lead time of 0, the
// nearest possible one. Dropped, the median would be 20 minutes over 1;
// counted as is, 5 minutes over 2.
func TestNegativeLeadTimeCountsAsZero(t *testing.T) {
	got := spreadOf(shopLeadTime(t, shopCommit(-10*time.Minute), shopCommit(20*time.Minute)))
	if want := (spread{2, 10 * time.Minute}); got != want {
		t.Errorf("want %+v, got %+v", want, got)
	}
}

// TestLeadTimeProjectsInConfigOrder: one LeadTime per project, in config
// order, each with the commits of its own repositories (compared ignoring
// case); a repository no project lists is left out. The band follows the
// median.
func TestLeadTimeProjectsInConfigOrder(t *testing.T) {
	got := LeadTimes(projects, []history.Commit{
		shippedCommit("Acme/CLI", time.Hour, 3*day),
		shippedCommit("acme/gone", time.Hour, time.Minute),
		shippedCommit("ACME/API", time.Hour, 2*time.Hour),
		shopCommit(4 * time.Hour),
	}, now)
	want := []LeadTime{
		{Project: "Acme Shop", Commits: 2, Median: 3 * time.Hour, Band: LessThanOneDay},
		{Project: "Acme Tools", Commits: 1, Median: 3 * day, Band: OneDayToOneWeek},
	}
	if !slices.Equal(got, want) {
		t.Errorf("want %+v, got %+v", want, got)
	}
}

// TestNoCommits: every project is there, with no commit and no band; no
// project gives no LeadTime.
func TestNoCommits(t *testing.T) {
	got := LeadTimes(projects, nil, now)
	want := []LeadTime{{Project: "Acme Shop"}, {Project: "Acme Tools"}}
	if !slices.Equal(got, want) {
		t.Errorf("want %+v, got %+v", want, got)
	}
	if none := LeadTimes(nil, []history.Commit{shopCommit(time.Minute)}, now); len(none) != 0 {
		t.Errorf("want no LeadTime without projects, got %+v", none)
	}
}

// TestLeadTimeBandText (forsgren#16, ruling 6): the band with the median,
// the count and the period, singular for one commit; "No lead time yet"
// without a commit in the window.
func TestLeadTimeBandText(t *testing.T) {
	cases := map[string]LeadTime{
		"Less than one hour — median 17 minutes over 37 commits in the last 30 days": {
			Commits: 37, Median: 17 * time.Minute, Band: LessThanOneHour,
		},
		"One to six months — median 45 days over 1 commit in the last 30 days": {
			Commits: 1, Median: 45 * day, Band: OneToSixMonths,
		},
		"No lead time yet": {},
	}
	for want, l := range cases {
		if got := l.BandText(); got != want {
			t.Errorf("want %q, got %q", want, got)
		}
	}
}

// TestHumanDuration pins the duration format: whole minutes below an hour,
// hours and minutes below a day, days and hours above; cut down, never
// rounded up, so a median never reads as the next band's edge; a zero part
// left out; singular for one.
func TestHumanDuration(t *testing.T) {
	cases := map[time.Duration]string{
		0:                                      "less than a minute",
		59 * time.Second:                       "less than a minute",
		time.Minute:                            "1 minute",
		17*time.Minute + 59*time.Second:        "17 minutes",
		time.Hour - time.Second:                "59 minutes",
		time.Hour:                              "1 hour",
		time.Hour + time.Minute:                "1 hour 1 minute",
		5*time.Hour + 12*time.Minute:           "5 hours 12 minutes",
		2*time.Hour + 30*time.Second:           "2 hours",
		24*time.Hour - time.Second:             "23 hours 59 minutes",
		24 * time.Hour:                         "1 day",
		25 * time.Hour:                         "1 day 1 hour",
		7 * day:                                "7 days",
		200*day + 4*time.Hour + 59*time.Minute: "200 days 4 hours",
	}
	for d, want := range cases {
		if got := humanDuration(d); got != want {
			t.Errorf("humanDuration(%v): want %q, got %q", d, want, got)
		}
	}
}
