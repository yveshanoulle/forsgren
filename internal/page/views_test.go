package page

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// viewPages are the pages of the views (forsgren#46), each in its own
// folder, one level below the site's root.
var viewPages = []string{"standard/index.html", "numbers/index.html"}

// TestPageNamesIncludeEachView (forsgren#46): the site has the root page,
// the legend, and a page per view at /standard/ and /numbers/.
func TestPageNamesIncludeEachView(t *testing.T) {
	names := PageNames()
	for _, want := range append([]string{"index.html", "legend.html"}, viewPages...) {
		if !slices.Contains(names, want) {
			t.Errorf("want %s among the pages, got %v", want, names)
		}
	}
}

// row is a table row of the page: the heading, then the five cells.
func row(heading string, cells ...string) *regexp.Regexp {
	pattern := `<th scope="row">` + regexp.QuoteMeta(heading) + `</th>`
	for _, cell := range cells {
		pattern += `\s*<td>` + regexp.QuoteMeta(cell) + `</td>`
	}
	return regexp.MustCompile(pattern)
}

// TestNumbersPageShowsOnlyNumbers (forsgren#46): each cell is a number, 0
// where the count is really zero and - where there is no number, never a
// band's text.
func TestNumbersPageShowsOnlyNumbers(t *testing.T) {
	data := acmeProjects(metrics.LeadTime{}, unrecovered, oneFailed, noRework)
	got := rendered(t, "numbers/index.html", data)
	for heading, cells := range map[string][]string{
		"Acme Shop":  {"12", "-", "-", "7%", "0%"},
		"Acme Tools": {"0", "-", "-", "100%", "-"},
	} {
		if !row(heading, cells...).MatchString(got) {
			t.Errorf("want the row of %s to read %v, got:\n%s", heading, cells, got)
		}
	}
	// The switch in the caption has its own " · "; the table's body has none.
	table := got[strings.Index(got, "<tbody"):strings.Index(got, "</tbody>")]
	wantNone(t, "numbers/index.html", table, "Between once", "Less than", "No lead time yet", "not completed yet", " · ")
}

// TestScoringPageShowsEachMetricsScoreAndOverallPerformance (forsgren#47):
// each cell is the metric's DORA Quick Check score alone, "9.3", never its
// number; a metric without data is - and has no score; the sixth cell is
// Overall Performance, the mean of the scored metrics to one decimal. A
// score of 0 is observed performance in the lowest band, - is not enough
// data: a project that never had a successful deployment has no frequency
// score, one whose last success is old has the lowest band's 0.
// Acme Shop scores 6, 9.3 and 10 (8.4), Acme Tools only its 100% change fail
// rate, 0 (0.0).
func TestScoringPageShowsEachMetricsScoreAndOverallPerformance(t *testing.T) {
	data := acmeProjects(metrics.LeadTime{}, unrecovered, oneFailed, noRework)
	got := rendered(t, "scoring/index.html", data)
	for heading, cells := range map[string][]string{
		"Acme Shop":  {"6", "-", "-", "9.3", "10", "8.4"},
		"Acme Tools": {"-", "-", "-", "0", "-", "0.0"},
	} {
		if !row(heading, cells...).MatchString(got) {
			t.Errorf("want the row of %s to read %v, got:\n%s", heading, cells, got)
		}
	}
	wantAll(t, "scoring/index.html", got, `<th scope="col">Overall Performance</th>`)
}

// TestScoringPageShowsNoOverallPerformanceWithoutAScore (forsgren#47): a row
// with no data has no scored metric, so all six cells, Overall Performance
// included, are -.
func TestScoringPageShowsNoOverallPerformanceWithoutAScore(t *testing.T) {
	data := Placeholder("0.4.2")
	data.Rows = Table([]metrics.Row{{Level: metrics.ProjectRow, Name: "Acme Empty"}})
	got := rendered(t, "scoring/index.html", data)
	if !row("Acme Empty", "-", "-", "-", "-", "-", "-").MatchString(got) {
		t.Errorf("want the row of Acme Empty to read - in all six cells, got:\n%s", got)
	}
}

