package page

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// The TBD table's sub-rows (forsgren#422, step 4, decisions #449, #450, #451,
// D4): a total row, then a row per label or service in the DORA form.

// subRowsData is the page's data from TbdMetrics alone: Acme Shop's total, its
// service API with deployments, its service IOS with none, and the repository
// label Website, which has two commits timed by author date.
func subRowsData() Data {
	shop, hour := "Acme Shop", time.Hour
	api := metrics.TbdRow{Level: metrics.LabelRow, Name: "API", Project: shop, Service: true,
		IntervalAbsent: true, PushAbsent: true,
		Developers: metrics.Developers{Count: 2, Commits: 3},
		Deploy: metrics.DeployMeasures{Commits: 3, TimeToDeploy: metrics.DurationSpread{Count: 3, Median: hour},
			PerDeployment: metrics.CountSpread{Count: 2, Median: 2}},
		Volume: metrics.DeploymentVolume{Count: 5, Final: 5}}
	ios := metrics.TbdRow{Level: metrics.LabelRow, Name: "IOS", Project: shop, Service: true,
		IntervalAbsent: true, PushAbsent: true}
	website := metrics.TbdRow{Level: metrics.LabelRow, Name: "Website", Project: shop,
		Interval: metrics.MainlineInterval{Project: "Website", Commits: 4, Gaps: 3, Mean: 2 * hour, Median: 2 * hour,
			ByAuthorDate: 2},
		Push: metrics.PushMeasures{Pushes: 2, Commits: 4, Direct: 4}, Volume: metrics.DeploymentVolume{Count: 1}}
	total := metrics.TbdRow{Level: metrics.ProjectRow, Name: shop, Project: shop,
		Push: metrics.PushMeasures{Pushes: 20, Commits: 40, Direct: 40}, Volume: metrics.DeploymentVolume{Count: 85}}
	data := calculated()
	data.TbdMetrics = []metrics.TbdRow{total, api, ios, website}
	return data
}

// TestTbdSubRowsAreInTheDoraForm: a label or service row is class label, its
// header the label with the project visually hidden before it, as the DORA
// table writes it; the total row is the project's name alone.
func TestTbdSubRowsAreInTheDoraForm(t *testing.T) {
	got := rendered(t, "tbd.html", subRowsData())
	wantAll(t, "tbd.html", got, "<th scope=\"row\">Acme Shop</th>", "<tr class=\"label\">",
		"<th scope=\"row\"><span class=\"visually-hidden\">Acme Shop: </span>API</th>",
		"<th scope=\"row\"><span class=\"visually-hidden\">Acme Shop: </span>Website</th>")
}

// TestAServiceRowHasDashesWhereTheMeasuresAreAbsent: a service row shows its own
// deployment cells and a dash in the Mainline Interval and in every push and
// pull request cell, also while the pull requests are not collected yet.
func TestAServiceRowHasDashesWhereTheMeasuresAreAbsent(t *testing.T) {
	want := "<th scope=\"row\"><span class=\"visually-hidden\">Acme Shop: </span>API</th>\n            " +
		tds("- | - | 1 h | - | - | - | 5 | - | 2 | - | - | - | - | 2") + "\n"
	data := subRowsData()
	wantAll(t, "collected", rendered(t, "tbd.html", data), want)
	data.PullsUncollected = true
	wantAll(t, "not collected", rendered(t, "tbd.html", data), want)
}

// TestAServiceWithoutDataHasItsOwnSentence: a service with no deployment and
// no deployed commit has one sentence across the row, worded for a service.
func TestAServiceWithoutDataHasItsOwnSentence(t *testing.T) {
	got := rendered(t, "tbd.html", subRowsData())
	wantAll(t, "tbd.html", got, "</span>IOS</th>\n            <td colspan=\"14\">"+
		"currently no data for this service in the last 30 days</td>")
}

// TestTheNotesListNamesALabelRowWithItsProject (D4): the line of a note names
// the row Project: label.
func TestTheNotesListNamesALabelRowWithItsProject(t *testing.T) {
	got := rendered(t, "tbd.html", subRowsData())
	wantAll(t, "tbd.html", got, "(2) Commits timed by author date: Acme Shop: Website 2</li>")
}

// TestTbdSubRowsGolden: the page with a total row and a service, a no-data
// service and a repository label row, with the median only and with all the
// figures.
func TestTbdSubRowsGolden(t *testing.T) {
	checkPageGolden(t, "tbd.html", "testdata/tbd.sub-rows.golden.html", subRowsData())
	checkPageGolden(t, "tbd.html", "testdata/tbd.all-sub-rows.golden.html", inFigures(subRowsData(), true))
}

// TestAnAbsentMeasureIsADashBecauseTheRowSaysAbsent: a service row marked
// absent shows its dashes even if its interval, push and pull request measures
// are not empty, never the measure of the repository by mistake, and with no
// note from them.
func TestAnAbsentMeasureIsADashBecauseTheRowSaysAbsent(t *testing.T) {
	data := subRowsData()
	api := &data.TbdMetrics[1]
	api.Interval = metrics.MainlineInterval{Project: "API", Commits: 4, Gaps: 3, Mean: time.Hour, Median: time.Hour,
		ByAuthorDate: 2}
	api.Lead = metrics.MainlineLeadTime{PullRequests: 5, Mean: time.Hour, Median: time.Hour, Bots: 1}
	api.Push = metrics.PushMeasures{Pushes: 9, Commits: 9, Direct: 9,
		TimeToMain: metrics.DurationSpread{Count: 9, Median: time.Hour}}
	want := "<th scope=\"row\"><span class=\"visually-hidden\">Acme Shop: </span>API</th>\n            " +
		tds("- | - | 1 h | - | - | - | 5 | - | 2 | - | - | - | - | 2") + "\n"
	wantAll(t, "tbd.html", rendered(t, "tbd.html", data), want)
	for _, note := range data.TbdNotes() {
		for _, p := range note.Projects {
			if p.Name == "Acme Shop: API" {
				t.Errorf("note %d names the service API", note.Number())
			}
		}
	}
}
