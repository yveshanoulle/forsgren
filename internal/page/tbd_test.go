package page

import (
	"bytes"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// tbdData is the TBD page's data: Acme Shop with 4 commits and a deviation,
// Acme Tools with 2 commits, so a mean and no deviation, and Acme Docs with
// no commit; their Mainline Lead Times (tbdLeads) and their Developers, with
// commits without a known author for Acme Tools and Acme Web. Acme Shop has
// half of its commits timed by author date and Acme Tools half of its
// commits legacy data without a known author, so their plain notes; Acme Web
// has more than half of both, so the cells say so (forsgren#345, step 3).
func tbdData() Data {
	return tbdDataWith(tbdLeads())
}

// tbdLeads are the Mainline Lead Times of tbdData (forsgren#256, step 2):
// Acme Shop's 5 pull requests all within 24 hours, Acme Tools' one cut pull
// request, no human one for Acme Docs but 2 of bots, and Acme Web's 12 with
// one timed by its created time, next to 3 of bots and 1 of unknown author
// (forsgren#345, step 2).
func tbdLeads() []metrics.MainlineLeadTime {
	return []metrics.MainlineLeadTime{
		{Project: "Acme Shop", PullRequests: 5, Mean: 3 * time.Hour, Deviation: time.Hour, WithinReference: 5},
		{Project: "Acme Tools", PullRequests: 1, Mean: 30 * time.Hour, Cut: 1},
		{Project: "Acme Docs", Bots: 2},
		{Project: "Acme Web", PullRequests: 12, Mean: 20 * time.Hour, Deviation: 10 * time.Hour, WithinReference: 7,
			CreatedStandsIn: 1, Bots: 3, UnknownAuthors: 1},
	}
}

// tbdDataWith is tbdData with the Mainline Lead Times leads.
func tbdDataWith(leads []metrics.MainlineLeadTime) Data {
	data := calculated()
	data.Mainline = []metrics.MainlineInterval{
		{Project: "Acme Shop", Commits: 4, Gaps: 3, Mean: 2 * time.Hour, Deviation: time.Hour, Median: 2 * time.Hour,
			ByAuthorDate: 2},
		{Project: "Acme Tools", Commits: 2, Gaps: 1, Mean: 2 * time.Hour},
		{Project: "Acme Docs"},
		{Project: "Acme Web", Commits: 13, Gaps: 12, Mean: 24 * time.Minute, Deviation: 2*time.Hour + 24*time.Minute,
			Median: 5 * time.Minute, P90: time.Hour, ByAuthorDate: 7},
	}
	data.Developers = []metrics.Developers{
		{Project: "Acme Shop", Count: 3, Commits: 4},
		{Project: "Acme Tools", Count: 1, Unknown: 1, Legacy: 1, Commits: 2},
		{Project: "Acme Docs"},
		{Project: "Acme Web", Count: 12, Unknown: 11, Legacy: 11, Commits: 20},
	}
	data.MainlineLead = leads
	return data
}

// noLeads are the Mainline Lead Times of tbdData's projects without a pull
// request merged in the window.
func noLeads() []metrics.MainlineLeadTime {
	leads := tbdLeads()
	for i := range leads {
		leads[i] = metrics.MainlineLeadTime{Project: leads[i].Project}
	}
	return leads
}

// uncollected is tbdData with no data/pulls.csv beside the history: the pull
// requests have not been collected yet (forsgren#256, step 2).
func uncollected() Data {
	data := tbdDataWith(noLeads())
	data.PullsUncollected = true
	return data
}

// notReadable is tbdData with collect refused the pull request read of a
// repository of Acme Tools and of Acme Docs (forsgren#337, step 2): Acme
// Tools' cut pull request stays read, Acme Docs has none.
func notReadable() Data {
	data := tbdData()
	data.MainlineLead[1].NotReadable = true
	data.MainlineLead[2].NotReadable = true
	return data
}

// tbdRow is the TBD page's row of project, its Mainline Interval cell, its
// Mainline Lead Time cell then its Developers cell, as the template writes it.
func tbdRow(project, interval, lead, developers string) string {
	return "<th scope=\"row\">" + project + "</th>\n            <td>" + interval + "</td>\n            <td>" + lead +
		"</td>\n            <td>" + developers + "</td>\n"
}

// share is the end of a Mainline Lead Time cell after its count: the share of
// the pull requests merged within 24 hours in whole percent, then how many of
// how many (forsgren#345, step 2, #343).
func share(percent, counts string) string {
	return " · " + percent + "% (" + counts + ") pull requests merged within 24 hours of their first commit"
}

// shopInterval and webInterval are the Mainline Interval cells of Acme Shop,
// half of its commits timed by author date, and of Acme Web, more than half
// (forsgren#345, step 3).
const (
	shopInterval = "2 h ± 1 h (3) · median 2 h · p90 - · 2 commits timed by author date"
	webInterval  = "24 min ± 2 h 24 min (12) · median 5 min · p90 1 h · " +
		"Mostly estimated: 7 of 13 commits timed by author date."
)

// noHumanPulls is the Mainline Lead Time cell of a project without a human
// pull request in the window, Yves's wording on #342 (forsgren#345, step 2).
const noHumanPulls = "No human pull requests in this period; changes may go directly to the trunk"

// TestTbdPageShowsTheDevelopersNextToTheInterval (forsgren#273, step 3): a
// Developers column follows the Mainline Interval and its Mainline Lead Time
// (forsgren#256, step 2), each project's cell its count, then the note on the
// commits without a known author when there are, in the same row as the
// project's interval; Acme Web's, more than half of its commits legacy data
// without a known author, says so (forsgren#345, step 3).
func TestTbdPageShowsTheDevelopersNextToTheInterval(t *testing.T) {
	got := rendered(t, "tbd.html", tbdData())
	wantAll(t, "tbd.html", got,
		"<th scope=\"col\">Mainline Interval</th>\n            <th scope=\"col\">Mainline Lead Time</th>\n"+
			"            <th scope=\"col\">Developers</th>\n",
		tbdRow("Acme Shop", shopInterval, "3 h ± 1 h (5)"+share("100", "5 of 5"), "3"),
		tbdRow("Acme Tools", "2 h ± - (1) · median - · p90 -",
			"1 d 6 h ± - (1, 1 cut)"+share("0", "0 of 1")+" · the mean is a lower bound",
			"1 · 1 commit without a known author is not counted"),
		tbdRow("Acme Docs", "-", noHumanPulls+" · 2 bot pull requests not counted", "0"),
		tbdRow("Acme Web", webInterval,
			"20 h ± 10 h (12)"+share("58", "7 of 12")+" · 1 pull request timed by its created time"+
				" · 3 bot pull requests not counted · 1 pull request of unknown author not counted",
			"12 developers · 11 commits without a known author excluded (legacy data)."))
}

// TestTbdPageSaysThePullRequestsAreNotCollectedYet (forsgren#256, step 2):
// without data/pulls.csv beside the history, every Mainline Lead Time cell
// says the pull requests have not been collected yet, never a dash, which is
// a project without a pull request merged in the window.
func TestTbdPageSaysThePullRequestsAreNotCollectedYet(t *testing.T) {
	const notYet = "No pull requests have been collected yet"
	got := rendered(t, "tbd.html", uncollected())
	wantAll(t, "uncollected", got, tbdRow("Acme Shop", shopInterval, notYet, "3"),
		tbdRow("Acme Docs", "-", notYet, "0"))
	noneInWindow := rendered(t, "tbd.html", tbdDataWith(noLeads()))
	wantNone(t, "collected, none in the window", noneInWindow, notYet)
	wantAll(t, "collected, none in the window", noneInWindow, tbdRow("Acme Docs", "-", noHumanPulls, "0"))
}

// TestTbdPageSaysThePullRequestsAreNotReadable (forsgren#337, step 2): a
// project collect was refused the pull request read of shows "Pull requests
// not readable" in its Mainline Lead Time cell, never the lead time of what
// was read nor the dash of no pull request, also while data/pulls.csv is
// absent; the other projects keep their cell.
func TestTbdPageSaysThePullRequestsAreNotReadable(t *testing.T) {
	const refused, notYet = "Pull requests not readable", "No pull requests have been collected yet"
	got := rendered(t, "tbd.html", notReadable())
	wantAll(t, "not readable", got, tbdRow("Acme Tools", "2 h ± - (1) · median - · p90 -", refused,
		"1 · 1 commit without a known author is not counted"), tbdRow("Acme Docs", "-", refused, "0"),
		tbdRow("Acme Shop", shopInterval, "3 h ± 1 h (5)"+share("100", "5 of 5"), "3"))
	uncollectedRefused := notReadable()
	uncollectedRefused.PullsUncollected = true
	got = rendered(t, "tbd.html", uncollectedRefused)
	wantAll(t, "not collected yet", got, tbdRow("Acme Docs", "-", refused, "0"),
		tbdRow("Acme Shop", shopInterval, notYet, "3"))
}

// TestTbdPageRefusesDevelopersOfOtherProjects (forsgren#273, step 3): the
// Developers, and the Mainline Lead Times (forsgren#256, step 2), are paired
// with the Mainline Intervals by project, so a render whose Developers or
// Mainline Lead Times are missing, one too many, or name another project in a
// row, fails instead of showing a number in the wrong row.
func TestTbdPageRefusesDevelopersOfOtherProjects(t *testing.T) {
	cases := map[string]func(*Data){
		"developers missing": func(d *Data) { d.Developers = d.Developers[:3] },
		"developers extra": func(d *Data) {
			d.Developers = append(d.Developers, metrics.Developers{Project: "Acme Gone", Count: 1})
		},
		"developers swapped": func(d *Data) { d.Developers[0], d.Developers[1] = d.Developers[1], d.Developers[0] },
		"leads missing":      func(d *Data) { d.MainlineLead = d.MainlineLead[:3] },
		"leads extra": func(d *Data) {
			d.MainlineLead = append(d.MainlineLead, metrics.MainlineLeadTime{Project: "Acme Gone"})
		},
		"leads swapped": func(d *Data) { d.MainlineLead[0], d.MainlineLead[1] = d.MainlineLead[1], d.MainlineLead[0] },
	}
	for name, change := range cases {
		data := tbdData()
		change(&data)
		var got bytes.Buffer
		if err := Render(&got, "tbd.html", data); err == nil {
			t.Errorf("%s: want the render to fail, got:\n%s", name, got.String())
		}
	}
}

// TestTbdPageGolden (forsgren#253, step 4 of 7): the TBD page is a root page,
// tbd.html, with a table of a row per project; with no projects, or no
// Mainline Interval read yet, one line says why in place of the table. Its
// Mainline Lead Time column (forsgren#256, step 2) has a golden with data,
// one with no pull request in the window, one before the pull requests were
// collected and one with refused pull request reads (forsgren#337, step 2).
func TestTbdPageGolden(t *testing.T) {
	noProjects := calculated()
	noProjects.NoProjects = true
	checkPageGolden(t, "tbd.html", "testdata/tbd.golden.html", tbdData())
	checkPageGolden(t, "tbd.html", "testdata/tbd.no-data.golden.html", calculated())
	checkPageGolden(t, "tbd.html", "testdata/tbd.no-projects.golden.html", noProjects)
	checkPageGolden(t, "tbd.html", "testdata/tbd.lead-no-data.golden.html", tbdDataWith(noLeads()))
	checkPageGolden(t, "tbd.html", "testdata/tbd.lead-not-collected.golden.html", uncollected())
	checkPageGolden(t, "tbd.html", "testdata/tbd.lead-not-readable.golden.html", notReadable())
}

// TestTbdPageHasItsHeadingAndTable (forsgren#253): the title and the h1 (id
// tbd-heading) name trunk-based development; the table is the h1's region,
// with no caption, columns Project, Mainline Interval, Mainline Lead Time
// (forsgren#256) and Developers (forsgren#273); each project's cell is the
// metric's own, "-" below two commits.
func TestTbdPageHasItsHeadingAndTable(t *testing.T) {
	got := rendered(t, "tbd.html", tbdData())
	wantAll(t, "tbd.html", got, "<title>Trunk-based development [TBD] (BETA) · ",
		`<h1 id="tbd-heading">Trunk-based development [TBD] (BETA)</h1>`, `aria-labelledby="tbd-heading"`,
		`<th scope="col">Project</th>`, `<th scope="col">Mainline Interval</th>`,
		`<th scope="col">Mainline Lead Time</th>`,
		`<th scope="row">Acme Shop</th>`, "<td>"+shopInterval+"</td>",
		`<th scope="row">Acme Tools</th>`, "<td>2 h ± - (1) · median - · p90 -</td>",
		`<th scope="row">Acme Docs</th>`, "<td>-</td>",
		`<th scope="row">Acme Web</th>`, "<td>"+webInterval+"</td>")
	wantNone(t, "tbd.html", got, "<caption", "metrics are coming to this page")
}

// TestTbdPageHasNoExplanationAndNoLeadTimeLine (forsgren#271): the h1 is
// followed by the table, or by its one line; the explanation of the Mainline
// Interval and of the Mainline Lead Time is the legend's, not the page's.
func TestTbdPageHasNoExplanationAndNoLeadTimeLine(t *testing.T) {
	for name, data := range map[string]Data{"data": tbdData(), "no data": calculated()} {
		wantNone(t, name, rendered(t, "tbd.html", data), "sample standard deviation", "deployments of the last",
			"Mainline Lead Time is", "A dash is", "each commit once", "lower bound, so")
	}
}

// TestTbdTitleIsYvesWording (forsgren#271): the title and the h1 of the TBD
// page read exactly "Trunk-based development [TBD] (BETA)", the BETA in
// capitals as Yves wrote it, the same marker the History page reads (forsgren#198).
func TestTbdTitleIsYvesWording(t *testing.T) {
	const want = "Trunk-based development [TBD] (BETA)"
	if got := calculated().TbdTitle(); got != want {
		t.Errorf("want the title %q, got %q", want, got)
	}
	history := rendered(t, "history.html", historyData())
	wantAll(t, "history.html", history, `<h1 id="history-heading">History (BETA)</h1>`)
}

// TestTbdPageSaysWhyItHasNoTable (forsgren#253): with no projects, or no
// Mainline Interval read, the page shows one line and no table.
func TestTbdPageSaysWhyItHasNoTable(t *testing.T) {
	noProjects := calculated()
	noProjects.NoProjects = true
	for name, c := range map[string]struct {
		data Data
		want string
	}{
		"no projects": {noProjects, "No projects are listed yet, so there is no Mainline Interval to show."},
		"no data":     {calculated(), "No commits have been collected yet, so there is no Mainline Interval to show."},
	} {
		got := rendered(t, "tbd.html", c.data)
		wantAll(t, name, got, "<p>"+c.want+"</p>")
		wantNone(t, name, got, "<table")
	}
}

// TestTbdPageIsAfterHistoryInTheRootPages (forsgren#253): the page is one of
// the root pages, labelled TBD, after the History page.
func TestTbdPageIsAfterHistoryInTheRootPages(t *testing.T) {
	last := rootPages[len(rootPages)-1]
	if last.Name != TbdPage || last.Label != "TBD" {
		t.Errorf("want the last root page %q labelled TBD, got %+v", TbdPage, last)
	}
}
