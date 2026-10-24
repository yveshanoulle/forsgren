package metrics

import (
	"testing"
	"time"
)

// noHumanPulls is the cell of a project without a human pull request in the
// window, a dash (forsgren#390, step 2).
const noHumanPulls = "-"

// TestMainlineLeadTimeCellShowsMeanCountAndShare (forsgren#256, step 2): the
// cell is the mean, the deviation and the count of pull requests, as the
// Mainline Interval writes them, then the share merged within 24 hours in
// Yves's wording of decision #302 (pull requests, not commits), with the
// counts behind it in brackets (#343, rounded down as before), and a dash for
// the deviation of one; without a human pull request, #342's sentence
// (forsgren#345, step 2).
func TestMainlineLeadTimeCellShowsMeanCountAndShare(t *testing.T) {
	h := time.Hour
	cases := map[string]struct {
		lead MainlineLeadTime
		want string
	}{
		"none": {MainlineLeadTime{}, noHumanPulls},
		"one": {MainlineLeadTime{PullRequests: 1, Mean: 5 * h, WithinReference: 1},
			"5 h ± - (1) · 100% (1 of 1) pull requests merged within 24 hours of their first commit"},
		"three, two within": {MainlineLeadTime{PullRequests: 3, Mean: 30 * h, Deviation: 2*h + 30*time.Minute,
			WithinReference: 2}, "1 d 6 h ± 2 h 30 min (3) · 66% (2 of 3) pull requests merged within 24 hours of " +
			"their first commit"},
	}
	for name, c := range cases {
		if got := c.lead.Cell(); got != c.want {
			t.Errorf("%s: want %q, got %q", name, c.want, got)
		}
	}
}

// TestMainlineLeadTimeCellSaysWhatIsNotExact (forsgren#256, step 2): the cut
// pull requests are counted next to the pull requests (decision #299) and the
// mean is then said to be a lower bound, never shown as exact; the pull
// requests the created time stood in for are counted last (decision #300),
// one and many.
func TestMainlineLeadTimeCellSaysWhatIsNotExact(t *testing.T) {
	const share = " · 50% (2 of 4) pull requests merged within 24 hours of their first commit"
	base := MainlineLeadTime{PullRequests: 4, Mean: 3 * time.Hour, Deviation: time.Hour, WithinReference: 2}
	cut, oneStandIn, standIns, both := base, base, base, base
	cut.Cut = 2
	oneStandIn.CreatedStandsIn = 1
	standIns.CreatedStandsIn = 3
	both.Cut, both.CreatedStandsIn = 1, 2
	cases := map[string]struct {
		lead MainlineLeadTime
		want string
	}{
		"cut":          {cut, "3 h ± 1 h (4, 2 cut)" + share + " · the mean is a lower bound"},
		"one stand-in": {oneStandIn, "3 h ± 1 h (4)" + share + " · 1 pull request timed by its created time"},
		"stand-ins":    {standIns, "3 h ± 1 h (4)" + share + " · 3 pull requests timed by their created time"},
		"both": {both, "3 h ± 1 h (4, 1 cut)" + share + " · the mean is a lower bound" +
			" · 2 pull requests timed by their created time"},
	}
	for name, c := range cases {
		if got := c.lead.Cell(); got != c.want {
			t.Errorf("%s: want %q, got %q", name, c.want, got)
		}
	}
}

// TestMainlineLeadTimeCellNamesThePullRequestsNotCounted (forsgren#345, step
// 2, #341): the bot pull requests and those of unknown author are named last,
// each when there are any, one and many; without a human pull request they
// follow #342's sentence; a project not readable stays "Pull requests not
// readable".
func TestMainlineLeadTimeCellNamesThePullRequestsNotCounted(t *testing.T) {
	const counted = "3 h ± - (1) · 100% (1 of 1) pull requests merged within 24 hours of their first commit"
	human := MainlineLeadTime{PullRequests: 1, Mean: 3 * time.Hour, WithinReference: 1}
	withNotes := func(m MainlineLeadTime, bots, unknown int) MainlineLeadTime {
		m.Bots, m.UnknownAuthors = bots, unknown
		return m
	}
	cases := map[string]struct {
		lead MainlineLeadTime
		want string
	}{
		"one bot":     {withNotes(human, 1, 0), counted + " · 1 bot pull request not counted"},
		"bots":        {withNotes(human, 3, 0), counted + " · 3 bot pull requests not counted"},
		"one unknown": {withNotes(human, 0, 1), counted + " · 1 pull request of unknown author not counted"},
		"bots, unknowns": {withNotes(human, 2, 4), counted + " · 2 bot pull requests not counted" +
			" · 4 pull requests of unknown author not counted"},
		"no human, bots": {withNotes(MainlineLeadTime{}, 3, 0), noHumanPulls + " · 3 bot pull requests not counted"},
		"no human, both": {withNotes(MainlineLeadTime{}, 1, 2), noHumanPulls + " · 1 bot pull request not counted" +
			" · 2 pull requests of unknown author not counted"},
		"not readable": {withNotes(MainlineLeadTime{NotReadable: true}, 2, 1), "Pull requests not readable"},
	}
	for name, c := range cases {
		if got := c.lead.Cell(); got != c.want {
			t.Errorf("%s: want %q, got %q", name, c.want, got)
		}
	}
}
