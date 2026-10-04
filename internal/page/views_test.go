package page

import (
	"regexp"
	"slices"
	"strings"
	"testing"

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
	wantNone(t, "numbers/index.html", got, "Between once", "Less than", "No lead time yet", "not completed yet", " · ")
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
