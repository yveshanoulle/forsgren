package metrics

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// openedBy is p with its bot status set to status.
func openedBy(p history.PullRequest, status history.BotStatus) history.PullRequest {
	p.Bot = status
	return p
}

// TestPRLeadTimeCountsHumanPullRequestsOnly (forsgren#345, step 2,
// Yves's answers on #341 and #348): only the pull requests a person opened
// count in the mean, the deviation, the count and the 24-hour share; a bot's
// and one of unknown author are left out of them, never taken as human, and
// counted apart; those merged before the window or in another project's
// repository are not counted at all.
func TestPRLeadTimeCountsHumanPullRequestsOnly(t *testing.T) {
	h := time.Hour
	pulls := append(shopPulls(1, 3),
		openedBy(mergedPull("acme/app", 3, 30*h, h), history.ByBot),
		openedBy(mergedPull("acme/api", 4, 50*h, h), history.ByBot),
		openedBy(mergedPull("acme/app", 5, 40*h, h), history.BotUnknown),
		openedBy(mergedPull("acme/app", 6, h, 40*day), history.ByBot),
		openedBy(mergedPull("acme/app", 7, h, 40*day), history.BotUnknown),
		openedBy(mergedPull("acme/cli", 8, h, h), history.ByBot))
	got := PRLeadTimes(projects, Data{Pulls: pulls}, now)
	want := PRLeadTime{Project: "Acme Shop", PullRequests: 2, Mean: 2 * h, Median: 2 * h,
		Bots: 2}
	if got[0] != want {
		t.Errorf("Acme Shop: want %+v, got %+v", want, got[0])
	}
	if tools := (PRLeadTime{Project: "Acme Tools", Bots: 1}); got[1] != tools {
		t.Errorf("Acme Tools: want %+v, got %+v", tools, got[1])
	}
}

// TestPRLeadTimeWithoutAHumanPullRequestHasNoLeadTime (forsgren#345,
// step 2): pull requests of bots and of unknown authors alone give no lead
// time, no deviation and no share, only the bots count.
func TestPRLeadTimeWithoutAHumanPullRequestHasNoLeadTime(t *testing.T) {
	bot := openedBy(mergedPull("acme/app", 1, time.Hour, time.Hour), history.ByBot)
	unknown := openedBy(mergedPull("acme/app", 2, time.Hour, time.Hour), history.BotUnknown)
	got := shopPRLead(bot, unknown)
	want := PRLeadTime{Project: "Acme Shop", Bots: 1}
	if got != want {
		t.Errorf("want %+v, got %+v", want, got)
	}
	if got.HasLeadTime() {
		t.Errorf("want no lead time, got %+v", got)
	}
}
