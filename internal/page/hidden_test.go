package page

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestWriteSiteLeavesOutHiddenPagesAndRemovesStaleOnes (forsgren#159): a
// hidden issues or days page is not written and not counted, and a file of it
// left in a reused out dir is removed; the other pages are written.
func TestWriteSiteLeavesOutHiddenPagesAndRemovesStaleOnes(t *testing.T) {
	cases := map[string]struct {
		hidden map[string]bool
		gone   []string
		kept   []string
		pages  int
	}{
		"days":   {map[string]bool{"days": true}, []string{"days.html"}, []string{"issues.html"}, 8},
		"issues": {map[string]bool{"issues": true}, []string{"issues.html"}, []string{"days.html"}, 8},
		"both":   {map[string]bool{"days": true, "issues": true}, []string{"days.html", "issues.html"}, nil, 7},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			dir := t.TempDir()
			writeStale(t, dir)
			n, err := WriteSite(dir, placeholderHiding(tc.hidden))
			if err != nil || n != tc.pages {
				t.Fatalf("want %d pages and no error, got %d, %v", tc.pages, n, err)
			}
			wantGone(t, dir, tc.gone)
			wantRendered(t, dir, append(tc.kept, "index.html", "legend.html", "settings.html"))
		})
	}
}

// TestWriteSiteFailsWhenAHiddenPageCannotBeRemoved (forsgren#159): a hidden
// page whose name is a folder with files in it cannot be removed, and the
// write fails instead of leaving the page behind unnoticed.
func TestWriteSiteFailsWhenAHiddenPageCannotBeRemoved(t *testing.T) {
	dir := t.TempDir()
	folder := filepath.Join(dir, "days.html")
	if err := os.MkdirAll(folder, 0o750); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(folder, "x"), []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	if n, err := WriteSite(dir, placeholderHiding(map[string]bool{"days": true})); err == nil {
		t.Errorf("want an error when days.html cannot be removed, got %d pages", n)
	}
}

// TestWriteSiteHidesAPageThatWasNeverWritten (forsgren#159): a hidden page
// with no file in a fresh out dir is no error.
func TestWriteSiteHidesAPageThatWasNeverWritten(t *testing.T) {
	if n, err := WriteSite(t.TempDir(), placeholderHiding(map[string]bool{"days": true})); err != nil || n != 8 {
		t.Errorf("want 8 pages and no error, got %d, %v", n, err)
	}
}

// placeholderHiding is the placeholder page data with hidden as its hidden
// pages.
func placeholderHiding(hidden map[string]bool) Data {
	data := Placeholder("1.6.2")
	data.Hidden = hidden
	return data
}

