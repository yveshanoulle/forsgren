package page

import "testing"

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
