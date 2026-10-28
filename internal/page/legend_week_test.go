package page

import (
	"strings"
	"testing"
)

// legendWeekText are the sentences of the legend's Week page section
// (forsgren#531, step 4, decisions #532 A, #534 A, #539 A; forsgren#540, decision #541).
var legendWeekText = []string{
	"the commits and the deployments of the last 30 days, per weekday from Monday to Sunday",
	"It counts the period the footer names as Report Start and Report End, " +
		"and every weekday of that window, not one calendar week, so a weekday appears as often as the window holds it.",
	"Days are in UTC.",
	"Total holds the counts of the commits and of the deployments of the window.",
	"Under each weekday, Commits and Deployments are the share of the row's commits and of its deployments " +
		"that fall on that weekday, written as the shares on the TBD page are, " +
		"and the seven shares of a column add up to 100% before rounding.",
	"A commit is counted at its author date and a deployment at its time.",
	"the first-parent commits that the pushes to the main branch brought in the window",
	"The deployments are the successful ones of the window.",
	"A weekday without any reads 0%, and a 0 is zero.",
	"A row with no commits, or no deployments, reads 0 in Total and a dash in its weekday cells, " +
		"as there is nothing to divide.",
	"counts its own commits: the commits of its deployments that change one of its paths, each once, " +
		"as Deployed commits on the TBD page",
	"Its Total Commits and its Commits cells read –",
	"the en dash stands for commits not attributed to this service or rule, which are counted at repository " +
		"level on the project's row",
	"It is not zero commits, and it does not mean deployment data is missing",
	"The commits are the ones counted as Commits on the TBD page",
	"its Deployments cells are the percentages of the deployments of the service or rule itself",
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

// TestLegendSaysEveryWeekdayOfThatWindowOnce (forsgren#544): the window is described in one sentence.
func TestLegendSaysEveryWeekdayOfThatWindowOnce(t *testing.T) {
	_, section, _ := weekSection(t, calculated())
	if got := strings.Count(section, "every weekday of that window"); got != 1 {
		t.Errorf("want every weekday of that window once in the Week page section, got %d", got)
	}
}

// TestLegendExplainsTotalAndSharesInOneParagraph (forsgren#544): one paragraph starts with Total.
func TestLegendExplainsTotalAndSharesInOneParagraph(t *testing.T) {
	_, section, _ := weekSection(t, calculated())
	if got := strings.Count(section, "<p>Total "); got != 1 {
		t.Errorf("want one paragraph starting with Total in the Week page section, got %d", got)
	}
	if strings.Contains(section, "Total is the commits") {
		t.Error("want the Total sentence said once, in the Total holds paragraph")
	}
}

// TestLegendWeekSectionNamesTheWindowInUse: dora_days 90 reads 90 days.
func TestLegendWeekSectionHasNoWeekendShare(t *testing.T) {
	if _, section, _ := weekSection(t, calculated()); strings.Contains(section, "Weekend share") {
		t.Error("want no Weekend share in the Week page section")
	}
}

func TestLegendWeekSectionNamesTheWindowInUse(t *testing.T) {
	data := calculated()
	data.DoraDays = 90
	if _, section, _ := weekSection(t, data); !strings.Contains(section, "of the last 90 days") {
		t.Error("want the Week page section to name the window in use, 90 days")
	}
}
