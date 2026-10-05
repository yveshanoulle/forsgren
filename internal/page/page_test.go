package page

import (
	"bytes"
	"flag"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// -update rewrites the golden files from the current output. Use it only
// after reading the diff the failing golden test printed.
var update = flag.Bool("update", false, "rewrite testdata/*.golden.html")

func TestPlaceholderMatchesGolden(t *testing.T) {
	data := Placeholder("0.1.3")
	data.AsOf = "2026-10-03 12:00"
	checkGolden(t, "testdata/index.golden.html", data)
}

// TestNoProjectsPageMatchesGolden (forsgren#12): the page of an installation
// whose config lists no projects says so, besides its version.
func TestNoProjectsPageMatchesGolden(t *testing.T) {
	data := Placeholder("0.1.3")
	data.NoProjects = true
	data.AsOf = "2026-10-03 12:00"
	checkGolden(t, "testdata/index.no-projects.golden.html", data)
}

// acmeProjects is the page data of two projects counted back from
// 2026-10-03 12:00 UTC (forsgren#38: one table, a row per project): Acme
// Shop with deployments, the lead time shop, the recovery time recovery
// and the change fail rate changeFail; Acme Tools with one failed
// deployment and nothing else, the worst case, shown in full (Yves's ruling
// on decision #35).
func acmeProjects(shop metrics.LeadTime, recovery metrics.Recovery, changeFail metrics.ChangeFailRate,
	rework metrics.ReworkRate,
) Data {
	data := Placeholder("0.1.3")
	data.AsOf = "2026-10-03 12:00"
	latest := time.Date(2026, 10, 1, 9, 30, 0, 0, time.UTC)
	frequency := metrics.Frequency{
		Project: "Acme Shop", Last7: 3, Last30: 12, Last180: 12, Latest: latest, Band: metrics.DailyToWeekly,
	}
	data.Rows = Table([]metrics.Row{
		{Level: metrics.ProjectRow, Name: "Acme Shop", Frequency: frequency, LeadTime: shop, Recovery: recovery,
			ChangeFail: changeFail, Rework: rework},
		{Level: metrics.ProjectRow, Name: "Acme Tools", Frequency: metrics.Frequency{Band: metrics.LessThanSixMonthly},
			Recovery: metrics.Recovery{Unrecovered: 1}, ChangeFail: metrics.ChangeFailRate{
				Deployments: 1, FailedDeployments: 1, Failed: 1, Band: metrics.HundredPercent,
			}},
	})
	return data
}

// unrecovered is Acme Shop's recovery time in acmeProjects' pages: one
// failure, not recovered yet.
var unrecovered = metrics.Recovery{Unrecovered: 1}

// oneFailed is Acme Shop's change fail rate in acmeProjects' pages: 1
// failed deployment of 13 (forsgren#18).
var oneFailed = metrics.ChangeFailRate{Deployments: 13, FailedDeployments: 1, Failed: 1, Band: metrics.ZeroPercent}

// noRework is Acme Shop's deployment rework rate in acmeProjects' pages
// unless a test sets another (forsgren#39): none of its 12 successful
// deployments is rework.
var noRework = metrics.ReworkRate{Deployments: 12, Band: metrics.ZeroPercent}

// TestFrequencyPageMatchesGolden (forsgren#12, step 7; forsgren#38): with
// projects the page is one table, a row per project in the given order,
// each cell short, a link to the legend under it; a project with no
// deployment says so across its row, and one with deployments but no commit
// in the window says "No lead time yet".
func TestFrequencyPageMatchesGolden(t *testing.T) {
	checkGolden(t, "testdata/index.frequency.golden.html",
		acmeProjects(metrics.LeadTime{}, unrecovered, oneFailed, noRework))
}

// TestLeadTimePageMatchesGolden (forsgren#16, step 5): a project's row shows
// its lead time for changes, the band, the median and the count.
func TestLeadTimePageMatchesGolden(t *testing.T) {
	shop := metrics.LeadTime{Commits: 3, Median: 17 * time.Minute, Band: metrics.LessThanOneHour}
	checkGolden(t, "testdata/index.leadtime.golden.html", acmeProjects(shop, unrecovered, oneFailed, noRework))
}

// TestRecoveryPageMatchesGolden (forsgren#17): a project's row shows its
// failed deployment recovery time, the band, the median, the count and the
// failures not recovered yet.
func TestRecoveryPageMatchesGolden(t *testing.T) {
	recovery := metrics.Recovery{Recoveries: 2, Median: 3 * time.Hour, Band: metrics.LessThanOneDay, Unrecovered: 1}
	threeFailed := metrics.ChangeFailRate{Deployments: 15, FailedDeployments: 3, Failed: 3, Band: metrics.TwentyPercent}
	checkGolden(t, "testdata/index.recovery.golden.html", acmeProjects(metrics.LeadTime{}, recovery, threeFailed,
		metrics.ReworkRate{Deployments: 12, Rework: 2, Band: metrics.TwentyPercent}))
}

// TestChangeFailPageMatchesGolden (forsgren#18): a project's row shows its
// change fail rate, the band, the rate and the failed changes of the
// deployments.
func TestChangeFailPageMatchesGolden(t *testing.T) {
	changeFail := metrics.ChangeFailRate{
		Deployments: 13, FailedDeployments: 1, FailureIssues: 2, Failed: 2, Band: metrics.TwentyPercent,
	}
	checkGolden(t, "testdata/index.changefail.golden.html", acmeProjects(metrics.LeadTime{}, unrecovered, changeFail,
		metrics.ReworkRate{Deployments: 12, Rework: 9, Band: metrics.EightyPercent}))
}

// TestNoDataPageMatchesGolden: projects with no deployment recorded yet,
// successful or failed, each say so across their row.
func TestNoDataPageMatchesGolden(t *testing.T) {
	data := Placeholder("0.1.3")
	data.AsOf = "2026-10-03 12:00"
	data.Rows = Table([]metrics.Row{
		{Level: metrics.ProjectRow, Name: "Acme Shop"}, {Level: metrics.ProjectRow, Name: "Acme Tools"},
	})
	checkGolden(t, "testdata/index.no-data.golden.html", data)
}

// labelledRows are the metrics' rows of the labels page (forsgren#38),
// shaped as Yves's example: Acme Shop's total, then its labels ADMIN, API,
// IOS (nothing deployed yet) and Website; Acme Tools and Acme Docs with no
// labels.
func labelledRows() []metrics.Row {
	latest := time.Date(2026, 10, 2, 8, 0, 0, 0, time.UTC)
	often := metrics.Frequency{Last7: 4, Last30: 16, Last180: 40, Latest: latest, Band: metrics.DailyToWeekly}
	rarely := metrics.Frequency{Last30: 2, Last180: 5, Latest: latest, Band: metrics.WeeklyToMonthly}
	fast := metrics.LeadTime{Commits: 48, Median: 2*time.Hour + 7*time.Minute, Band: metrics.LessThanOneDay}
	slow := metrics.LeadTime{Commits: 5, Median: 3*24*time.Hour + 4*time.Hour, Band: metrics.OneDayToOneWeek}
	recovered := metrics.Recovery{Recoveries: 1, Median: 40 * time.Minute, Band: metrics.LessThanOneHour}
	cf := func(deployments, failed int, band metrics.ChangeFailBand) metrics.ChangeFailRate {
		return metrics.ChangeFailRate{Deployments: deployments, FailedDeployments: failed, Failed: failed, Band: band}
	}
	row := func(level metrics.Level, name string, f metrics.Frequency, l metrics.LeadTime, r metrics.Recovery,
		c metrics.ChangeFailRate,
	) metrics.Row {
		return metrics.Row{Level: level, Name: name, Frequency: f, LeadTime: l, Recovery: r, ChangeFail: c}
	}
	label := metrics.LabelRow
	rows := []metrics.Row{
		row(metrics.ProjectRow, "Acme Shop", often, fast, recovered, cf(18, 1, metrics.ZeroPercent)),
		row(label, "ADMIN", rarely, slow, metrics.Recovery{}, cf(2, 0, metrics.ZeroPercent)),
		row(label, "API", often, fast, recovered, cf(7, 1, metrics.TwentyPercent)),
		{Level: label, Name: "IOS"},
		row(label, "Website", rarely, metrics.LeadTime{}, metrics.Recovery{Unrecovered: 1}, cf(3, 1, metrics.FortyPercent)),
		row(metrics.ProjectRow, "Acme Tools", metrics.Frequency{Last30: 3, Latest: latest, Band: metrics.WeeklyToMonthly},
			slow, metrics.Recovery{}, cf(3, 0, metrics.ZeroPercent)),
		{Level: metrics.ProjectRow, Name: "Acme Docs"},
	}
	rows[0].Rework = metrics.ReworkRate{Deployments: 18, Rework: 2, Band: metrics.TwentyPercent}
	rows[2].Rework = metrics.ReworkRate{Deployments: 7, Rework: 1, Band: metrics.TwentyPercent}
	return rows
}

// TestLabelsPageMatchesGolden (forsgren#38): a project with label rows is
// headed "(total)", its labels' rows follow it, indented, each with its
// project's name for a screen reader; a project without labels is one row.
func TestLabelsPageMatchesGolden(t *testing.T) {
	data := Placeholder("0.1.3")
	data.AsOf = "2026-10-03 12:00"
	data.Rows = Table(labelledRows())
	checkGolden(t, "testdata/index.labels.golden.html", data)
}

// TestTableHeadsTheRows (forsgren#38): "(total)" only on a project that has
// label rows, and each label's row knows its project.
func TestTableHeadsTheRows(t *testing.T) {
	var got []string
	for _, r := range Table(labelledRows()) {
		got = append(got, r.Project+"|"+r.Heading)
	}
	want := []string{
		"|Acme Shop (total)", "Acme Shop|ADMIN", "Acme Shop|API", "Acme Shop|IOS", "Acme Shop|Website",
		"|Acme Tools", "|Acme Docs",
	}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Errorf("want %v, got %v", want, got)
	}
}

