package main

import (
	"strings"
	"testing"
)

// figuresAll is the config line that makes the TBD table show the mean, the
// median and the 90th percentile of each measure (forsgren#423).
const figuresAll = "tbd_figures: all\n"

// tbdSiteIn renders validConfig with tbd_page: true and the config line
// figures (none for the default), over the data at path, and returns tbd.html.
func tbdSiteIn(t *testing.T, figures, path string) string {
	t.Helper()
	return readSite(t, renderInto(t, "--config", writeConfig(t, validConfig+tbdOn+figures), "--data", path), "tbd.html")
}

// TestRenderTbdFiguresChoosesTheColumnsOfTheTbdTable (forsgren#423): without
// the key, and with tbd_figures: median, tbd.html has the median of each
// measure in one header row; with tbd_figures: all it has the mean, the median
// and the p90 under two header rows. Neither has a deviation or a gaps column
// (decision #424 C).
func TestRenderTbdFiguresChoosesTheColumnsOfTheTbdTable(t *testing.T) {
	pinNow(t)
	data := writeData(t, acmeHistory(), acmeCommits())
	for name, figures := range map[string]string{"default": "", "median": "tbd_figures: median\n"} {
		got := tbdSiteIn(t, figures, data)
		wantIn(t, got, `<th scope="col">Mainline Interval (median)</th>`, `<th scope="col">PR Lead Time (median)</th>`)
		for _, not := range []string{"rowspan", "colgroup", ">mean<", ">deviation<", ">gaps<"} {
			if strings.Contains(got, not) {
				t.Errorf("%s: want no %q in tbd.html, got:\n%s", name, not, got)
			}
		}
	}
	got := tbdSiteIn(t, figuresAll, data)
	wantIn(t, got, `<th scope="colgroup" colspan="3">Mainline Interval</th>`,
		`<th scope="colgroup" colspan="3">PR Lead Time</th>`, `<th scope="col">mean</th>`, `<th scope="col">p90</th>`)
	for _, not := range []string{">deviation<", ">gaps<", ">pull requests<"} {
		if strings.Contains(got, not) {
			t.Errorf("all: want no %q in tbd.html, got:\n%s", not, got)
		}
	}
}

// TestRenderTbdFiguresThatIsNotAcceptedShowsTheMedianAndSaysWhy (forsgren#423,
// #183): any other value is not used: the table has the median only, the
// settings page lists the key with the value as written, the reason and the
// default in force.
func TestRenderTbdFiguresThatIsNotAcceptedShowsTheMedianAndSaysWhy(t *testing.T) {
	pinNow(t)
	data := writeData(t, acmeHistory(), acmeCommits())
	dir := renderInto(t, "--config", writeConfig(t, validConfig+tbdOn+"tbd_figures: both\n"), "--data", data)
	wantIn(t, readSite(t, dir, "tbd.html"), `<th scope="col">Mainline Interval (median)</th>`)
	settings := readSite(t, dir, "settings.html")
	wants := []string{`<th scope="row">tbd_figures</th>`,
		`<span class="written">both</span> is not accepted: use median or all.`, "median, all"}
	for _, want := range wants {
		if !strings.Contains(settings, want) {
			t.Errorf("want %q in settings.html, got:\n%s", want, settings)
		}
	}
}
