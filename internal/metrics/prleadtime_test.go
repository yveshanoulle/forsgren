package metrics

import (
	"slices"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// mergedPull is pull request number of repository, opened by a person,
// merged mergedAgo before now, its first commit authored lead before the
// merge and created a minute before that commit.
func mergedPull(repository string, number int64, lead, mergedAgo time.Duration) history.PullRequest {
	merged := now.Add(-mergedAgo)
	first := merged.Add(-lead)
	return history.PullRequest{
		Repository: repository, Number: number, CreatedAt: first.Add(-time.Minute), MergedAt: merged,
		MergeCommit: "0123456789abcdef0123456789abcdef01234567", UpdatedAt: merged, FirstCommitAt: first,
		Bot: history.ByHuman,
	}
}

// shopPulls are pull requests of acme/app merged an hour ago, their lead
// times the given hours, numbered from 1.
func shopPulls(hours ...int) []history.PullRequest {
	pulls := make([]history.PullRequest, len(hours))
	for i, h := range hours {
		pulls[i] = mergedPull("acme/app", int64(i+1), time.Duration(h)*time.Hour, time.Hour)
	}
	return pulls
}

// shopPRLead is Acme Shop's PR Lead Time over the pull requests, in
// the 30 day window.
func shopPRLead(pulls ...history.PullRequest) PRLeadTime {
	return PRLeadTimes(projects, Data{Pulls: pulls}, now)[0]
}

// TestPRLeadTimeMeanMedianAndCount (forsgren#256, step 1): per merged
// pull request, the merged time minus its first commit time; the mean, the
// median and the count. No pull request has no lead time; one has a mean and
// no median.
func TestPRLeadTimeMeanMedianAndCount(t *testing.T) {
	h := time.Hour
	cases := []struct {
		name  string
		pulls []history.PullRequest
		want  PRLeadTime
		has   [2]bool // HasLeadTime, HasMedian
	}{
		{"none", nil, PRLeadTime{}, [2]bool{false, false}},
		{"one", shopPulls(5), PRLeadTime{PullRequests: 1, Mean: 5 * h}, [2]bool{true, false}},
		{"1, 2 and 3 hours", shopPulls(3, 1, 2), PRLeadTime{PullRequests: 3, Mean: 2 * h, Median: 2 * h},
			[2]bool{true, true}},
		{"1 and 3 hours", shopPulls(1, 3), PRLeadTime{PullRequests: 2, Mean: 2 * h, Median: 2 * h},
			[2]bool{true, true}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := shopPRLead(c.pulls...)
			c.want.Project = "Acme Shop"
			if got != c.want {
				t.Errorf("want %+v, got %+v", c.want, got)
			}
			if has := [2]bool{got.HasLeadTime(), got.HasMedian()}; has != c.has {
				t.Errorf("want HasLeadTime, HasMedian %v, got %v", c.has, has)
			}
		})
	}
}

// TestPRLeadTimeCountsCutValues (forsgren#256, decision #299): a pull
// request whose commit list was cut keeps its first commit time, a lower
// bound: it counts in the mean and the median like any other,
// and Cut says how many did.
func TestPRLeadTimeCountsCutValues(t *testing.T) {
	pulls := shopPulls(1, 3)
	pulls[1].FirstCommitCut = true
	want := PRLeadTime{Project: "Acme Shop", PullRequests: 2, Mean: 2 * time.Hour, Median: 2 * time.Hour,
		Cut: 1}
	if got := shopPRLead(pulls...); got != want {
		t.Errorf("want %+v, got %+v", want, got)
	}
}

// TestPRLeadTimeStandInUsesTheCreatedTime (forsgren#256, decision
// #300): a pull request whose commit list gave no usable date has no first
// commit time, and its created time stands in: the lead time is merged minus
// created, counted, and CreatedStandsIn says how many.
func TestPRLeadTimeStandInUsesTheCreatedTime(t *testing.T) {
	standIn := mergedPull("acme/app", 2, 0, time.Hour)
	standIn.CreatedAt = standIn.MergedAt.Add(-3 * time.Hour)
	standIn.FirstCommitAt, standIn.CreatedStandsIn = time.Time{}, true
	pulls := append(shopPulls(1), standIn)
	want := PRLeadTime{Project: "Acme Shop", PullRequests: 2, Mean: 2 * time.Hour, Median: 2 * time.Hour,
		CreatedStandsIn: 1}
	if got := shopPRLead(pulls...); got != want {
		t.Errorf("want %+v, got %+v", want, got)
	}
}

