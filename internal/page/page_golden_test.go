package page

import (
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/metrics"
)

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
	checkGolden(t, "testdata/index.changefail.golden.html", acmeProjects(metrics.LeadTime{},
		metrics.Recovery{Unrecovered: 3}, changeFail,
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
		heading := r.Heading
		if r.Total {
			heading += " (total)"
		}
		got = append(got, r.Project+"|"+heading)
	}
	want := []string{
		"|Acme Shop (total)", "Acme Shop|ADMIN", "Acme Shop|API", "Acme Shop|IOS", "Acme Shop|Website",
		"|Acme Tools", "|Acme Docs",
	}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Errorf("want %v, got %v", want, got)
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
	data.Settings = append(config.Config{}.Settings(), config.Config{}.RepositorySettings()...)
	checkPageGolden(t, "settings.html", "testdata/settings.golden.html", data)
}