// TestScoringPageShowsNoScoreForAProjectWithoutDeployments (forsgren#47): a
// project that never had a successful deployment in the recorded history has
// the frequency band metrics gives it, the lowest, but no data: all six
// cells, Overall Performance included, are -.
func TestScoringPageShowsNoScoreForAProjectWithoutDeployments(t *testing.T) {
	data := Placeholder("0.4.2")
	data.Rows = Table([]metrics.Row{{Level: metrics.ProjectRow, Name: "Acme Idle",
		Frequency: metrics.Frequency{Band: metrics.LessThanSixMonthly}}})
	got := rendered(t, "scoring/index.html", data)
	if !row("Acme Idle", "-", "-", "-", "-", "-", "-").MatchString(got) {
		t.Errorf("want the row of Acme Idle to read - in all six cells, got:\n%s", got)
	}
}

// TestScoringPageScoresZeroForALastSuccessOlderThanSixMonths (forsgren#47,
// ruling d): deployment frequency has data when the recorded history holds a
// successful deployment, however old. A last success more than 180 days ago
// is observed performance in the lowest band: frequency scores 0 and, with
// no other metric scored, so does Overall Performance. A project with only a
// failed deployment, Acme Tools, has no success and keeps -.
func TestScoringPageScoresZeroForALastSuccessOlderThanSixMonths(t *testing.T) {
	data := Placeholder("0.4.2")
	old := metrics.Frequency{Latest: time.Date(2025, 9, 1, 9, 30, 0, 0, time.UTC), Band: metrics.LessThanSixMonthly}
	failed := metrics.ChangeFailRate{Deployments: 1, FailedDeployments: 1, Failed: 1, Band: metrics.HundredPercent}
	data.Rows = Table([]metrics.Row{
		{Level: metrics.ProjectRow, Name: "Acme Old", Frequency: old},
		{Level: metrics.ProjectRow, Name: "Acme Tools", Frequency: metrics.Frequency{Band: metrics.LessThanSixMonthly},
			ChangeFail: failed},
	})
	got := rendered(t, "scoring/index.html", data)
	for heading, cells := range map[string][]string{
		"Acme Old":   {"0", "-", "-", "-", "-", "0.0"},
		"Acme Tools": {"-", "-", "-", "0", "-", "0.0"},
	} {
		if !row(heading, cells...).MatchString(got) {
			t.Errorf("want the row of %s to read %v, got:\n%s", heading, cells, got)
		}
	}
}

// TestStandardPageShowsTheStandardCells (forsgren#46): the standard view is
// the 0.1.0 table, band, number and count.
func TestStandardPageShowsTheStandardCells(t *testing.T) {
	data := acmeProjects(metrics.LeadTime{}, unrecovered, oneFailed, noRework)
	shop := data.Rows[0]
	want := row("Acme Shop", shop.Frequency.Cell(), shop.LeadTime.Cell(), shop.Recovery.Cell(),
		shop.ChangeFail.Cell(), shop.Rework.Cell())
	if got := rendered(t, "standard/index.html", data); !want.MatchString(got) {
		t.Errorf("want the standard cells on the standard page, got:\n%s", got)
	}
}

// TestViewPagesLinkRelativelyFromTheirFolder (forsgren#46): a page one folder
// down reaches the stylesheet and the legend through ../, and none of the
// root's links.
func TestViewPagesLinkRelativelyFromTheirFolder(t *testing.T) {
	data := acmeProjects(metrics.LeadTime{}, unrecovered, oneFailed, noRework)
	for _, name := range viewPages {
		got := rendered(t, name, data)
		wantAll(t, name, got, `href="../styles.css"`, `<a href="../legend.html">What the bands mean</a>`)
		wantNone(t, name, got, `href="styles.css"`, `href="legend.html"`)
	}
}

// wantAll fails the test for each text the page does not contain.
func wantAll(t *testing.T, name, got string, texts ...string) {
	t.Helper()
	for _, text := range texts {
		if !strings.Contains(got, text) {
			t.Errorf("%s: want %s, got:\n%s", name, text, got)
		}
	}
}

// wantNone fails the test for each text the page contains.
func wantNone(t *testing.T, name, got string, texts ...string) {
	t.Helper()
	for _, text := range texts {
		if strings.Contains(got, text) {
			t.Errorf("%s: want no %s, got:\n%s", name, text, got)
		}
	}
}