// checkGolden renders index.html with data and compares it with the golden
// file, rewriting it first under -update.
func checkGolden(t *testing.T, golden string, data Data) {
	t.Helper()
	checkPageGolden(t, "index.html", golden, data)
}

// checkPageGolden is checkGolden for the named page.
func checkPageGolden(t *testing.T, name, golden string, data Data) {
	t.Helper()
	var got bytes.Buffer
	if err := Render(&got, name, data); err != nil {
		t.Fatalf("Render: %v", err)
	}
	if *update {
		if err := os.WriteFile(golden, got.Bytes(), 0o600); err != nil {
			t.Fatalf("update golden: %v", err)
		}
	}
	want, err := os.ReadFile(filepath.Clean(golden))
	if err != nil {
		t.Fatalf("read golden: %v", err)
	}
	if !bytes.Equal(got.Bytes(), want) {
		t.Errorf("%s differs from %s\n--- got ---\n%s\n--- want ---\n%s", name, golden, got.String(), want)
	}
}

func TestRenderEscapesFields(t *testing.T) {
	var got bytes.Buffer
	data := Data{Title: "forsgren", Message: `<script>alert("x")</script>`}
	if err := Render(&got, "index.html", data); err != nil {
		t.Fatalf("Render: %v", err)
	}
	if strings.Contains(got.String(), "<script>") {
		t.Errorf("a <script> in a field reached the page unescaped:\n%s", got.String())
	}
	if !strings.Contains(got.String(), "&lt;script&gt;") {
		t.Errorf("want the field escaped as &lt;script&gt;, got:\n%s", got.String())
	}
}

