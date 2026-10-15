package page

import (
	"bytes"
	"flag"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// -update rewrites the golden files from the current output. Use it only
// after reading the diff the failing golden test printed.
var update = flag.Bool("update", false, "rewrite testdata/*.golden.html")

// calculated is the placeholder page data, calculated at 2026-10-03 12:00
// UTC, that the golden pages start from.
func calculated() Data {
	data := Placeholder("1.7.1")
	data.AsOf = "2026-10-03 12:00"
	return data
}

func TestPlaceholderMatchesGolden(t *testing.T) {
	checkGolden(t, "testdata/index.golden.html", calculated())
}

// TestNoProjectsPageMatchesGolden (forsgren#12): the page of an installation
// whose config lists no projects says so, besides its version.
func TestNoProjectsPageMatchesGolden(t *testing.T) {
	data := calculated()
	data.NoProjects = true
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
	data := calculated()
	latest := time.Date(2026, 10, 1, 9, 30, 0, 0, time.UTC)
	frequency := metrics.Frequency{
		Project: "Acme Shop", Last7: 3, InWindow: 12, Last180: 12, WeekendInWindow: 3, Latest: latest,
		Band: metrics.DailyToWeekly,
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

// acmeTable is acmeProjects with Acme Shop's usual numbers: no lead time,
// unrecovered, oneFailed and noRework.
func acmeTable() Data {
	return acmeProjects(metrics.LeadTime{}, unrecovered, oneFailed, noRework)
}

// TestFrequencyPageMatchesGolden (forsgren#12, step 7; forsgren#38): with
// projects the page is one table, a row per project in the given order,
// each cell short, a link to the legend under it; a project with no
// deployment says so across its row, and one with deployments but no commit
// in the window says "No lead time yet".
func TestFrequencyPageMatchesGolden(t *testing.T) {
	checkGolden(t, "testdata/index.frequency.golden.html", acmeTable())
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
	data := calculated()
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
	often := metrics.Frequency{InWindow: 16, Last180: 40, WeekendInWindow: 5, Latest: latest, Band: metrics.DailyToWeekly}
	apiOften := metrics.Frequency{
		InWindow: 12, Last180: 30, WeekendInWindow: 3, Latest: latest, Band: metrics.DailyToWeekly,
	}
	rarely := metrics.Frequency{InWindow: 2, Last180: 5, Latest: latest, Band: metrics.WeeklyToMonthly}
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
		row(label, "API", apiOften, fast, recovered, cf(7, 1, metrics.TwentyPercent)),
		{Level: label, Name: "IOS"},
		row(label, "Website", rarely, metrics.LeadTime{}, metrics.Recovery{Unrecovered: 1}, cf(3, 1, metrics.FortyPercent)),
		row(metrics.ProjectRow, "Acme Tools", metrics.Frequency{InWindow: 3, Latest: latest, Band: metrics.WeeklyToMonthly},
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
	data := calculated()
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
	err := Render(&bytes.Buffer{}, "missing.html", Placeholder("1.7.1"))
	if err == nil || !strings.Contains(err.Error(), "missing.html") {
		t.Errorf("want an error naming missing.html, got %v", err)
	}
}

// TestLegendPageMatchesGolden (forsgren#39, step 1): the band explanations
// are the page legend.html; the table page holds none of them.
func TestLegendPageMatchesGolden(t *testing.T) {
	data := calculated()
	data.WorkingHours = 8
	checkPageGolden(t, "legend.html", "testdata/legend.golden.html", data)
}

// TestSettingsPageMatchesGolden (forsgren#84, step 1): settings.html lists
// the settings of an empty config, every one a default.
func TestSettingsPageMatchesGolden(t *testing.T) {
	data := calculated()
	data.Settings = config.Config{}.Settings()
	checkPageGolden(t, "settings.html", "testdata/settings.golden.html", data)
}

// on2026 is midnight UTC on day d of month m of 2026, the Date of a row of the
// days or issues page.
func on2026(m time.Month, d int) time.Time { return time.Date(2026, m, d, 0, 0, 0, 0, time.UTC) }

// october is on2026 in October.
func october(d int) time.Time { return on2026(time.October, d) }

// TestDaysPageShowsTheLastThirtyDays (forsgren#123, step 1): the days page
// is back to 0.6.3: it tabulates Data.IssueDays under the header "Date", with
// no caption (forsgren#128) and no note, and
// shows no week or month row even when Data.IssueRows holds some.
func TestDaysPageShowsTheLastThirtyDays(t *testing.T) {
	data := calculated()
	data.IssueDays = []metrics.IssueDay{
		{Date: october(13), New: 2, Open: 4, Active: true},
		{Date: october(12), Completed: 1, Open: 3, Active: true},
	}
	data.IssueRows = []metrics.IssueRow{
		{Kind: metrics.KindWeek, IssueDay: metrics.IssueDay{Date: october(5), New: 1, Open: 1, Active: true}},
		{Kind: metrics.KindMonth, IssueDay: metrics.IssueDay{
			Date: on2026(time.September, 1), New: 1, Open: 1, Active: true,
		}},
	}
	got := rendered(t, "days.html", data)
	wantAll(t, "days.html", got, "2026-10-13", "2026-10-12", `<th scope="col">Date</th>`)
	wantNone(t, "days.html", got, "Week 41", "September 2026", `<th scope="col">Period</th>`,
		"a week that spans two months")
}

// TestIssueTableRowsLabelsDayWeekAndMonthRows (forsgren#89, step 13;
// forsgren#123): the rows of Data.IssueRows are labelled by their kind: a day
// by its date, a week by the ISO number of its Monday (5 October 2026 is in
// week 41), a month by its name and year. The issues page shows them.
func TestIssueTableRowsLabelsDayWeekAndMonthRows(t *testing.T) {
	row := func(kind string, date time.Time) metrics.IssueRow {
		return metrics.IssueRow{Kind: kind, IssueDay: metrics.IssueDay{Date: date, New: 1, Open: 1, Active: true}}
	}
	data := calculated()
	data.IssueRows = []metrics.IssueRow{
		row(metrics.KindDay, october(13)),
		row(metrics.KindWeek, october(5)),
		row(metrics.KindMonth, on2026(time.September, 1)),
	}
	var got []string
	for _, r := range data.IssueTableRows() {
		got = append(got, r.Label)
	}
	if want := []string{"2026-10-13", "Week 41", "September 2026"}; !slices.Equal(got, want) {
		t.Errorf("want the labels %q, got %q", want, got)
	}
}

// TestDaysPageSkipsInactiveDays (forsgren#108, step 5): a day that is not
// Active (nothing new, closed or reopened) has no row on the days page, the
// days around it do. The calculation keeps the day (rule 3); only the page hides it.
func TestDaysPageSkipsInactiveDays(t *testing.T) {
	data := calculated()
	data.IssueDays = []metrics.IssueDay{
		{Date: october(3), New: 1, Open: 5, Active: true},
		{Date: october(2), Open: 5},
		{Date: october(1), Completed: 1, Open: 5, Active: true},
	}
	got := rendered(t, "days.html", data)
	wantAll(t, "days.html", got, "2026-10-03", "2026-10-01")
	wantNone(t, "days.html", got, "2026-10-02")
}

// TestDaysPageWithNoActiveDayShowsAMessage (forsgren#108, step 7, rule 4):
// when no day of the window is Active, the days page says so in one line
// and has no table, not even its head.
func TestDaysPageWithNoActiveDayShowsAMessage(t *testing.T) {
	data := calculated()
	data.IssueDays = []metrics.IssueDay{{Date: october(13), Open: 5}, {Date: october(12), Open: 5}}
	got := rendered(t, "days.html", data)
	wantAll(t, "days.html", got, "<p>No issues were opened, closed or reopened in the last 30 days.</p>")
	wantNone(t, "days.html", got, "<table>", "2026-10-13")
}

// TestDaysPageMenuIgnoresTheConfiguredView (forsgren#76, decision #102):
// the config's view: decides which view the root page shows, not what the
// days page marks. Whatever Data.View is, the days page's menu links all
// three views and only Daily is current.
func TestDaysPageMenuIgnoresTheConfiguredView(t *testing.T) {
	menu := wantMenu("", "Daily", "page")
	for _, view := range []string{viewStandard, viewNumbers, viewScoring} {
		t.Run(view, func(t *testing.T) {
			data := calculated()
			data.View = view
			got := rendered(t, "days.html", data)
			if !strings.Contains(got, menu) || strings.Count(got, "aria-current") != 1 {
				t.Errorf("want the menu %q with the only aria-current, got:\n%s", menu, got)
			}
		})
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

// wantOnEveryPage fails for each page of PageNames, rendered with data, that
// lacks one of texts.
func wantOnEveryPage(t *testing.T, data Data, texts ...string) {
	t.Helper()
	for _, name := range PageNames() {
		wantAll(t, name, rendered(t, name, data), texts...)
	}
}

// wantOnNoPage fails for each page of PageNames, rendered with data, that
// holds one of texts.
func wantOnNoPage(t *testing.T, data Data, texts ...string) {
	t.Helper()
	for _, name := range PageNames() {
		wantNone(t, name, rendered(t, name, data), texts...)
	}
}

// released is the placeholder page data with latest as forsgren's latest
// release and waitingPR as the pull request that bumps to it, 0 for none.
func released(latest string, waitingPR int) Data {
	data := Placeholder("1.7.1")
	data.Latest, data.WaitingPR = latest, waitingPR
	return data
}

// legendItem is one item of the legend page's band lists.
var legendItem = regexp.MustCompile(`<li>[^<]*</li>`)

// TestTablePageLinksToTheLegend (forsgren#39, step 1): the table page
// carries a link to legend.html and none of the band explanations: no item
// of the legend page's band lists (forsgren#39, step 4).
func TestTablePageLinksToTheLegend(t *testing.T) {
	data := acmeTable()
	got := rendered(t, "index.html", data)
	if !strings.Contains(got, `<a href="legend.html">Legend</a>`) {
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
	wantOnEveryPage(t, acmeTable(), " Metrics from GitHub data.")
}

// TestWriteSiteWritesNinePagesAndStyles (forsgren#55, #46, #47, #84, #76, #123, #128): the
// root page, the legend, the settings page, the days page and the issues page, and each
// view's page, standard, numbers and scoring, in its own folder, and the numbers and scoring page.
func TestWriteSiteWritesNinePagesAndStyles(t *testing.T) {
	dir := t.TempDir()
	n, err := WriteSite(dir, Placeholder("1.7.1"))
	if err != nil {
		t.Fatalf("WriteSite: %v", err)
	}
	if n != 9 {
		t.Errorf("want 9 pages written, got %d", n)
	}
	for _, name := range []string{
		"index.html", "legend.html", "settings.html", "days.html", "issues.html", "standard/index.html",
		"numbers/index.html", "scoring/index.html", "numbers-scoring/index.html", "styles.css",
	} {
		if _, err := os.Stat(filepath.Join(dir, name)); err != nil {
			t.Errorf("want %s in the site: %v", name, err)
		}
	}
	if _, err := os.Stat(filepath.Join(dir, "months.html")); err == nil {
		t.Error("want no months.html in the site: it is issues.html now (forsgren#128)")
	}
}

func TestWriteSiteFailsWhenDirIsAFile(t *testing.T) {
	file := filepath.Join(t.TempDir(), "not-a-dir")
	if err := os.WriteFile(file, []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	if n, err := WriteSite(file, Placeholder("1.7.1")); err == nil {
		t.Errorf("want an error when the output is a regular file, got %d pages", n)
	}
}

// TestEveryPageEndsWithTheFooter (forsgren#41, step 1): every page's footer
// opens with the same one paragraph: Forsgren linked to forsgren.be (forsgren#162), its
// version, what it is and, when numbers were calculated, when (UTC); no
// Install link anywhere (forsgren#45). Without a calculation time the
// "Calculated at" sentence is left out. Settings and Legend follow the
// paragraph on every page (forsgren#128).
func TestEveryPageEndsWithTheFooter(t *testing.T) {
	const head = `<p><a href="https://forsgren.be/">Forsgren</a> 1.7.1 ` +
		`Metrics from GitHub data.`
	cases := map[string]struct {
		data Data
		want string
	}{
		"with data":    {acmeTable(), head + " Calculated at 2026-10-03 12:00 UTC</p>"},
		"without data": {Placeholder("1.7.1"), head + "</p>"},
	}
	for name, c := range cases {
		for _, page := range PageNames() {
			t.Run(name+" "+page, func(t *testing.T) {
				got := rendered(t, page, c.data)
				if !strings.Contains(got, "  <footer>\n    "+c.want+"\n") {
					t.Errorf("want the footer %q to open the footer, got:\n%s", c.want, got)
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
	wantNone(t, "the page", got, "Install", "forsgren-template")
}

// TestTablePageOpensWithTheTable (forsgren#41, step 1; forsgren#135): the table
// page has no Calculated paragraph above its table, only the heading (the
// version is in the footer).
func TestTablePageOpensWithTheTable(t *testing.T) {
	wantNone(t, "index.html", rendered(t, "index.html", acmeTable()), "counts back from the time in the footer")
}

// TestLegendPageSaysWhereEachMetricComesFrom (forsgren#41, step 1): the
// paragraph that left the table page is on the legend page, one source per
// metric.
func TestLegendPageSaysWhereEachMetricComesFrom(t *testing.T) {
	wantAll(t, "legend.html", rendered(t, "legend.html", Placeholder("1.7.1")),
		"Every number counts back from the time in the footer: deployment frequency from the successful deployments",
		"lead time for changes from the commits they shipped",
		"failed deployment recovery time from the failed deployments and the successful ones after them",
		"change fail rate from the failed deployments and the issues labelled failure",
		"deployment rework rate from the successful deployments that came after a failed deployment",
	)
}

// TestLegendPageCreditsTheDoraQuickCheck (forsgren#47): the legend page says
// where the scores come from, word for word the credit the Quick Check's
// licence asks for, with the Quick Check and the licence each linked.
func TestLegendPageCreditsTheDoraQuickCheck(t *testing.T) {
	const want = `Scores follow the <a href="https://dora.dev/quickcheck/">DORA Quick Check</a> (dora.dev), ` +
		`© Google LLC, <a href="https://creativecommons.org/licenses/by/4.0/">CC BY 4.0</a>.`
	wantAll(t, "legend.html", rendered(t, "legend.html", Placeholder("1.7.1")), want)
}

// TestNoPageShowsASiteNameLine (forsgren#41, step 2): the header carries no
// visible text on either page, the footer names Forsgren.
func TestNoPageShowsASiteNameLine(t *testing.T) {
	wantOnNoPage(t, acmeTable(), `class="site-name"`)
}

// TestFooterShowsTheTimeWithoutRows (forsgren#41, step 3; it reverses
// forsgren#28's "the time with Rows only"): a page with an AsOf and no Rows
// still says when it was calculated.
func TestFooterShowsTheTimeWithoutRows(t *testing.T) {
	wantOnEveryPage(t, calculated(), "Calculated at 2026-10-03 12:00 UTC</p>")
}

// TestNoProjectsPageShowsAHowTo (forsgren#41, step 3): where the table would
// be, a page with no projects says that forsgren.config.yml lists them, shows
// a small example with the optional label, and links straight to
// docs/configuration.md; the one-line message is gone.
func TestNoProjectsPageShowsAHowTo(t *testing.T) {
	data := Placeholder("1.7.1")
	data.NoProjects = true
	got := rendered(t, "index.html", data)
	wantAll(t, "index.html", got,
		"forsgren.config.yml lists the projects",
		"<pre><code>version: 1\nprojects:\n  - name: Acme Shop\n    repositories:\n",
		"        label: iOS\n",
		`<a href="https://github.com/yveshanoulle/forsgren/blob/main/docs/configuration.md">`,
	)
	wantNone(t, "index.html", got, "No projects configured yet")
}

// TestFooterNamesANewerRelease (forsgren#40, step 4, option 2): when a newer
// forsgren release exists, the version line of the footer says so, on every
// page, with the numbers compared as numbers.
func TestFooterNamesANewerRelease(t *testing.T) {
	wantOnEveryPage(t, released("1.7.2", 0), "1.7.1 · 1.7.2 is available")
}

// TestFooterNamesNoReleaseThatIsNotNewer (forsgren#40, step 4): up to date,
// ahead of the latest release, or an unknown or unreadable latest release:
// the footer adds nothing.
func TestFooterNamesNoReleaseThatIsNotNewer(t *testing.T) {
	for _, latest := range []string{"", "1.7.1", "0.1.2", "0.0.10", "banana"} {
		t.Run("latest "+latest, func(t *testing.T) {
			wantOnNoPage(t, released(latest, 0), " is available")
		})
	}
}

// TestFooterNamesTheWaitingPullRequest (forsgren#40, step 5, option 1): a
// newer release whose Dependabot pull request is open is named with the
// pull request's number, instead of "is available"; no repository appears.
func TestFooterNamesTheWaitingPullRequest(t *testing.T) {
	data := released("1.7.2", 7)
	wantOnEveryPage(t, data, "1.7.1 · 1.7.2 is waiting in pull request #7 (merge it to update)")
	wantOnNoPage(t, data, " is available")
}

// TestFooterNamesNoWaitingPullRequestWithoutANewerRelease (forsgren#40, step
// 5): with no pull request, "is available" stays; up to date, a pull request
// number alone adds nothing.
func TestFooterNamesNoWaitingPullRequestWithoutANewerRelease(t *testing.T) {
	available := rendered(t, "index.html", released("1.7.2", 0))
	wantAll(t, "without a pull request", available, "1.7.2 is available")
	wantNone(t, "without a pull request", available, "waiting")
	wantNone(t, "up to date", rendered(t, "index.html", released("1.7.1", 7)), "pull request #", " is available")
}

// TestFooterEndsTheReleaseNewsBeforeWhatForsgrenIs (forsgren#40, review of
// step 7): the news of a newer release, available or waiting in a pull
// request, is a sentence of its own; it never runs on into "The five DORA
// metrics" ("1.7.2 is available The five ..."), on every page.
func TestFooterEndsTheReleaseNewsBeforeWhatForsgrenIs(t *testing.T) {
	for waiting, want := range map[int]string{
		0: "1.7.1 · 1.7.2 is available. Metrics from GitHub data",
		7: "1.7.1 · 1.7.2 is waiting in pull request #7 (merge it to update). Metrics from GitHub data",
	} {
		wantOnEveryPage(t, released("1.7.2", waiting), want)
	}
}

// TestLegendStatesTheWorkingDay (forsgren#71): the legend says how a working
// day is configured, and its on-demand and hourly-to-daily numbers follow:
// a set 12 gives more than 12 x 30 = 360, so 361 and more; unset says it is
// the default 8.
func TestLegendStatesTheWorkingDay(t *testing.T) {
	cases := []struct {
		name  string
		hours int
		set   bool
		want  []string
	}{
		{"set", 12, true, []string{"A working day is configured as 12 hours.", "361 and more", "30 to 360"}},
		{"unset", 8, false, []string{
			"A working day is configured as 8 hours (the default; working_hours is not set in forsgren.config.yml).",
			"241 and more", "30 to 240",
		}},
	}
	for _, c := range cases {
		data := Placeholder("1.7.1")
		data.WorkingHours, data.WorkingHoursSet = c.hours, c.set
		wantAll(t, c.name, rendered(t, "legend.html", data), c.want...)
	}
}

// withTwoSettings is the placeholder with one setting the config sets, view:
// numbers, and one it leaves at its default, history_days: 365.
func withTwoSettings() Data {
	data := Placeholder("1.7.1")
	data.Settings = []config.Setting{{Key: "view", Value: "numbers", Default: "standard", Set: true},
		{Key: "history_days", Value: "365", Default: "365"}}
	return data
}

// TestSettingsPageIsATableOfParameterValuePossibleValuesAndDefault
// (forsgren#74, #84, #141): the settings page tabulates each setting under
// Parameter, Current value, Possible values and Default; Default is the key's
// default value (forsgren#169).
func TestSettingsPageIsATableOfParameterValuePossibleValuesAndDefault(t *testing.T) {
	data := withTwoSettings()
	wantAll(t, "settings.html", rendered(t, "settings.html", data),
		`<th scope="col">Parameter</th>
            <th scope="col">Current value</th>
            <th scope="col">Possible values</th>
            <th scope="col">Default</th>`,
		`<th scope="row">view</th>
            <td>numbers</td>
            <td>standard, numbers, scoring</td>
            <td>standard</td>`,
		`<th scope="row">history_days</th>
            <td>365 (not set)</td>
            <td>30 to 1825</td>
            <td>365</td>`,
	)
}

// TestSettingsPageHasNoNoteOnTheAutoUpdateLevel (forsgren#157): the possible
// values of auto_update_level are exactly patch, minor and major; the level is
// optional, so the cell carries no rule.
func TestSettingsPageHasNoNoteOnTheAutoUpdateLevel(t *testing.T) {
	data := calculated()
	data.Settings = config.Config{}.Settings()
	html := rendered(t, "settings.html", data)
	wantAll(t, "settings.html", html, "<td>patch, minor, major</td>")
	wantNone(t, "settings.html", html, "required when auto_update")
}

// TestLegendHasNoSettings (forsgren#84, step 2): the settings moved to their
// own page; the legend has no Settings section and no setting.
func TestLegendHasNoSettings(t *testing.T) {
	data := withTwoSettings()
	wantNone(t, "legend.html", rendered(t, "legend.html", data),
		"<h2>Settings</h2>",
		"<li>view: numbers</li>",
		"<li>history_days: 365",
	)
}

// defaultNote is the legend's explanation of the settings page's Default
// column and of "(not set)" after a Current value (forsgren#141, #169).
const defaultNote = "The Default column of the settings page is the value used when forsgren.config.yml does not " +
	"set the key. A current value followed by (not set) means the file does not set the key, so the default applies; " +
	"a current value without it is set in the file, even to the default's value."

// TestLegendExplainsTheDefaultColumnAndNotSet (forsgren#141, #169): the legend
// ends with a section on the settings page that says what the Default column
// holds and what (not set) after a Current value means, and no longer speaks
// of True and False.
func TestLegendExplainsTheDefaultColumnAndNotSet(t *testing.T) {
	html := rendered(t, "legend.html", calculated())
	wantAll(t, "legend.html", html, "<h2>Settings page</h2>\n    <p>"+defaultNote+"</p>\n")
	wantNone(t, "legend.html", html, "True when forsgren.config.yml")
}

// autoUpdateLevelNote is the legend's explanation of auto_update_level and of
// a patch, a minor and a major release (forsgren#156).
const autoUpdateLevelNote = "auto_update_level is the largest step of a forsgren update that merges itself; a " +
	"larger one is left for you. By what a release asks of an installation, a patch release is fixes only, with " +
	"nothing new for the installation to do or see; a minor release is new behaviour, or anything that asks the " +
	"installation for something (a permission, a secret, a file, a config key); a major release is one where an " +
	"installation that does nothing would stop working."

// TestLegendExplainsAutoUpdateLevels (forsgren#156): the legend's settings
// section says what a patch, a minor and a major release are, and what each
// auto_update_level merges by itself; the levels come from the config's
// constants, so a renamed level fails here.
func TestLegendExplainsAutoUpdateLevels(t *testing.T) {
	wantAll(t, "legend.html", rendered(t, "legend.html", calculated()),
		"<p>"+autoUpdateLevelNote+"</p>",
		"<li>"+config.LevelPatch+": merges "+config.LevelPatch+" updates only</li>",
		"<li>"+config.LevelMinor+": merges "+config.LevelMinor+" and "+config.LevelPatch+" updates</li>",
		"<li>"+config.LevelMajor+": merges "+config.LevelMajor+", "+config.LevelMinor+" and "+config.LevelPatch+
			" updates. It does not mean a major release is safe: nothing checks a release against this "+
			"installation's own data.</li>")
}

// TestDaysPageMatchesGolden (forsgren#128, step 2): the page of the days is
// days.html, what issues.html showed before: a table of the last 30 days, newest
// first, titled Daily, with the menu that ends issues, Daily.
func TestDaysPageMatchesGolden(t *testing.T) {
	data := calculated()
	data.IssueDays = []metrics.IssueDay{
		{Date: october(2), New: 3, Completed: 1, NotPlanned: 2, Duplicate: 1, Open: 7, Total: 10, Active: true},
		{Date: october(1), New: 0, Completed: 0, Open: 5, Total: 8, Active: true},
		{
			Date: on2026(time.September, 30),
			New:  2, Completed: 4, Duplicate: 3, Other: 5, Open: 6, Active: true,
		},
	}
	checkPageGolden(t, "days.html", "testdata/days.golden.html", data)
}

// TestDaysPageWithoutDaysMatchesGolden (forsgren#128, step 3): the days page of a
// site with no issue events yet has no Active day, so it shows the no-activity
// message and no table.
func TestDaysPageWithoutDaysMatchesGolden(t *testing.T) {
	checkPageGolden(t, "days.html", "testdata/days.placeholder.golden.html", calculated())
}
