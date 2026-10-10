package page

import (
	"bytes"
	"flag"
	"os"
	"path/filepath"
	"regexp"
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
	data := Placeholder("0.4.2")
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
	err := Render(&bytes.Buffer{}, "missing.html", Placeholder("0.4.2"))
	if err == nil || !strings.Contains(err.Error(), "missing.html") {
		t.Errorf("want an error naming missing.html, got %v", err)
	}
}

// TestLegendPageMatchesGolden (forsgren#39, step 1): the band explanations
// are the page legend.html, with a link back to the table; the table page
// holds none of them.
func TestLegendPageMatchesGolden(t *testing.T) {
	data := calculated()
	data.WorkingHours = 8
	checkPageGolden(t, "legend.html", "testdata/legend.golden.html", data)
}

// TestSettingsPageMatchesGolden (forsgren#84, step 1): settings.html lists
// the settings of an empty config, every one a default, with a link back to
// the table.
func TestSettingsPageMatchesGolden(t *testing.T) {
	data := calculated()
	data.Settings = config.Config{}.Settings()
	checkPageGolden(t, "settings.html", "testdata/settings.golden.html", data)
}

// TestLegendPageTitleNamesIt (forsgren#39, step 4): the legend page's title
// is its link's text, then the site's title; its header shows no site-name line (forsgren#41).
func TestLegendPageTitleNamesIt(t *testing.T) {
	got := rendered(t, "legend.html", acmeTable())
	wantAll(t, "legend.html", got, "<title>What the bands mean · forsgren</title>")
	wantNone(t, "legend.html", got, `class="site-name"`)
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
	data := Placeholder("0.4.2")
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
	wantOnEveryPage(t, acmeTable(), " Metrics from GitHub data.")
}

