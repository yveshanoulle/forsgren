package metrics

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// botPulls are pull requests of acme/app a bot opened, merged an hour ago,
// their lead times the given hours, numbered from 1.
func botPulls(hours ...int) []history.PullRequest {
	pulls := shopPulls(hours...)
	for i := range pulls {
		pulls[i].Bot = history.ByBot
	}
	return pulls
}

// shopBotLead is Acme Shop's Bot PR Lead Time over the pull requests.
func shopBotLead(pulls ...history.PullRequest) PRLeadTime {
	return BotPRLeadTimes(projects, Data{Pulls: pulls}, now)[0]
}

// TestBotPRLeadTimeCountsTheBotPullRequestsOnly (forsgren#479, step 1): the
// same measure as PR Lead Time over the pull requests a bot opened; a person's
// and one of unknown author are in neither mean, those merged before the window
// or in another project's repository are not counted, and PR Lead Time keeps
// to people.
func TestBotPRLeadTimeCountsTheBotPullRequestsOnly(t *testing.T) {
	h := time.Hour
	pulls := append(botPulls(1, 3),
		mergedPull("acme/app", 3, 30*h, h),
		openedBy(mergedPull("acme/app", 4, 40*h, h), history.BotUnknown),
		openedBy(mergedPull("acme/app", 5, h, 40*day), history.ByBot),
		openedBy(mergedPull("acme/cli", 6, 5*h, h), history.ByBot))
	got := BotPRLeadTimes(projects, Data{Pulls: pulls}, now)
	want := PRLeadTime{Project: "Acme Shop", PullRequests: 2, Mean: 2 * h, Median: 2 * h}
	if got[0] != want {
		t.Errorf("Acme Shop: want %+v, got %+v", want, got[0])
	}
	if tools := (PRLeadTime{Project: "Acme Tools", PullRequests: 1, Mean: 5 * h}); got[1] != tools {
		t.Errorf("Acme Tools: want %+v, got %+v", tools, got[1])
	}
	if people := shopPRLead(pulls...); people.PullRequests != 1 || people.Mean != 30*h {
		t.Errorf("want PR Lead Time to keep to the one person's pull request, got %+v", people)
	}
}

// TestBotPRLeadTimeHasTheSameSpreadAndNotes (forsgren#479, step 1): the median
// from two pull requests, the 90th percentile from ten, a cut first commit
// time (note 3) and a created time standing in (note 4) counted as for PR Lead
// Time.
func TestBotPRLeadTimeHasTheSameSpreadAndNotes(t *testing.T) {
	h := time.Hour
	pulls := botPulls(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
	pulls[0].FirstCommitCut = true
	pulls[1].CreatedStandsIn = true
	pulls[1].FirstCommitAt = time.Time{}
	pulls[1].CreatedAt = pulls[1].MergedAt.Add(-2 * h)
	got := shopBotLead(pulls...)
	want := PRLeadTime{Project: "Acme Shop", PullRequests: 10, Mean: 11 * h / 2, Median: 11 * h / 2, P90: 9 * h,
		Cut: 1, CreatedStandsIn: 1}
	if got != want {
		t.Errorf("want %+v, got %+v", want, got)
	}
	if !got.HasMedian() || !got.HasP90() {
		t.Errorf("want a median and a p90 shown, got %+v", got)
	}
}

// TestBotPRLeadTimeIsNotReadableWhenARepositoryWasRefused (forsgren#479, step
// 1): the pull request read refused for a repository makes the bot figures of
// its project not readable as the people's.
func TestBotPRLeadTimeIsNotReadableWhenARepositoryWasRefused(t *testing.T) {
	data := Data{Pulls: botPulls(1), PullsDenied: history.Reach{"acme/api": refusedAt}}
	got := BotPRLeadTimes(projects, data, now)
	if !got[0].NotReadable || got[1].NotReadable {
		t.Errorf("want only Acme Shop not readable, got %+v", got)
	}
}