// TestPRLeadTimeCountsANegativeOneAsZero (forsgren#256): a first commit
// authored after the merge (a clock, a rewritten date) is a lead time of 0, as
// lead time for changes counts one (LeadTimes): the pull request is a real
// integration and stays in the count.
func TestPRLeadTimeCountsANegativeOneAsZero(t *testing.T) {
	ahead := mergedPull("acme/app", 2, -5*time.Hour, time.Hour)
	want := PRLeadTime{Project: "Acme Shop", PullRequests: 2, Mean: time.Hour, Median: time.Hour}
	if got := shopPRLead(append(shopPulls(2), ahead)...); got != want {
		t.Errorf("want %+v, got %+v", want, got)
	}
}

// TestPRLeadTimeCountsThePullRequestsMergedInTheWindow (forsgren#256):
// a pull request counts when it was merged in the DORA window (dora_days,
// both ends included), whatever its first commit's age, in the project whose
// config lists its repository, compared ignoring case, in the order of
// projects; one with no merged time, or merged after the render time, is not
// counted.
func TestPRLeadTimeCountsThePullRequestsMergedInTheWindow(t *testing.T) {
	h := time.Hour
	edge := mergedPull("ACME/App", 1, 2*h, 30*day)
	early := mergedPull("acme/app", 2, h, 30*day+time.Second)
	old := mergedPull("acme/app", 3, h, 40*day)
	unmerged := mergedPull("acme/app", 4, h, time.Hour)
	unmerged.MergedAt = time.Time{}
	ahead := mergedPull("acme/app", 5, h, -time.Hour)
	api := mergedPull("acme/api", 6, 60*day, time.Hour)
	tools := mergedPull("acme/cli", 7, 4*h, time.Hour)
	gone := mergedPull("acme/gone", 8, h, time.Hour)
	pulls := []history.PullRequest{edge, early, old, unmerged, ahead, api, tools, gone}
	got := PRLeadTimes(projects, Data{Pulls: pulls}, now)
	if counts := pullRequestsOf(got); !slices.Equal(counts, []int{2, 1}) {
		t.Errorf("want 2 pull requests for Acme Shop, the edge and acme/api, and 1 for Acme Tools, got %v", counts)
	}
	if got[0].Mean != (2*h+60*day)/2 {
		t.Errorf("Acme Shop: want the mean of the edge and acme/api, got %+v", got[0])
	}
	want := PRLeadTime{Project: "Acme Tools", PullRequests: 1, Mean: 4 * h}
	if got[1] != want {
		t.Errorf("Acme Tools: want %+v, got %+v", want, got[1])
	}
	wide := PRLeadTimes(projects[:1], Data{Pulls: pulls, DoraDays: 90}, now)
	if counts := pullRequestsOf(wide); !slices.Equal(counts, []int{4}) {
		t.Errorf("90 days: want the edge, the second after it, the one 40 days ago and acme/api, got %v", counts)
	}
}

// pullRequestsOf are the counts of pull requests of leads, in order.
func pullRequestsOf(leads []PRLeadTime) []int {
	counts := make([]int, len(leads))
	for i, l := range leads {
		counts[i] = l.PullRequests
	}
	return counts
}

// TestPRLeadTimesGiveEveryProject (forsgren#256): every project has its
// row, in config order, one without a pull request a zero one.
func TestPRLeadTimesGiveEveryProject(t *testing.T) {
	got := PRLeadTimes(projects, Data{}, now)
	want := []PRLeadTime{{Project: "Acme Shop"}, {Project: "Acme Tools"}}
	if !slices.Equal(got, want) {
		t.Errorf("want %+v, got %+v", want, got)
	}
}
