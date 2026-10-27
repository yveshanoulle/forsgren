package page

import (
	"strings"
	"testing"
)

// legendWeekText are the sentences of the legend's Week page section
// (forsgren#531, step 4, decisions #532 A, #534 A, #539 A).
var legendWeekText = []string{
	"the commits and the deployments of the last 30 days, per weekday from Monday to Sunday",
	"every weekday of that window, not one calendar week",
	"Days are in UTC.",
	"Each day cell reads commits · deployments.",
	"A commit is counted at its author date and a deployment at its time.",
	"the first-parent commits that the pushes to the main branch brought in the window",
	"The deployments are the successful ones of the window.",
	"A day without activity reads 0 · 0, and a 0 is zero.",
	"Weekend share is the commits of Saturday and Sunday out of all the commits of the row.",
	"Deployments are never mixed into it.",
	"A dash means the row has no commits",
	"counts its own commits: the commits of its deployments that change one of its paths, each once, " +
		"as Deployed commits on the TBD page",
	"Its day cells read – · 3",
	"the en dash stands for commits not attributed to this service or rule, which are counted at repository " +
		"level on the project's row",
	"It is not zero commits, and it does not mean deployment data is missing",
	"The commits are the ones counted as Commits on the TBD page",
	"the number after the dot is the deployments of the service or rule itself",
	"Its Weekend share says Per repository.",
	"Set week_page: false to take it out of the menu",
	"it is still generated, can be opened at week.html, and search engines are asked to skip it",
}

// weekSection is the legend's Week page section of data, and what comes right
// before and after it.
func weekSection(t *testing.T, data Data) (before, section, after string) {
	t.Helper()
	before, rest, found := strings.Cut(rendered(t, "legend.html", data), "<h2>Week page</h2>")
	if !found {
		t.Fatal("want a Week page section in the legend")
	}
	section, after, _ = strings.Cut(rest, "<h2>")
	return before, section, after
}

// TestLegendExplainsTheWeekPage: the legend has a Week page section, after
// the TBD section and before the Settings page section, with the sentences of
// legendWeekText.
func TestLegendExplainsTheWeekPage(t *testing.T) {
	before, section, after := weekSection(t, calculated())
	if !strings.Contains(before, "<h2>Trunk-based development [TBD]</h2>") {
		t.Error("want the Week page section after the TBD section")
	}
	if !strings.HasPrefix(after, "Settings page</h2>") {
		t.Errorf("want the Settings page section right after, got %.40q", after)
	}
	for _, want := range legendWeekText {
		if !strings.Contains(section, want) {
			t.Errorf("want %q in the Week page section", want)
		}
	}
}

// TestLegendWeekSectionNamesTheWindowInUse: dora_days 90 reads 90 days.
func TestLegendWeekSectionNamesTheWindowInUse(t *testing.T) {
	data := calculated()
	data.DoraDays = 90
	if _, section, _ := weekSection(t, data); !strings.Contains(section, "of the last 90 days") {
		t.Error("want the Week page section to name the window in use, 90 days")
	}
}
