package page

import (
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
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
				Pushes:      metrics.DataStart{At: stored(time.September, 1), Cut: true},
				Pulls:       metrics.DataStart{At: stored(time.September, 21)},
				Issues:      metrics.DataStart{At: stored(time.January, 5)}},
			{Level: metrics.LabelRow, Name: "API", Project: "Acme Shop",
				Deployments: metrics.DataStart{At: stored(time.September, 20)},
				Commits:     metrics.DataStart{At: stored(time.September, 18)},
				Pushes:      perRepository, Pulls: perRepository, Issues: perRepository},
			{Level: metrics.ProjectRow, Name: "Acme Old", Project: "Acme Old"},
		},
	}
	data.FilesReadings = []metrics.FilesReading{
		{Project: "Acme Shop", FilesProgress: history.FilesProgress{Read: 4199, Left: 3925}, Runs: 4},
	}
	return data
}

// TestDataPageSaysHowFarACommitFilesReadIs (forsgren#594, step 2): under the
// table, one sentence per project whose commit files read is still going, by
// the project's name; none, and no element, without a read going.
func TestDataPageSaysHowFarACommitFilesReadIs(t *testing.T) {
	data := dataPageData()
	data.FilesReadings = append(data.FilesReadings,
		metrics.FilesReading{Project: "Acme Old", FilesProgress: history.FilesProgress{Read: 10, Left: 1}, Runs: 1})
	got := rendered(t, "data.html", data)
	wantAll(t, "data.html", got,
		"</div>\n    <p>Acme Shop: the files of 4 199 of 8 124 commits are read, 3 925 left "+
			"(about 4 more runs).</p>\n    <p>Acme Old: the files of 10 of 11 commits are read, 1 left "+
			"(about 1 more run).</p>\n    <h2 id=\"data-used-by\">")
	wantAll(t, "no read", rendered(t, "data.html", markedData(metrics.DataStart{At: stored(time.March, 2)})),
		"</div>\n    <h2 id=\"data-used-by\">")
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
            <td class="cut">… 2026-09-01<span class="visually-hidden"> (earlier data not yet read)</span></td>
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

// TestDataPageMarksADateWhereThePushReadStopped (forsgren#583, step 1): a
// date that is only where the push read stopped at the page cap carries … for
// the eye and "earlier data not yet read" for a screen reader, after the ▲ of
// a late one; the line above the table says what … means, for a push read
// and for the files of a service's pushed commits (forsgren#589).
func TestDataPageMarksADateWhereThePushReadStopped(t *testing.T) {
	data := dataPageData()
	shop := &data.DataStarts.Rows[0]
	shop.Pushes.Cut, shop.Commits.Cut, shop.Pulls.Cut = true, true, true
	got := rendered(t, "data.html", data)
	wantAll(t, "data.html", got,
		`<td class="cut">… 2026-02-27<span class="visually-hidden"> (earlier data not yet read)</span></td>`,
		`<td class="late cut">▲ … 2026-09-21<span class="visually-hidden"> (after Report Start)</span>`+
			`<span class="visually-hidden"> (earlier data not yet read)</span></td>`,
		"A date marked … is where a read stopped before the oldest data, a push read at its page limit or, "+
			"for a service or rule, the files of its pushed commits still being read: "+
			"earlier data is not yet read, so the date is not where the repository started.")
}

// markedData is a Data page of one project whose Pushes date is set as
// pushes says, every other date before Report Start.
func markedData(pushes metrics.DataStart) Data {
	data := calculated()
	data.DataStarts = metrics.DataStarts{
		Start: time.Date(2026, 9, 3, 12, 0, 0, 0, time.UTC),
		Rows: []metrics.DataRow{{Level: metrics.ProjectRow, Name: "Acme Shop", Project: "Acme Shop",
			Deployments: metrics.DataStart{At: stored(time.March, 2)}, Pushes: pushes,
			Issues: metrics.DataStart{At: stored(time.January, 5)}}},
	}
	return data
}

// The explanations of the markers above the table (forsgren#583, step 3).
const (
	lateSentence = "A date marked ▲ is after Report Start"
	cutSentence  = "A date marked … is where a read stopped before the oldest data"
	endSentence  = "A date marked ⇤ is as far back as GitHub keeps the activity"
)

// TestDataPageExplainsOnlyTheMarkersItShows (forsgren#583, step 3, Yves): an
// explanation above the table appears only when its marker is in a cell, and
// no line at all when none is.
func TestDataPageExplainsOnlyTheMarkersItShows(t *testing.T) {
	early, late := stored(time.September, 1), stored(time.September, 21)
	cases := map[string]struct {
		pushes      metrics.DataStart
		want, wantN []string
	}{
		"none": {metrics.DataStart{At: early}, nil,
			[]string{lateSentence, cutSentence, endSentence, "<p>The first data"}},
		"late": {metrics.DataStart{At: late}, []string{lateSentence}, []string{cutSentence, endSentence}},
		"cut": {metrics.DataStart{At: early, Cut: true}, []string{cutSentence},
			[]string{lateSentence, endSentence}},
		"github end": {metrics.DataStart{At: early, GitHubEnd: true}, []string{endSentence},
			[]string{lateSentence, cutSentence}},
	}
	for name, c := range cases {
		got := rendered(t, "data.html", markedData(c.pushes))
		wantAll(t, name, got, c.want...)
		wantNone(t, name, got, c.wantN...)
	}
}

// TestDataPageShowsWhereGitHubKeepsNoOlderActivity (forsgren#583, step 3): a
// date GitHub's list ends at carries ⇤ for the eye and "GitHub keeps no older
// activity" for a screen reader, not the red of a cut one.
func TestDataPageShowsWhereGitHubKeepsNoOlderActivity(t *testing.T) {
	got := rendered(t, "data.html", markedData(metrics.DataStart{At: stored(time.September, 1), GitHubEnd: true}))
	wantAll(t, "data.html", got,
		`<td class="github-end">⇤ 2026-09-01<span class="visually-hidden"> (GitHub keeps no older activity)</span></td>`)
}

// TestDataPageWhereGitHubKeepsNoOlderActivityMatchesGolden (forsgren#583,
// step 3): the page with a date where GitHub's list ends, its one line above
// the table naming that marker alone.
func TestDataPageWhereGitHubKeepsNoOlderActivityMatchesGolden(t *testing.T) {
	data := markedData(metrics.DataStart{At: stored(time.September, 1), GitHubEnd: true})
	checkPageGolden(t, "data.html", "testdata/data.github-end.golden.html", data)
}