func TestRenderUnknownPage(t *testing.T) {
	err := Render(&bytes.Buffer{}, "missing.html", Placeholder("0.1.3"))
	if err == nil || !strings.Contains(err.Error(), "missing.html") {
		t.Errorf("want an error naming missing.html, got %v", err)
	}
}

// TestLegendPageMatchesGolden (forsgren#39, step 1): the band explanations
// are the page legend.html, with a link back to the table; the table page
// holds none of them.
func TestLegendPageMatchesGolden(t *testing.T) {
	data := Placeholder("0.1.3")
	data.AsOf = "2026-10-03 12:00"
	checkPageGolden(t, "legend.html", "testdata/legend.golden.html", data)
}

// TestLegendPageTitleNamesIt (forsgren#39, step 4): the legend page's title
// is its link's text, then the site's title; its header shows no site-name line (forsgren#41).
func TestLegendPageTitleNamesIt(t *testing.T) {
	got := rendered(t, "legend.html", acmeProjects(metrics.LeadTime{}, unrecovered, oneFailed, noRework))
	if !strings.Contains(got, "<title>What the bands mean · forsgren</title>") {
		t.Errorf("want the legend page titled %q, got:\n%s", "What the bands mean · forsgren", got)
	}
	if strings.Contains(got, `class="site-name"`) {
		t.Errorf("want no site-name line in the legend page's header, got:\n%s", got)
	}
}

