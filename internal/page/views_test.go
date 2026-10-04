package page

import (
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
	// The switch above the table has its own " · "; the table has none.
	table := got[strings.Index(got, "<table"):strings.Index(got, "</table>")]
	wantNone(t, "numbers/index.html", table, "Between once", "Less than", "No lead time yet", "not completed yet", " · ")
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

// TestViewSwitchMarksTheCurrentView (forsgren#46): "View: standard ·
// numbers", the current view plain text marked aria-current="page", the
// other a link to its folder; scoring is not linked before #47.
func TestViewSwitchMarksTheCurrentView(t *testing.T) {
	data := acmeProjects(metrics.LeadTime{}, unrecovered, oneFailed, noRework)
	for name, want := range map[string]string{
		"standard/index.html": `View: <span aria-current="page">standard</span> · <a href="../numbers/">numbers</a>`,
		"numbers/index.html":  `View: <a href="../standard/">standard</a> · <span aria-current="page">numbers</span>`,
	} {
		got := rendered(t, name, data)
		wantAll(t, name, got, want)
		if n := strings.Count(got, `aria-current="page"`); n != 1 {
			t.Errorf("%s: want one current view, got %d", name, n)
		}
		wantNone(t, name, got, "scoring")
	}
}

// TestViewsShowARowWithoutDeploymentsAsTheirOwnCells (forsgren#46): the
// numbers page says no sentence for it, five cells, 0 for the deployment
// frequency (a real zero) and - for the other four; the standard page keeps
// its sentence across the row.
func TestViewsShowARowWithoutDeploymentsAsTheirOwnCells(t *testing.T) {
	data := Placeholder("0.1.1")
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
// folder, pinned byte for byte.
func TestViewPagesMatchGolden(t *testing.T) {
	checkPageGolden(t, "standard/index.html", "testdata/standard.golden.html", viewData())
	checkPageGolden(t, "numbers/index.html", "testdata/numbers.golden.html", viewData())
}

// TestViewPagesWithoutDataMatchGolden (forsgren#46): the views of the
// placeholder build, which has no rows and so no switch.
func TestViewPagesWithoutDataMatchGolden(t *testing.T) {
	data := Placeholder("0.1.1")
	data.AsOf = "2026-10-03 12:00"
	checkPageGolden(t, "standard/index.html", "testdata/standard.placeholder.golden.html", data)
	checkPageGolden(t, "numbers/index.html", "testdata/numbers.placeholder.golden.html", data)
}

// TestNumbersPageWithoutDeploymentsMatchesGolden (forsgren#46): a project
// with no deployment recorded yet is five cells on the numbers page.
func TestNumbersPageWithoutDeploymentsMatchesGolden(t *testing.T) {
	data := Placeholder("0.1.1")
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
	if n, err := WriteSite(dir, Placeholder("0.1.1")); err == nil {
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
	for view, want := range map[string]string{
		"standard": `View: <span aria-current="true">standard</span> · <a href="numbers/">numbers</a>`,
		"numbers":  `View: <a href="standard/">standard</a> · <span aria-current="true">numbers</span>`,
	} {
		data.View = view
		got := rendered(t, "index.html", data)
		wantAll(t, "index.html", got, want, `href="styles.css"`, `<a href="legend.html">What the bands mean</a>`)
		wantNone(t, "index.html", got, "../", `aria-current="page"`)
	}
	data.View = "numbers"
	wantAll(t, "index.html", rendered(t, "index.html", data), "<td>12</td>")
	data.View = ""
	wantNone(t, "index.html", rendered(t, "index.html", data), "View:", "aria-current")
	placeholder := Placeholder("0.1.1")
	placeholder.View = "numbers"
	wantNone(t, "index.html", rendered(t, "index.html", placeholder), "View:")
}
