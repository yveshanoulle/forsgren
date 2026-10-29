package page

import (
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// The Data page (forsgren#579, step 2): per project and per label, service
// and rule, the first time forsgren stored data of each kind, a date after
// Report Start marked, so a window longer than the data shows where it starts.

// stored is 09:30 UTC on the given 2026 month and day.
func stored(month time.Month, d int) time.Time {
	return time.Date(2026, month, d, 9, 30, 0, 0, time.UTC)
}

// dataPageData is the Data page's data: Acme Shop with data from before Report
// Start and a late pull request, its API service with late deployments and Per
// repository cells, and Acme Old with nothing stored.
func dataPageData() Data {
	data := calculated()
	perRepository := metrics.DataStart{PerRepository: true}
	data.DataStarts = metrics.DataStarts{
		Start: time.Date(2026, 9, 3, 12, 0, 0, 0, time.UTC),
		Rows: []metrics.DataRow{
			{Level: metrics.ProjectRow, Name: "Acme Shop", Project: "Acme Shop",
				Deployments: metrics.DataStart{At: stored(time.March, 2)},
				Commits:     metrics.DataStart{At: stored(time.February, 27)},
				Pushes:      metrics.DataStart{At: stored(time.September, 1)},
				Pulls:       metrics.DataStart{At: stored(time.September, 21)},
				Issues:      metrics.DataStart{At: stored(time.January, 5)}},
			{Level: metrics.LabelRow, Name: "API", Project: "Acme Shop",
				Deployments: metrics.DataStart{At: stored(time.September, 20)},
				Commits:     metrics.DataStart{At: stored(time.September, 18)},
				Pushes:      perRepository, Pulls: perRepository, Issues: perRepository},
			{Level: metrics.ProjectRow, Name: "Acme Old", Project: "Acme Old"},
		},
	}
	return data
}

func TestDataPageMatchesGolden(t *testing.T) {
	checkPageGolden(t, "data.html", "testdata/data.golden.html", dataPageData())
}

func TestDataPageWithoutProjectsMatchesGolden(t *testing.T) {
	data := calculated()
	data.NoProjects = true
	checkPageGolden(t, "data.html", "testdata/data.no-projects.golden.html", data)
}

func TestDataPageWithoutSubRowsMatchesGolden(t *testing.T) {
	data := dataPageData()
	data.HideSubRows = true
	checkPageGolden(t, "data.html", "testdata/data.no-sub-rows.golden.html", data)
}

// TestDataPageCellsAreDatesMarkedWhenLate: each kind's cell is the UTC date,
// a late one marked for the eye and for a screen reader, a dash for nothing
// stored and Per repository for a kind a service row does not have.
func TestDataPageCellsAreDatesMarkedWhenLate(t *testing.T) {
	got := rendered(t, "data.html", dataPageData())
	wantAll(t, "data.html", got,
		"<h1 id=\"data-heading\">Data</h1>",
		`<th scope="col">Merged pull requests</th>`,
		`<td>2026-03-02</td>`,
		`<td class="late">▲ 2026-09-21<span class="visually-hidden"> (after Report Start)</span></td>`,
		`<td>Per repository</td>`, `<td>-</td>`)
	if strings.Contains(got, "▲ 2026-09-01") {
		t.Errorf("want 2026-09-01, before Report Start, unmarked")
	}
}

// TestDataPageSaysWhatUsesEachKind: under the table, which pages read each
// kind of data.
func TestDataPageSaysWhatUsesEachKind(t *testing.T) {
	got := rendered(t, "data.html", dataPageData())
	for _, kind := range dataKinds {
		if !strings.Contains(got, "<li><strong>"+kind.Name+"</strong>: "+kind.UsedBy+"</li>") {
			t.Errorf("want the line for %s, got:\n%s", kind.Name, got)
		}
	}
}

// TestDataPageColumnsStartWithIssues (forsgren#582): the columns after Project
// are Issues, Commits, Pushes, Deployments and Merged pull requests, and each
// row's cells follow them.
func TestDataPageColumnsStartWithIssues(t *testing.T) {
	got := rendered(t, "data.html", dataPageData())
	wantAll(t, "data.html", got, `<th scope="col">Project</th>
            <th scope="col">Issues</th>
            <th scope="col">Commits</th>
            <th scope="col">Pushes</th>
            <th scope="col">Deployments</th>
            <th scope="col">Merged pull requests</th>
          </tr>`,
		`<td>2026-01-05</td>
            <td>2026-02-27</td>
            <td>2026-09-01</td>
            <td>2026-03-02</td>
            <td class="late">▲ 2026-09-21`)
}

// TestDataPageIsLinkedInTheFooterOnlyWhenOn (forsgren#582): the Data page is
// in no menu; the footer links it after Dictionary while data_page is true,
// and not when the page is unlisted, which keeps its noindex tag, or hidden.
func TestDataPageIsLinkedInTheFooterOnlyWhenOn(t *testing.T) {
	data := dataPageData()
	wantAll(t, "scoring/index.html", rendered(t, "scoring/index.html", data),
		`<a href="../dictionary.html">Dictionary</a> <a href="../data.html">Data</a></p>`)
	for _, mode := range []map[string]bool{nil, {DataPage: true}} {
		data.Unlisted, data.Hidden = mode, nil
		wantNone(t, "data.html", rendered(t, "data.html", data), `data.html">Data</a></nav>`)
		data.Unlisted, data.Hidden = nil, mode
		if mode != nil {
			wantNone(t, "index.html", rendered(t, "index.html", data), `data.html">Data</a>`)
		}
	}
	data.Unlisted, data.Hidden = map[string]bool{DataPage: true}, nil
	got := rendered(t, "data.html", data)
	wantNone(t, "data.html unlisted", got, `data.html">Data</a>`)
	wantAll(t, "data.html unlisted", got, `<meta name="robots" content="noindex">`)
}