// rendered is the page name rendered with data.
func rendered(t *testing.T, name string, data Data) string {
	t.Helper()
	var got bytes.Buffer
	if err := Render(&got, name, data); err != nil {
		t.Fatalf("Render %s: %v", name, err)
	}
	return got.String()
}

// legendItem is one item of the legend page's band lists.
var legendItem = regexp.MustCompile(`<li>[^<]*</li>`)

// TestTablePageLinksToTheLegend (forsgren#39, step 1): the table page
// carries a link to legend.html and none of the band explanations: no item
// of the legend page's band lists (forsgren#39, step 4).
func TestTablePageLinksToTheLegend(t *testing.T) {
	data := acmeProjects(metrics.LeadTime{}, unrecovered, oneFailed, noRework)
	got := rendered(t, "index.html", data)
	if !strings.Contains(got, `<a href="legend.html">What the bands mean</a>`) {
		t.Errorf("want a link to legend.html on the table page, got:\n%s", got)
	}
	if strings.Contains(got, "<h2>Legend</h2>") {
		t.Errorf("want the legend off the table page, got:\n%s", got)
	}
	items := legendItem.FindAllString(rendered(t, "legend.html", data), -1)
	if len(items) == 0 {
		t.Fatal("want band lists on the legend page, found none")
	}
	for _, item := range items {
		if strings.Contains(got, item) {
			t.Errorf("want the legend's %s off the table page", item)
		}
	}
}

// TestEveryPageNamesFiveMetrics (forsgren#39): with rework rate as the
// table's fifth column, every page's footer names five DORA metrics
// (forsgren#41: in the footer's paragraph; the table's caption says "DORA
// metrics", forsgren#45).
func TestEveryPageNamesFiveMetrics(t *testing.T) {
	for _, name := range PageNames() {
		var got bytes.Buffer
		if err := Render(&got, name, acmeProjects(metrics.LeadTime{}, unrecovered, oneFailed, noRework)); err != nil {
			t.Fatalf("Render %s: %v", name, err)
		}
		if !strings.Contains(got.String(), " The five DORA metrics, from GitHub data.") {
			t.Errorf("%s: want the footer to name the five DORA metrics, got:\n%s", name, got.String())
		}
	}
}

