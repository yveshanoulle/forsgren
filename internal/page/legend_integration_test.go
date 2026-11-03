package page

import (
	"strings"
	"testing"
)

// legendIntegrationText are the sentences of the legend's part on the second TBD table (forsgren#622 step 3):
// what each column counts, the working days, who is left out and who counts, and the states.
var legendIntegrationText = []string{
	"Below it a second table, Integration, has the same rows",
	"how often the developers of a project get commits onto the main branch, in four groups of columns",
	"how many commits a developer puts on main per working day, as a spread over the developers",
	"the share of the developers who made a commit on main on at least 4 of every 5 working days",
	"the working days since each developer's last commit on main, as a spread over the developers. 0 is a commit today",
	"each developer's longest gap, in working days, between two commits on main, as a spread over the developers",
	"Working days are Monday to Friday, in UTC, over the last 30 days, the DORA window, both ends included",
	"Bots are left out. Accounts set up as the same developer count as one",
	"Only a developer with a commit on main in the window counts, so nobody is counted as a zero",
	"The figures are spreads over the developers, and no login is ever shown",
	"The measures shown follow the rules of How do I read the numbers?, as in the first table",
	"Push activity not readable and Pushes not collected yet stand across the four groups, a service row says " +
		"Per repository, and a project without data shows its one sentence, as in the first table",
}

// TestLegendExplainsTheIntegrationTable (forsgren#622): the TBD section says what the second table counts.
func TestLegendExplainsTheIntegrationTable(t *testing.T) {
	section := legendTbdSection(t, rendered(t, "legend.html", calculated()))
	_, part, _ := strings.Cut(section, `<h3 id="tbd-integration">`)
	part, _, _ = strings.Cut(part, "<h3 ")
	for _, want := range legendIntegrationText {
		if !strings.Contains(section, want) {
			t.Errorf("want %q in the TBD page section", want)
		}
	}
	if part == "" {
		t.Error("want an Integration part in the TBD page section")
	}
}