// writeStale leaves an old days.html and issues.html in dir.
func writeStale(t *testing.T, dir string) {
	t.Helper()
	for _, stale := range []string{"days.html", "issues.html"} {
		if err := os.WriteFile(filepath.Join(dir, stale), []byte("old"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
}

// wantRendered fails t for each of files that is missing from dir or still
// holds the old content.
func wantRendered(t *testing.T, dir string, files []string) {
	t.Helper()
	for _, f := range files {
		b, err := os.ReadFile(filepath.Clean(filepath.Join(dir, f)))
		if err != nil || string(b) == "old" {
			t.Errorf("want %s rendered, got %q, %v", f, b, err)
		}
	}
}

// wantGone fails t for each of files that is still in dir.
func wantGone(t *testing.T, dir string, files []string) {
	t.Helper()
	for _, f := range files {
		if _, err := os.Stat(filepath.Join(dir, f)); !os.IsNotExist(err) {
			t.Errorf("want %s gone from the site, got %v", f, err)
		}
	}
}

// TestMenuLeavesOutHiddenPages (forsgren#159): the menu of every page written
// leaves out the entry and the link of a hidden issues or days page, and still
// holds the three views and the page that is shown.
func TestMenuLeavesOutHiddenPages(t *testing.T) {
	cases := map[string]struct {
		hidden map[string]bool
		gone   []string
	}{
		"days":   {map[string]bool{"days": true}, []string{"days.html", "Daily</a>"}},
		"issues": {map[string]bool{"issues": true}, []string{"issues.html", "Issues</a>"}},
		"both": {map[string]bool{"days": true, "issues": true},
			[]string{"issues.html", "days.html", "Issues</a>", "Daily</a>"}},
	}
	for name, tc := range cases {
		data := calculated()
		data.Hidden = tc.hidden
		for _, page := range PageNames() {
			if !data.hides(page) {
				wantMenuWithout(t, name+" "+page, rendered(t, page, data), tc.gone)
			}
		}
	}
}

// wantMenuWithout fails t when html holds one of gone, or lacks the views.
func wantMenuWithout(t *testing.T, name, html string, gone []string) {
	t.Helper()
	for _, g := range gone {
		if strings.Contains(html, g) {
			t.Errorf("%s: want no %q on the page", name, g)
		}
	}
	if !strings.Contains(html, "Scoring") {
		t.Errorf("%s: want the views in the menu", name)
	}
}

// legendPagesText is the legend's explanation of the two keys (forsgren#159).
const legendPagesText = "<p>The Issues page and the Daily page are shown or hidden with issues_page and days_page " +
	"in forsgren.config.yml. By default the Issues page is shown (issues_page: true) and the Daily page is hidden " +
	"(days_page: false); days_page: true brings the Daily page back. A hidden page is not generated and has no " +
	"entry in the menu. To add the Daily page, set days_page: true and run forsgren again to regenerate the report."

// TestLegendExplainsTheTwoPageKeysWhateverIsHidden (forsgren#159, Yves's
// ruling on decision #165): the legend keeps its Issues pages section and says
// how issues_page and days_page show or hide the two pages, the same text
// whether they are shown or hidden.
func TestLegendExplainsTheTwoPageKeysWhateverIsHidden(t *testing.T) {
	hidden := map[string]map[string]bool{
		"none": nil, "days": {"days": true}, "both": {"days": true, "issues": true},
	}
	for name, hide := range hidden {
		data := calculated()
		data.Hidden = hide
		html := rendered(t, "legend.html", data)
		for _, want := range []string{"<h2>Issues pages</h2>", legendPagesText} {
			if !strings.Contains(html, want) {
				t.Errorf("%s hidden: want %q in the legend", name, want)
			}
		}
	}
}

// legendNumbersScoringText is the sentence the legend adds on the numbers and
// scoring page's key, and legendScoresText the one under Scores (forsgren#55).
const (
	legendNumbersScoringText = " The Numbers and scoring page, shown only with numbers_scoring_page: true " +
		"(default false), puts each metric's number and its score in one cell, written number \u00b7 score, " +
		"with a dash where there is no data.</p>"
	legendScoresText = "The Numbers and scoring page, when it is shown, has the number and the score of each " +
		"metric in one cell."
)

// TestLegendExplainsTheNumbersAndScoringPageWhateverIsHidden (forsgren#55,
// decision 7): the legend ends the paragraph on the page keys with the
// sentence on numbers_scoring_page and says under Scores what the page shows,
// the same text whether the page is shown or hidden.
func TestLegendExplainsTheNumbersAndScoringPageWhateverIsHidden(t *testing.T) {
	for name, hide := range map[string]map[string]bool{"shown": nil, "hidden": {viewNumbersScoring: true}} {
		data := calculated()
		data.Hidden = hide
		html := rendered(t, "legend.html", data)
		for _, want := range []string{"regenerate the report." + legendNumbersScoringText, legendScoresText} {
			if !strings.Contains(html, want) {
				t.Errorf("%s: want %q in the legend", name, want)
			}
		}
	}
}

// TestWriteSiteLeavesOutAHiddenNumbersAndScoringPage (forsgren#55): a hidden
// numbers and scoring page is not written and not counted, a stale file of it
// in a reused out dir is removed with its folder once empty, and a folder
// that holds something else keeps it; the other eight pages are written.
func TestWriteSiteLeavesOutAHiddenNumbersAndScoringPage(t *testing.T) {
	hidden := placeholderHiding(map[string]bool{viewNumbersScoring: true})
	for name, other := range map[string]string{"empty folder": "", "folder with another file": "keep.txt"} {
		t.Run(name, func(t *testing.T) {
			dir := t.TempDir()
			folder := writeStaleFolder(t, dir, other)
			n, err := WriteSite(dir, hidden)
			if err != nil || n != 8 {
				t.Fatalf("want 8 pages and no error, got %d, %v", n, err)
			}
			wantGone(t, dir, []string{"numbers-scoring/index.html"})
			if _, err := os.Stat(folder); (other == "") != os.IsNotExist(err) {
				t.Errorf("want the folder gone only when empty (other file %q), got %v", other, err)
			}
			wantRendered(t, dir, []string{"index.html", "numbers/index.html", "scoring/index.html", "days.html"})
		})
	}
}

// writeStaleFolder leaves an old numbers-scoring/index.html in dir, and the
// file other beside it when named; it returns the folder.
func writeStaleFolder(t *testing.T, dir, other string) string {
	t.Helper()
	folder := filepath.Join(dir, viewNumbersScoring)
	if err := os.MkdirAll(folder, 0o750); err != nil {
		t.Fatal(err)
	}
	for _, f := range []string{"index.html", other} {
		if f == "" {
			continue
		}
		if err := os.WriteFile(filepath.Join(folder, f), []byte("old"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	return folder
}

// TestWriteSiteHidesANumbersAndScoringPageThatWasNeverWritten (forsgren#55): no
// file and no folder in a fresh out dir is no error, and none is made.
func TestWriteSiteHidesANumbersAndScoringPageThatWasNeverWritten(t *testing.T) {
	dir := t.TempDir()
	if n, err := WriteSite(dir, placeholderHiding(map[string]bool{viewNumbersScoring: true})); err != nil || n != 8 {
		t.Errorf("want 8 pages and no error, got %d, %v", n, err)
	}
	wantGone(t, dir, []string{viewNumbersScoring})
}