// TestWriteSiteWritesFivePagesAndStyles (forsgren#46, #47): the root page and
// the legend, and each view's page, standard, numbers and scoring, in its own
// folder.
func TestWriteSiteWritesFivePagesAndStyles(t *testing.T) {
	dir := t.TempDir()
	n, err := WriteSite(dir, Placeholder("0.1.3"))
	if err != nil {
		t.Fatalf("WriteSite: %v", err)
	}
	if n != 5 {
		t.Errorf("want 5 pages written, got %d", n)
	}
	for _, name := range []string{
		"index.html", "legend.html", "standard/index.html", "numbers/index.html", "scoring/index.html", "styles.css",
	} {
		if _, err := os.Stat(filepath.Join(dir, name)); err != nil {
			t.Errorf("want %s in the site: %v", name, err)
		}
	}
}

func TestWriteSiteFailsWhenDirIsAFile(t *testing.T) {
	file := filepath.Join(t.TempDir(), "not-a-dir")
	if err := os.WriteFile(file, []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	if n, err := WriteSite(file, Placeholder("0.1.3")); err == nil {
		t.Errorf("want an error when the output is a regular file, got %d pages", n)
	}
}

// TestLabelDashIsDecorative (forsgren#38, review): the dash before a label
// row's heading is drawn for the eye only, with empty alternative text, so
// a screen reader reads "Acme Shop: API", never "en dash API".
func TestLabelDashIsDecorative(t *testing.T) {
	css, err := files.ReadFile("styles.css")
	if err != nil {
		t.Fatal(err)
	}
	if want := `.label th::before {
  content: "– " / "";
}`; !strings.Contains(string(css), want) {
		t.Errorf("want styles.css to hold\n%s\ngot:\n%s", want, css)
	}
}

// TestEveryPageEndsWithTheFooter (forsgren#41, step 1): both pages end with
// the same one footer paragraph: Forsgren linked to its repository, its
// version, what it is and, when numbers were calculated, when (UTC); no
// Install link follows (forsgren#45). Without a calculation time the
// "Calculated at" sentence is left out.
func TestEveryPageEndsWithTheFooter(t *testing.T) {
	const head = `<p><a href="https://github.com/yveshanoulle/forsgren">Forsgren</a> 0.1.3 ` +
		`The five DORA metrics, from GitHub data.`
	withData := acmeProjects(metrics.LeadTime{}, unrecovered, oneFailed, noRework)
	cases := map[string]struct {
		data Data
		want string
	}{
		"with data":    {withData, head + " Calculated at 2026-10-03 12:00 UTC</p>"},
		"without data": {Placeholder("0.1.3"), head + "</p>"},
	}
	for name, c := range cases {
		for _, page := range PageNames() {
			t.Run(name+" "+page, func(t *testing.T) {
				got := rendered(t, page, c.data)
				if !strings.Contains(got, c.want+"\n  </footer>") {
					t.Errorf("want the footer %q to end the footer, got:\n%s", c.want, got)
				}
				wantNoInstallLink(t, got)
			})
		}
	}
}

// wantNoInstallLink fails when the page still has the Install link or the
// forsgren-template repository it pointed to (forsgren#45).
func wantNoInstallLink(t *testing.T, got string) {
	t.Helper()
	for _, gone := range []string{"Install", "forsgren-template"} {
		if strings.Contains(got, gone) {
			t.Errorf("want %q off the page, got:\n%s", gone, got)
		}
	}
}

// TestTablePageOpensWithTheTable (forsgren#41, step 1): the table page has no
// text above its table: no visible heading (the version
// moves below the table) and no Calculated paragraph. Screen readers keep a
// heading, a visually hidden h1.
func TestTablePageOpensWithTheTable(t *testing.T) {
	got := rendered(t, "index.html", acmeProjects(metrics.LeadTime{}, unrecovered, oneFailed, noRework))
	for _, gone := range []string{"<h1>", "counts back from the time in the footer"} {
		if strings.Contains(got, gone) {
			t.Errorf("want %q off the table page, got:\n%s", gone, got)
		}
	}
}

// TestTablePageKeepsAVisuallyHiddenHeading (forsgren#41, step 1): the table
// page's one h1 is visually hidden, so screen readers still get a heading:
// the version and what the page is.
func TestTablePageKeepsAVisuallyHiddenHeading(t *testing.T) {
	got := rendered(t, "index.html", acmeProjects(metrics.LeadTime{}, unrecovered, oneFailed, noRework))
	const want = `<h1 class="visually-hidden">Forsgren 0.1.3: the five DORA metrics</h1>`
	if !strings.Contains(got, want) {
		t.Errorf("want %q on the table page, got:\n%s", want, got)
	}
}

// TestLegendPageSaysWhereEachMetricComesFrom (forsgren#41, step 1): the
// paragraph that left the table page is on the legend page, one source per
// metric.
func TestLegendPageSaysWhereEachMetricComesFrom(t *testing.T) {
	got := rendered(t, "legend.html", Placeholder("0.1.3"))
	for _, want := range []string{
		"Every number counts back from the time in the footer: deployment frequency from the successful deployments",
		"lead time for changes from the commits they shipped",
		"failed deployment recovery time from the failed deployments and the successful ones after them",
		"change fail rate from the failed deployments and the issues labelled failure",
		"deployment rework rate from the successful deployments that came after a failed deployment",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("want %q on the legend page, got:\n%s", want, got)
		}
	}
}

