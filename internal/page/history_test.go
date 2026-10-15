package page

import (
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// historyShop is Acme Shop's total in a period: deployments counted, with the
// bands that go with them.
func historyShop(deployments int) metrics.Row {
	return metrics.Row{
		Level: metrics.ProjectRow, Name: "Acme Shop",
		Frequency: metrics.Frequency{InWindow: deployments, Last180: deployments, Band: metrics.DailyToWeekly,
			Latest: time.Date(2026, 5, 1, 9, 30, 0, 0, time.UTC)},
		LeadTime:   metrics.LeadTime{Commits: 48, Median: 2*time.Hour + 7*time.Minute, Band: metrics.LessThanOneDay},
		Recovery:   metrics.Recovery{Recoveries: 2, Median: 3 * time.Hour, Band: metrics.LessThanOneDay},
		ChangeFail: metrics.ChangeFailRate{Deployments: 15, FailedDeployments: 3, Failed: 3, Band: metrics.TwentyPercent},
		Rework:     metrics.ReworkRate{Deployments: 12, Rework: 2, Band: metrics.TwentyPercent},
	}
}

// historyData is the history page's data: two columns, the half-year 2026 H1
// and the rolling last 6 months. Acme Shop and its service API have numbers
// in both; Acme Tools has no deployment in the half-year and, in the last 6
// months, one failed deployment and one that recovered it (forsgren#68).
func historyData() Data {
	api := historyShop(5)
	api.Level, api.Name = metrics.LabelRow, "API"
	tools := metrics.Row{Level: metrics.ProjectRow, Name: "Acme Tools"}
	recovered := tools
	recovered.Frequency = metrics.Frequency{InWindow: 1, Band: metrics.LessThanSixMonthly,
		Latest: time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)}
	recovered.LeadTime = metrics.LeadTime{Commits: 2, Median: 25 * time.Minute, Band: metrics.LessThanOneHour}
	recovered.Recovery = metrics.Recovery{Recoveries: 1, Median: 40 * time.Hour, Band: metrics.OneDayToOneWeek}
	recovered.ChangeFail = metrics.ChangeFailRate{Deployments: 2, FailedDeployments: 1, Failed: 1,
		Band: metrics.FortyPercent}
	recovered.Rework = metrics.ReworkRate{Deployments: 1, Rework: 1, Band: metrics.HundredPercent}
	data := calculated()
	data.History = []metrics.Column{
		{
			Period: metrics.Period{Label: "2026 H1"},
			Rows:   []metrics.Row{historyShop(40), api, tools},
		},
		{
			Period: metrics.Period{Label: "Last 6 months", End: time.Date(2026, 10, 3, 12, 0, 0, 0, time.UTC), Rolling: true},
			Rows:   []metrics.Row{historyShop(30), api, recovered},
		},
	}
	return data
}

// TestHistoryPageGolden (forsgren#68): the history page is a table per
// measure, Overall Performance first, a row per table row and a column per
// period, oldest first, each cell the number and its score as the numbers
// and scoring page writes them and a dash for a row that is unread or has no
// deployment yet.
func TestHistoryPageGolden(t *testing.T) {
	checkPageGolden(t, "history.html", "testdata/history.golden.html", historyData())
}

// TestHistoryPageCellsAreNumbersAndScores (forsgren#68): one row of the
// frequency table, verbatim, and the dashes of the unread and empty rows.
func TestHistoryPageCellsAreNumbersAndScores(t *testing.T) {
	data := historyData()
	data.History[0].Rows[1] = metrics.Row{Level: metrics.LabelRow, Name: "API", Unread: true}
	got := rendered(t, "history.html", data)
	for _, want := range []string{
		"<td>40 · 6</td>\n            <td>30 · 6</td>",
		"<td>-</td>\n            <td>5 · 6</td>",
		"<td>-</td>\n            <td>1 · 0</td>",
		"<th scope=\"row\">Acme Tools</th>\n            <td>-</td>",
		"<th scope=\"col\">Last 6 months to 2026-10-03</th>",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("history page does not contain %q", want)
		}
	}
}
