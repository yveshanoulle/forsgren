package page

import (
	"strings"
	"testing"
)

// TestLegendLeadTimeLevelsShowTheirScore (forsgren#79): each level of lead
// time for changes in the legend ends with the score the scoring view gives
// that level, 10 for the fastest down to 0.
func TestLegendLeadTimeLevelsShowTheirScore(t *testing.T) {
	wantAll(t, "legend.html", rendered(t, "legend.html", viewData()),
		"<li>Less than one hour: below 1 hour, score 10</li>",
		"<li>Less than one day: 1 hour to below 24 hours, score 8</li>",
		"<li>One day to one week: 24 hours to below 7 days, score 6</li>",
		"<li>One week to one month: 7 days to below 30 days, score 4</li>",
		"<li>One to six months: 30 days to below 180 days, score 2</li>",
		"<li>More than six months: 180 days and more, score 0</li>")
}

// TestLegendFrequencyLevelsShowTheirScore (forsgren#79): each level of
// deployment frequency in the legend ends with the score the scoring view
// gives that level, at the default window of 30 days.
func TestLegendFrequencyLevelsShowTheirScore(t *testing.T) {
	wantAll(t, "legend.html", rendered(t, "legend.html", viewData()),
		"in 30 days (more than once an hour over a working day of 8 hours), score 10</li>",
		"to 240 in 30 days, score 8</li>",
		"to 29 in 30 days, score 6</li>",
		"to 4 in 30 days, score 4</li>",
		"1 and more in 180 days, score 2</li>",
		"<li>Less than once per six months: none in 180 days, score 0</li>")
}

// TestLegendChangeFailLevelsShowTheirScoreRange (forsgren#79, decision #197):
// the scoring view scores the whole percent, so a level of change fail rate
// has the scores of its lowest and its highest whole percent.
func TestLegendChangeFailLevelsShowTheirScoreRange(t *testing.T) {
	wantAll(t, "legend.html", rendered(t, "legend.html", viewData()),
		"<li>0%: below 10%, score 10 to 9.1</li>",
		"<li>20%: 10% to below 30%, score 9 to 7.1</li>",
		"<li>40%: 30% to below 50%, score 7 to 5.1</li>",
		"<li>60%: 50% to below 70%, score 5 to 3.1</li>",
		"<li>80%: 70% to below 90%, score 3 to 1.1</li>",
		"<li>100%: 90% and more, score 1 to 0</li>")
}

// TestLegendRecoveryListsLeadTimesLevelsWithScore (forsgren#79): recovery time
// is banded and scored on lead time's six answers, so its section of the
// legend lists the same six levels, each with its score.
func TestLegendRecoveryListsLeadTimesLevelsWithScore(t *testing.T) {
	_, section, found := strings.Cut(rendered(t, "legend.html", viewData()), "<h2>Failed deployment recovery time</h2>")
	if !found {
		t.Fatal("want a recovery time section in the legend")
	}
	section, _, _ = strings.Cut(section, "<h2>")
	wantAll(t, "recovery time section", section,
		"<li>Recovered in less than one hour: below 1 hour, score 10</li>",
		"<li>Recovered in less than one day: 1 hour to below 24 hours, score 8</li>",
		"<li>Recovered in one day to one week: 24 hours to below 7 days, score 6</li>",
		"<li>Recovered in one week to one month: 7 days to below 30 days, score 4</li>",
		"<li>Recovered in one to six months: 30 days to below 180 days, score 2</li>",
		"<li>Recovered in more than six months: 180 days and more, score 0</li>")
}