// TestLegendPageCreditsTheDoraQuickCheck (forsgren#47): the legend page says
// where the scores come from, word for word the credit the Quick Check's
// licence asks for, with the Quick Check and the licence each linked.
func TestLegendPageCreditsTheDoraQuickCheck(t *testing.T) {
	const want = `Scores follow the <a href="https://dora.dev/quickcheck/">DORA Quick Check</a> (dora.dev), ` +
		`© Google LLC, <a href="https://creativecommons.org/licenses/by/4.0/">CC BY 4.0</a>.`
	if got := rendered(t, "legend.html", Placeholder("0.1.3")); !strings.Contains(got, want) {
		t.Errorf("want %q on the legend page, got:\n%s", want, got)
	}
}

// TestNoPageShowsASiteNameLine (forsgren#41, step 2): the header carries no
// visible text on either page, the footer names Forsgren.
func TestNoPageShowsASiteNameLine(t *testing.T) {
	for _, name := range PageNames() {
		got := rendered(t, name, acmeProjects(metrics.LeadTime{}, unrecovered, oneFailed, noRework))
		if strings.Contains(got, `class="site-name"`) {
			t.Errorf("%s: want no site-name line, got:\n%s", name, got)
		}
	}
}

// TestFooterShowsTheTimeWithoutRows (forsgren#41, step 3; it reverses
// forsgren#28's "the time with Rows only"): a page with an AsOf and no Rows
// still says when it was calculated.
func TestFooterShowsTheTimeWithoutRows(t *testing.T) {
	data := Placeholder("0.1.3")
	data.AsOf = "2026-10-03 12:00"
	for _, name := range PageNames() {
		if got := rendered(t, name, data); !strings.Contains(got, "Calculated at 2026-10-03 12:00 UTC</p>") {
			t.Errorf("%s: want the calculation time in the footer, got:\n%s", name, got)
		}
	}
}

// TestNoProjectsPageShowsAHowTo (forsgren#41, step 3): where the table would
// be, a page with no projects says that forsgren.config.yml lists them, shows
// a small example with the optional label, and links to the README's
// Configuration section; the one-line message is gone.
func TestNoProjectsPageShowsAHowTo(t *testing.T) {
	data := Placeholder("0.1.3")
	data.NoProjects = true
	got := rendered(t, "index.html", data)
	for _, want := range []string{
		"forsgren.config.yml lists the projects",
		"<pre><code>version: 1\nprojects:\n  - name: Acme Shop\n    repositories:\n",
		"        label: iOS\n",
		`<a href="https://github.com/yveshanoulle/forsgren#configuration">`,
	} {
		if !strings.Contains(got, want) {
			t.Errorf("want %q on the page, got:\n%s", want, got)
		}
	}
	if strings.Contains(got, "No projects configured yet") {
		t.Errorf("want the one-line message replaced by the how-to, got:\n%s", got)
	}
}