// TestWriteSiteWritesSixPagesAndStyles (forsgren#46, #47, #84): the root
// page, the legend and the settings page, and each view's page, standard,
// numbers and scoring, in its own folder.
func TestWriteSiteWritesSixPagesAndStyles(t *testing.T) {
	dir := t.TempDir()
	n, err := WriteSite(dir, Placeholder("0.4.2"))
	if err != nil {
		t.Fatalf("WriteSite: %v", err)
	}
	if n != 6 {
		t.Errorf("want 6 pages written, got %d", n)
	}
	for _, name := range []string{
		"index.html", "legend.html", "settings.html", "standard/index.html", "numbers/index.html",
		"scoring/index.html", "styles.css",
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
	if n, err := WriteSite(file, Placeholder("0.4.2")); err == nil {
		t.Errorf("want an error when the output is a regular file, got %d pages", n)
	}
}

// TestEveryPageEndsWithTheFooter (forsgren#41, step 1): every page's footer
// opens with the same one paragraph: Forsgren linked to its repository, its
// version, what it is and, when numbers were calculated, when (UTC); no
// Install link anywhere (forsgren#45). Without a calculation time the
// "Calculated at" sentence is left out. The page's own links follow the
// paragraph (the footerlinks block, forsgren#83), each page's pinned by its
// golden.
func TestEveryPageEndsWithTheFooter(t *testing.T) {
	const head = `<p><a href="https://github.com/yveshanoulle/forsgren">Forsgren</a> 0.4.2 ` +
		`Metrics from GitHub data.`
	cases := map[string]struct {
		data Data
		want string
	}{
		"with data":    {acmeTable(), head + " Calculated at 2026-10-03 12:00 UTC</p>"},
		"without data": {Placeholder("0.4.2"), head + "</p>"},
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

// TestTablePageOpensWithTheTable (forsgren#41, step 1): the table page has no
// text above its table: no visible heading (the version
// moves below the table) and no Calculated paragraph. Screen readers keep a
// heading, a visually hidden h1.
func TestTablePageOpensWithTheTable(t *testing.T) {
	wantNone(t, "index.html", rendered(t, "index.html", acmeTable()), "<h1>", "counts back from the time in the footer")
}

// TestTablePageKeepsAVisuallyHiddenHeading (forsgren#41, step 1): the table
// page's one h1 is visually hidden, so screen readers still get a heading:
// the version and what the page is.
func TestTablePageKeepsAVisuallyHiddenHeading(t *testing.T) {
	wantAll(t, "index.html", rendered(t, "index.html", acmeTable()),
		`<h1 class="visually-hidden">Forsgren 0.4.2: the five DORA metrics</h1>`)
}

// TestLegendPageSaysWhereEachMetricComesFrom (forsgren#41, step 1): the
// paragraph that left the table page is on the legend page, one source per
// metric.
func TestLegendPageSaysWhereEachMetricComesFrom(t *testing.T) {
	wantAll(t, "legend.html", rendered(t, "legend.html", Placeholder("0.4.2")),
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
	wantAll(t, "legend.html", rendered(t, "legend.html", Placeholder("0.4.2")), want)
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
// a small example with the optional label, and links to the README's
// Configuration section; the one-line message is gone.
func TestNoProjectsPageShowsAHowTo(t *testing.T) {
	data := Placeholder("0.4.2")
	data.NoProjects = true
	got := rendered(t, "index.html", data)
	wantAll(t, "index.html", got,
		"forsgren.config.yml lists the projects",
		"<pre><code>version: 1\nprojects:\n  - name: Acme Shop\n    repositories:\n",
		"        label: iOS\n",
		`<a href="https://github.com/yveshanoulle/forsgren#configuration">`,
	)
	wantNone(t, "index.html", got, "No projects configured yet")
}

// TestFooterNamesANewerRelease (forsgren#40, step 4, option 2): when a newer
// forsgren release exists, the version line of the footer says so, on every
// page, with the numbers compared as numbers.
func TestFooterNamesANewerRelease(t *testing.T) {
	wantOnEveryPage(t, released("0.4.3", 0), "0.4.2 · 0.4.3 is available")
}

// TestFooterNamesNoReleaseThatIsNotNewer (forsgren#40, step 4): up to date,
// ahead of the latest release, or an unknown or unreadable latest release:
// the footer adds nothing.
func TestFooterNamesNoReleaseThatIsNotNewer(t *testing.T) {
	for _, latest := range []string{"", "0.4.2", "0.1.2", "0.0.10", "banana"} {
		t.Run("latest "+latest, func(t *testing.T) {
			wantOnNoPage(t, released(latest, 0), " is available")
		})
	}
}

// TestFooterNamesTheWaitingPullRequest (forsgren#40, step 5, option 1): a
// newer release whose Dependabot pull request is open is named with the
// pull request's number, instead of "is available"; no repository appears.
func TestFooterNamesTheWaitingPullRequest(t *testing.T) {
	data := released("0.4.3", 7)
	wantOnEveryPage(t, data, "0.4.2 · 0.4.3 is waiting in pull request #7 (merge it to update)")
	wantOnNoPage(t, data, " is available")
}

// TestFooterNamesNoWaitingPullRequestWithoutANewerRelease (forsgren#40, step
// 5): with no pull request, "is available" stays; up to date, a pull request
// number alone adds nothing.
func TestFooterNamesNoWaitingPullRequestWithoutANewerRelease(t *testing.T) {
	available := rendered(t, "index.html", released("0.4.3", 0))
	wantAll(t, "without a pull request", available, "0.4.3 is available")
	wantNone(t, "without a pull request", available, "waiting")
	wantNone(t, "up to date", rendered(t, "index.html", released("0.4.2", 7)), "pull request #", " is available")
}

// TestFooterEndsTheReleaseNewsBeforeWhatForsgrenIs (forsgren#40, review of
// step 7): the news of a newer release, available or waiting in a pull
// request, is a sentence of its own; it never runs on into "The five DORA
// metrics" ("0.4.3 is available The five ..."), on every page.
func TestFooterEndsTheReleaseNewsBeforeWhatForsgrenIs(t *testing.T) {
	for waiting, want := range map[int]string{
		0: "0.4.2 · 0.4.3 is available. Metrics from GitHub data",
		7: "0.4.2 · 0.4.3 is waiting in pull request #7 (merge it to update). Metrics from GitHub data",
	} {
		wantOnEveryPage(t, released("0.4.3", waiting), want)
	}
}

// TestTableCaptionIsDORAMetrics (forsgren#45, step 2): the table's caption
// reads exactly "DORA metrics", and the region around the table is still
// labelled by it, so the id its aria-labelledby names exists.
func TestTableCaptionIsDORAMetrics(t *testing.T) {
	wantAll(t, "index.html", rendered(t, "index.html", acmeTable()),
		`<caption id="metrics-caption">DORA metrics</caption>`, `aria-labelledby="metrics-caption"`)
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
		data := Placeholder("0.4.2")
		data.WorkingHours, data.WorkingHoursSet = c.hours, c.set
		wantAll(t, c.name, rendered(t, "legend.html", data), c.want...)
	}
}

// withTwoSettings is the placeholder with one setting the config sets, view:
// numbers, and one it leaves at its default, history_days: 365.
func withTwoSettings() Data {
	data := Placeholder("0.4.2")
	data.Settings = []config.Setting{{Key: "view", Value: "numbers", Set: true}, {Key: "history_days", Value: "365"}}
	return data
}

// TestSettingsPageListsTheSettings (forsgren#74, #84): the settings page lists
// each setting as key: value, and the unset ones marked as defaults.
func TestSettingsPageListsTheSettings(t *testing.T) {
	data := withTwoSettings()
	wantAll(t, "settings.html", rendered(t, "settings.html", data),
		"<li>view: numbers</li>",
		"<li>history_days: 365 (default, not set in forsgren.config.yml)</li>",
	)
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
