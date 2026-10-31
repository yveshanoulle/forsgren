package page

import (
	"strconv"
	"strings"
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
		IntervalAbsent: true, PushAbsent: true, DeployedCommits: 3,
		Developers: metrics.Developers{Count: 2, Commits: 3},
		Deploy: metrics.DeployMeasures{Commits: 3,
			TimeToDeploy:  metrics.DurationSpread{Count: 3, Median: hour, Deviation: 25 * time.Minute},
			PerDeployment: metrics.CountSpread{Count: 2, Median: 2, Deviation: 1.5}},
		Volume: metrics.DeploymentVolume{Count: 5, Final: 5}}
	ios := metrics.TbdRow{Level: metrics.LabelRow, Name: "IOS", Project: shop, Service: true,
		IntervalAbsent: true, PushAbsent: true}
	total := tbdData().TbdMetrics[0]
	data := calculated()
	data.TbdMetrics = []metrics.TbdRow{total, api, ios, websiteRow(total)}
	return data
}

// websiteRow is the row of the repository label Website: a one-repository
// project with every measure of its own, one push of its own left out (note
// 6), none of them the total's.
func websiteRow(total metrics.TbdRow) metrics.TbdRow {
	site := total
	site.Level, site.Name = metrics.LabelRow, "Website"
	site.Interval = metrics.MainlineInterval{Project: "Website", Commits: 4, Gaps: 3, Mean: 3 * time.Hour,
		Median: 2 * time.Hour, P90: 5 * time.Hour, Deviation: 100 * time.Minute}
	site.Lead.Median, site.Lead.Mean, site.Lead.Deviation = 5*time.Hour, 6*time.Hour, 4*time.Hour
	site.BotLead.Median, site.BotLead.Mean, site.BotLead.Deviation = 35*time.Minute, 50*time.Minute, 20*time.Minute
	site.Push = metrics.PushMeasures{Pushes: 7, Commits: 12, PullRequests: 3, Direct: 9, UnknownAuthors: 1,
		TimeToMain: metrics.DurationSpread{Count: 12, Mean: 20 * time.Minute, Median: 10 * time.Minute,
			P90: time.Hour, Deviation: 15 * time.Minute},
		PerPush: metrics.CountSpread{Count: 7, Mean: 1.7, Median: 1, P90: 3, Deviation: 0.9}}
	site.MainLead = metrics.MainlineLeadTime{Project: "Website", Commits: 7, UnknownPushes: 1,
		Lead: metrics.DurationSpread{Count: 7, Mean: 90 * time.Minute, Median: time.Hour, P90: 0,
			Deviation: 40 * time.Minute}}
	site.Deploy.TimeToDeploy = metrics.DurationSpread{Count: 12, Mean: time.Hour, Median: 45 * time.Minute,
		P90: 4 * time.Hour, Deviation: 70 * time.Minute}
	site.Deploy.PerDeployment = metrics.CountSpread{Count: 9, Mean: 1.3, Median: 1, P90: 3, Deviation: 0.7}
	site.Volume.Count, site.Developers = 9, metrics.Developers{Count: 2, Commits: 12}
	return site
}

// TestTbdSubRowsAreInTheDoraForm: a label or service row is class label, its
// header the label with the project visually hidden before it, as the DORA
// table writes it; the total row is the project's name alone.
func TestTbdSubRowsAreInTheDoraForm(t *testing.T) {
	got := rendered(t, "tbd.html", subRowsData())
	wantAll(t, "tbd.html", got, "<th scope=\"row\">Acme Shop</th>", "<tr class=\"label\">",
		labelCell("Acme Shop", "API"),
		labelCell("Acme Shop", "Website"))
}

// perRepository is the sentence in place of the cells of a service row that are
// per repository (decision #450, C).
const perRepository = "Per repository"

// apiRow is the row of the service API of subRowsData as the template writes
// it, with the median only or with all the figures (decision #450, C): its own
// deployment cells, and one cell across each run of the cells that are per
// repository, which are, in the order of the columns, the Mainline Interval,
// Mainline Lead Time, Time to main, PR Lead Time and Bot PR Lead Time (5 columns, 20
// with all),
// then after the service's own Time to deploy, Commits and Pushes (2), the
// service's own Deployments and Deployed commits, Commits per push (1, 4), the
// service's own Commits per deployment and the four shares (4) (forsgren#485,
// #513, #518).
func apiRow(all bool) string {
	span := func(median, every int) string {
		if all {
			median = every
		}
		return "@" + strconv.Itoa(median) + perRepository
	}
	own := []string{"1 h", "2.0"}
	if all {
		own = []string{"&lt; 1 m | 1 h | - | 25 m", "0.0 | 2.0 | - | 1.5"}
	}
	cells := []string{span(5, 20), own[0], "@2" + perRepository, "5", "3", span(1, 4), own[1], span(4, 4), "2"}
	return labelCell("Acme Shop", "API") + "\n            " +
		tds(strings.Join(cells, " | ")) + "\n"
}

// TestAServiceRowHasOneSentenceWhereTheMeasuresAreAbsent: a service row shows
// its own deployment cells and, in place of each run of cells that are per
// repository, one cell across the run saying so, in both figure modes, also
// while the pull requests are not collected yet.
func TestAServiceRowHasOneSentenceWhereTheMeasuresAreAbsent(t *testing.T) {
	for _, all := range []bool{false, true} {
		data := inFigures(subRowsData(), all)
		wantAll(t, "collected", rendered(t, "tbd.html", data), apiRow(all))
		data.PullsUncollected = true
		wantAll(t, "not collected", rendered(t, "tbd.html", data), apiRow(all))
	}
}

// TestAServiceWithoutDataHasItsOwnSentence: a service with no deployment and
// no deployed commit has one sentence across the row, worded for a service.
func TestAServiceWithoutDataHasItsOwnSentence(t *testing.T) {
	got := rendered(t, "tbd.html", subRowsData())
	wantAll(t, "tbd.html", got, "</span>IOS</th>\n            <td colspan=\"17\">"+
		"currently no data for this service in the last 30 days</td>")
}

// TestTheNotesListNamesALabelRowWithItsProject (D4): the line of a note names
// the row Project: label.
func TestTheNotesListNamesALabelRowWithItsProject(t *testing.T) {
	got := rendered(t, "tbd.html", subRowsData())
	wantAll(t, "tbd.html", got, "not counted as 0: Acme Shop 2, Acme Shop: Website 1</li>")
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
	api.Interval = metrics.MainlineInterval{Project: "API", Commits: 4, Gaps: 3, Mean: time.Hour, Median: time.Hour}
	api.Lead = metrics.PRLeadTime{PullRequests: 5, Mean: time.Hour, Median: time.Hour}
	api.BotLead = metrics.PRLeadTime{PullRequests: 2, Mean: time.Hour, Median: time.Hour}
	api.Push = metrics.PushMeasures{Pushes: 9, Commits: 9, Direct: 9,
		TimeToMain: metrics.DurationSpread{Count: 9, Median: time.Hour}}
	api.MainLead = metrics.MainlineLeadTime{Commits: 9, UnknownPushes: 1, Filling: true,
		Lead: metrics.DurationSpread{Count: 9, Median: time.Hour}}
	wantAll(t, "tbd.html", rendered(t, "tbd.html", data), apiRow(false))
	for _, note := range data.TbdNotes() {
		for _, p := range note.Projects {
			if p.Name == "Acme Shop: API" {
				t.Errorf("note %d names the service API", note.Number())
			}
		}
	}
}