// TestNewerComparesVersionsAsNumbers (forsgren#40, step 4): 0.0.10 is newer
// than 0.0.9, a leading "v" is ignored, and what is equal, older or not a
// version is never newer.
func TestNewerComparesVersionsAsNumbers(t *testing.T) {
	cases := []struct {
		current, latest string
		want            bool
	}{
		{"0.0.9", "0.0.10", true},
		{"0.0.10", "0.0.9", false},
		{"0.0.10", "0.1.0", true},
		{"0.9.9", "1.0.0", true},
		{"0.0.9", "v0.0.10", true},
		{"v0.0.9", "0.0.10", true},
		{"0.0.9", "0.0.9", false},
		{"0.0.9", "0.0.8", false},
		{"0.0.9", "", false},
		{"0.0.9", "banana", false},
		{"0.0.9", "0.0.10-rc1", false},
		{"banana", "0.0.10", false},
		{"0.0.9", "0.0.99999999999999999999", false},
	}
	for _, c := range cases {
		if got := newer(c.current, c.latest); got != c.want {
			t.Errorf("newer(%q, %q) = %v, want %v", c.current, c.latest, got, c.want)
		}
	}
}

// TestFooterNamesANewerRelease (forsgren#40, step 4, option 2): when a newer
// forsgren release exists, the version line of the footer says so, on every
// page, with the numbers compared as numbers.
func TestFooterNamesANewerRelease(t *testing.T) {
	data := Placeholder("0.1.3")
	data.Latest = "0.1.4"
	for _, name := range PageNames() {
		if got := rendered(t, name, data); !strings.Contains(got, "0.1.3 · 0.1.4 is available") {
			t.Errorf("%s: want %q in the footer, got:\n%s", name, "0.1.3 · 0.1.4 is available", got)
		}
	}
}

// TestFooterNamesNoReleaseThatIsNotNewer (forsgren#40, step 4): up to date,
// ahead of the latest release, or an unknown or unreadable latest release:
// the footer adds nothing.
func TestFooterNamesNoReleaseThatIsNotNewer(t *testing.T) {
	for _, latest := range []string{"", "0.1.3", "0.1.2", "0.0.10", "banana"} {
		data := Placeholder("0.1.3")
		data.Latest = latest
		for _, name := range PageNames() {
			if got := rendered(t, name, data); strings.Contains(got, " is available") {
				t.Errorf("%s, latest %q: want nothing added to the footer, got:\n%s", name, latest, got)
			}
		}
	}
}

// TestReleaseVersionNamesThePlainVersion (forsgren#40, step 4): a release
// tag's version is its three numbers without the v; anything else is none.
func TestReleaseVersionNamesThePlainVersion(t *testing.T) {
	cases := map[string]string{"v0.0.10": "0.0.10", "0.1.2": "0.1.2", "nightly": "", "v1.2": "", "1.2.3-rc1": ""}
	for in, want := range cases {
		got, ok := ReleaseVersion(in)
		if got != want || ok != (want != "") {
			t.Errorf("ReleaseVersion(%q) = %q, %v, want %q", in, got, ok, want)
		}
	}
}

// TestFooterNamesTheWaitingPullRequest (forsgren#40, step 5, option 1): a
// newer release whose Dependabot pull request is open is named with the
// pull request's number, instead of "is available"; no repository appears.
func TestFooterNamesTheWaitingPullRequest(t *testing.T) {
	data := Placeholder("0.1.3")
	data.Latest = "0.1.4"
	data.WaitingPR = 7
	want := "0.1.3 · 0.1.4 is waiting in pull request #7 (merge it to update)"
	for _, name := range PageNames() {
		got := rendered(t, name, data)
		if !strings.Contains(got, want) || strings.Contains(got, " is available") {
			t.Errorf("%s: want %q and no \"is available\" in the footer, got:\n%s", name, want, got)
		}
	}
}