// TestViewSwitchMarksTheCurrentView (forsgren#46, #47): "View: standard ·
// numbers · scoring", the current view plain text marked aria-current="page",
// the others links to their folders.
func TestViewSwitchMarksTheCurrentView(t *testing.T) {
	data := acmeProjects(metrics.LeadTime{}, unrecovered, oneFailed, noRework)
	for name, want := range map[string]string{
		"standard/index.html": `View: <span aria-current="page">standard</span> · <a href="../numbers/">numbers</a> · ` +
			`<a href="../scoring/">scoring</a>`,
		"numbers/index.html": `View: <a href="../standard/">standard</a> · <span aria-current="page">numbers</span> · ` +
			`<a href="../scoring/">scoring</a>`,
		"scoring/index.html": `View: <a href="../standard/">standard</a> · <a href="../numbers/">numbers</a> · ` +
			`<span aria-current="page">scoring</span>`,
	} {
		got := rendered(t, name, data)
		wantAll(t, name, got, want)
		if n := strings.Count(got, `aria-current="page"`); n != 1 {
			t.Errorf("%s: want one current view, got %d", name, n)
		}
	}
}

// captionWithSwitch is the caption of a table with the view switch
// (forsgren#51): "DORA metrics View: standard · numbers · scoring" on one
// line, the title in its own element, which names the table and its region,
// the switch beside it, so the table's name is never the switch's text.
const captionWithSwitch = `<table aria-labelledby="metrics-caption">
        <caption><span id="metrics-caption">DORA metrics</span> <span class="views">View: `

// TestViewSwitchSitsInTheCaption (forsgren#51): on each view's page and on
// the root with a view, the switch follows the caption's title on its line,
// never a paragraph above the table; the region and the table are both
// named by the title alone, and the current view is still marked.
func TestViewSwitchSitsInTheCaption(t *testing.T) {
	data := acmeProjects(metrics.LeadTime{}, unrecovered, oneFailed, noRework)
	pages := map[string]string{"standard/index.html": "page", "numbers/index.html": "page", "index.html": "true"}
	for name, current := range pages {
		data.View = "numbers"
		got := rendered(t, name, data)
		wantAll(t, name, got, captionWithSwitch, `role="region" aria-labelledby="metrics-caption"`,
			`<span aria-current="`+current+`">`)
		wantNone(t, name, got, `<p class="views">`, `<caption id=`)
		if n := strings.Count(got, `id="metrics-caption"`); n != 1 {
			t.Errorf("%s: want one element with the id metrics-caption, got %d", name, n)
		}
	}
}

// TestViewsShowARowWithoutDeploymentsAsTheirOwnCells (forsgren#46): the
// numbers page says no sentence for it, five cells, 0 for the deployment
// frequency (a real zero) and - for the other four; the standard page keeps
// its sentence across the row.
func TestViewsShowARowWithoutDeploymentsAsTheirOwnCells(t *testing.T) {
	data := Placeholder("0.4.2")
	data.Rows = Table([]metrics.Row{{Level: metrics.ProjectRow, Name: "Acme Empty"}})
	numbers := rendered(t, "numbers/index.html", data)
	if !row("Acme Empty", "0", "-", "-", "-", "-").MatchString(numbers) {
		t.Errorf("want the row of Acme Empty to read 0, -, -, -, -, got:\n%s", numbers)
	}
	wantNone(t, "numbers/index.html", numbers, "No deployments recorded yet", "colspan")
	wantAll(t, "standard/index.html", rendered(t, "standard/index.html", data),
		`<td colspan="5">No deployments recorded yet</td>`)
}

// viewData is the page data of the views' golden pages: Acme Shop with all
// five numbers, Acme Tools with one failed deployment (forsgren#46).
func viewData() Data {
	recovery := metrics.Recovery{Recoveries: 2, Median: 3 * time.Hour, Band: metrics.LessThanOneDay, Unrecovered: 1}
	shop := metrics.LeadTime{Commits: 48, Median: 2*time.Hour + 7*time.Minute, Band: metrics.LessThanOneDay}
	threeFailed := metrics.ChangeFailRate{Deployments: 15, FailedDeployments: 3, Failed: 3, Band: metrics.TwentyPercent}
	return acmeProjects(shop, recovery, threeFailed,
		metrics.ReworkRate{Deployments: 12, Rework: 2, Band: metrics.TwentyPercent})
}

