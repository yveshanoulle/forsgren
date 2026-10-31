package page

import (
	"strconv"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// withoutData is tbdData with Acme Docs (the third project) without data in
// the window: no deployed commit, no deployment, no push and no merged pull
// request. Its Mainline Interval keeps a note, to see that no marker or note
// line comes from the row (forsgren#394, step 3, decision #433).
func withoutData(all bool) Data {
	data := inFigures(tbdData(), all)
	data.TbdMetrics[2] = metrics.TbdRow{Level: metrics.ProjectRow, Name: "Acme Docs", Project: "Acme Docs",
		Interval: metrics.MainlineInterval{Project: "Acme Docs", Commits: 4, Gaps: 3, Mean: 2 * 3600e9, ByAuthorDate: 4}}
	return data
}

// noDataRow is the row of a project without data: the project, then one cell
// across every column after it.
func noDataRow(columns int, days int) string {
	return "<th scope=\"row\">Acme Docs</th>\n            <td colspan=\"" + strconv.Itoa(columns) +
		"\">currently no data for this project in the last " + strconv.Itoa(days) + " days</td>\n          </tr>"
}

// TestTbdRowWithoutDataIsOneSentenceAcrossTheColumns (forsgren#394, step 3,
// decision #433): the whole row is one cell spanning the 17 columns after the
// project with the median only, the 41 with all the figures, saying the
// window's days from the config; the other rows are unchanged.
func TestTbdRowWithoutDataIsOneSentenceAcrossTheColumns(t *testing.T) {
	for name, c := range map[string]struct {
		all     bool
		columns int
	}{"median": {false, 17}, "all": {true, 41}} {
		data := withoutData(c.all)
		got := rendered(t, "tbd.html", data)
		wantAll(t, name, got, noDataRow(c.columns, 30),
			tbdRow(c.all, "Acme Shop", leadPair(c.all, "Acme Shop"), "3"))
		data.DoraDays = 90
		wantAll(t, name+" 90", rendered(t, "tbd.html", data), noDataRow(c.columns, 90))
	}
}

// TestTbdColumnsAcrossMatchTheHeader: the sentence cell spans exactly the
// header's columns after Project, in both figure modes.
func TestTbdColumnsAcrossMatchTheHeader(t *testing.T) {
	if got := strings.Count(medianHead(), "<th ") - 1; got != 17 {
		t.Errorf("median header has %d columns after the project, want 17", got)
	}
	_, beneath := tbdHeaders()
	if got := strings.Count(beneath, "<th "); got != 41 {
		t.Errorf("all-figures header has %d columns after the project, want 41", got)
	}
}

// TestTbdRowWithAnyOneOfTheFourKeepsItsDataRow: each condition alone keeps
// the normal row; a single measure without a value keeps its dash.
func TestTbdRowWithAnyOneOfTheFourKeepsItsDataRow(t *testing.T) {
	for name, change := range map[string]func(*Data){
		"deployed commit": func(d *Data) { d.TbdMetrics[2].Deploy.Commits = 1 },
		"deployment":      func(d *Data) { d.TbdMetrics[2].Volume.Count = 1 },
		"push":            func(d *Data) { d.TbdMetrics[2].Push.Pushes = 1 },
		"pull request":    func(d *Data) { d.TbdMetrics[2].Lead.PullRequests = 1 },
		"bot pull":        func(d *Data) { d.TbdMetrics[2].BotLead.PullRequests = 1 },
	} {
		data := withoutData(false)
		change(&data)
		wantNone(t, name, rendered(t, "tbd.html", data), "currently no data", "colspan=\"17\"")
	}
}

// TestTbdRowWithoutDataHasNoNoteMarker: the row has no marker and no line of
// the Notes list comes from it.
func TestTbdRowWithoutDataHasNoNoteMarker(t *testing.T) {
	data := withoutData(false)
	for _, row := range data.TbdNotes() {
		for _, p := range row.Projects {
			if p.Name == "Acme Docs" {
				t.Errorf("note %d names Acme Docs", row.Number())
			}
		}
	}
	got := rendered(t, "tbd.html", data)
	i := strings.Index(got, "<th scope=\"row\">Acme Docs</th>")
	j := strings.Index(got[i:], "</tr>")
	wantNone(t, "row", got[i:i+j], "aria-describedby", "(")
}