// TestFooterNamesNoWaitingPullRequestWithoutANewerRelease (forsgren#40, step
// 5): with no pull request, "is available" stays; up to date, a pull request
// number alone adds nothing.
func TestFooterNamesNoWaitingPullRequestWithoutANewerRelease(t *testing.T) {
	data := Placeholder("0.1.3")
	data.Latest = "0.1.4"
	got := rendered(t, "index.html", data)
	if !strings.Contains(got, "0.1.4 is available") || strings.Contains(got, "waiting") {
		t.Errorf("want \"is available\" and no \"waiting\" without a pull request, got:\n%s", got)
	}
	data.Latest, data.WaitingPR = "0.1.3", 7
	got = rendered(t, "index.html", data)
	if strings.Contains(got, "pull request #") || strings.Contains(got, " is available") {
		t.Errorf("want nothing added when up to date, got:\n%s", got)
	}
}

// TestFooterEndsTheReleaseNewsBeforeWhatForsgrenIs (forsgren#40, review of
// step 7): the news of a newer release, available or waiting in a pull
// request, is a sentence of its own; it never runs on into "The five DORA
// metrics" ("0.1.4 is available The five ..."), on every page.
func TestFooterEndsTheReleaseNewsBeforeWhatForsgrenIs(t *testing.T) {
	for waiting, want := range map[int]string{
		0: "0.1.3 · 0.1.4 is available. The five DORA metrics",
		7: "0.1.3 · 0.1.4 is waiting in pull request #7 (merge it to update). The five DORA metrics",
	} {
		data := Placeholder("0.1.3")
		data.Latest, data.WaitingPR = "0.1.4", waiting
		for _, name := range PageNames() {
			if got := rendered(t, name, data); !strings.Contains(got, want) {
				t.Errorf("%s: want %q in the footer, got:\n%s", name, want, got)
			}
		}
	}
}

// TestTableCaptionIsDORAMetrics (forsgren#45, step 2): the table's caption
// reads exactly "DORA metrics", and the region around the table is still
// labelled by it, so the id its aria-labelledby names exists.
func TestTableCaptionIsDORAMetrics(t *testing.T) {
	got := rendered(t, "index.html", acmeProjects(metrics.LeadTime{}, unrecovered, oneFailed, noRework))
	const want = `<caption id="metrics-caption">DORA metrics</caption>`
	if !strings.Contains(got, want) {
		t.Errorf("want %q on the table page, got:\n%s", want, got)
	}
	if !strings.Contains(got, `aria-labelledby="metrics-caption"`) {
		t.Errorf("want the table's region labelled by metrics-caption, got:\n%s", got)
	}
}

// TestCaptionFontIsLargerThanBody (forsgren#45, step 2): the caption rule in
// styles.css sets a font-size in rem above 1, the body's size (the body sets
// none, so it is 1rem). Parsed, not matched as one exact string, so the size
// can be tuned without touching the test.
func TestCaptionFontIsLargerThanBody(t *testing.T) {
	css, err := files.ReadFile("styles.css")
	if err != nil {
		t.Fatal(err)
	}
	rule := regexp.MustCompile(`(?s)\bcaption\s*\{([^}]*)\}`).FindStringSubmatch(string(css))
	if rule == nil {
		t.Fatalf("want a caption rule in styles.css, got:\n%s", css)
	}
	size := regexp.MustCompile(`font-size:\s*([0-9.]+)rem`).FindStringSubmatch(rule[1])
	if size == nil {
		t.Fatalf("want the caption rule to set a font-size in rem, got:\n%s", rule[1])
	}
	if n, err := strconv.ParseFloat(size[1], 64); err != nil || n <= 1 {
		t.Errorf("want the caption font-size above the body's 1rem, got %s", size[1])
	}
}