// TestViewPagesMatchGolden (forsgren#46): each view's page, in its own
// folder, pinned byte for byte: the scoring page (forsgren#47) shows from the
// same data each metric's score, "-" where a metric has no data, and Overall
// Performance.
func TestViewPagesMatchGolden(t *testing.T) {
	checkPageGolden(t, "standard/index.html", "testdata/standard.golden.html", viewData())
	checkPageGolden(t, "numbers/index.html", "testdata/numbers.golden.html", viewData())
	checkPageGolden(t, "scoring/index.html", "testdata/scoring.golden.html", viewData())
}

// TestViewPagesWithoutDataMatchGolden (forsgren#46): the views of the
// placeholder build, which has no rows and so no switch.
func TestViewPagesWithoutDataMatchGolden(t *testing.T) {
	data := Placeholder("0.4.2")
	data.AsOf = "2026-10-03 12:00"
	checkPageGolden(t, "standard/index.html", "testdata/standard.placeholder.golden.html", data)
	checkPageGolden(t, "numbers/index.html", "testdata/numbers.placeholder.golden.html", data)
}

// TestNumbersPageWithoutDeploymentsMatchesGolden (forsgren#46): a project
// with no deployment recorded yet is five cells on the numbers page.
func TestNumbersPageWithoutDeploymentsMatchesGolden(t *testing.T) {
	data := Placeholder("0.4.2")
	data.AsOf = "2026-10-03 12:00"
	data.Rows = Table([]metrics.Row{{Level: metrics.ProjectRow, Name: "Acme Empty"}})
	checkPageGolden(t, "numbers/index.html", "testdata/numbers.no-data.golden.html", data)
}

// TestWriteSiteFailsWhenAViewFolderIsAFile (forsgren#46): a view's folder
// that cannot be created is an error, never a page lost without a word.
func TestWriteSiteFailsWhenAViewFolderIsAFile(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "numbers"), []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	if n, err := WriteSite(dir, Placeholder("0.4.2")); err == nil {
		t.Errorf("want an error when a view's folder is a regular file, got %d pages", n)
	}
}

// TestRootPageFollowsItsDataView (forsgren#46): the root page shows the view
// of its data with the switch, the links relative to the root, its view
// marked aria-current="true", since the root is not that view's page
// (Yves's ruling); with no view it is the plain root page, and with no rows
// it has no switch.
func TestRootPageFollowsItsDataView(t *testing.T) {
	data := acmeProjects(metrics.LeadTime{}, unrecovered, oneFailed, noRework)
	const (
		std, num, sco = `<a href="standard/">standard</a>`, `<a href="numbers/">numbers</a>`, `<a href="scoring/">scoring</a>`
		now           = `<span aria-current="true">%s</span>`
	)
	for view, want := range map[string]string{
		"standard": "View: " + fmt.Sprintf(now, "standard") + " · " + num + " · " + sco,
		"numbers":  "View: " + std + " · " + fmt.Sprintf(now, "numbers") + " · " + sco,
		"scoring":  "View: " + std + " · " + num + " · " + fmt.Sprintf(now, "scoring"),
	} {
		data.View = view
		got := rendered(t, "index.html", data)
		wantAll(t, "index.html", got, want, `href="styles.css"`, `<a href="legend.html">What the bands mean</a>`)
		wantNone(t, "index.html", got, "../", `aria-current="page"`)
	}
	data.View = "numbers"
	wantAll(t, "index.html", rendered(t, "index.html", data), "<td>12</td>")
	data.View = "scoring"
	wantAll(t, "index.html", rendered(t, "index.html", data), `<th scope="col">Overall Performance</th>`, "<td>8.4</td>")
	data.View = ""
	wantNone(t, "index.html", rendered(t, "index.html", data), "View:", "aria-current")
	placeholder := Placeholder("0.4.2")
	placeholder.View = "numbers"
	wantNone(t, "index.html", rendered(t, "index.html", placeholder), "View:")
}
