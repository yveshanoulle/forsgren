package page

import (
	"testing"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

const (
	dashNB = `<span aria-hidden="true">–` + " " + `</span>`
	dashSp = `<span aria-hidden="true">– </span>`
)

// labelCell is the header of a label row of a project as the page writes it,
// for a label of one word of up to 15 characters.
func labelCell(project, label string) string {
	return `<th scope="row"><span class="visually-hidden">` + project + `: </span>` + dashNB + label + "</th>"
}

// TestLabelHeaderKeepsALabelOfFifteenCharactersOnOneLine (forsgren#511): every
// space of the visible dash and label is a non-breaking space for a label of
// up to 15 characters, counted as runes; a longer label keeps its spaces.
func TestLabelHeaderKeepsALabelOfFifteenCharactersOnOneLine(t *testing.T) {
	nb := " "
	cases := []struct{ name, label, dash, text string }{
		{"one word of 8", "Releases", nb, "Releases"},
		{"two words of 15", "Mobile app, iOS", nb, "Mobile" + nb + "app," + nb + "iOS"},
		{"two words of 16", "Mobile app, iOS!", " ", "Mobile app, iOS!"},
		{"16 runes in more bytes", "Zürich service ü", " ", "Zürich service ü"},
		{"14 runes in more bytes", "Zürich service", nb, "Zürich" + nb + "service"},
	}
	for _, c := range cases {
		want := labelView{Dash: "–" + c.dash, Text: c.text}
		if got := labelHeaderOf(c.label); got != want {
			t.Errorf("%s: want %q, got %q", c.name, want, got)
		}
	}
}

// renamed gives every label row of rows the name.
func renamed(rows []metrics.Row, name string) []metrics.Row {
	for i := range rows {
		if rows[i].Level == metrics.LabelRow {
			rows[i].Name = name
		}
	}
	return rows
}

// TestEveryTableWritesTheLabelHeaderThroughTheHelper: the DORA table, History
// and TBD write a label row's header with the one helper, a 9-character name
// with a space and a 16-character one.
func TestEveryTableWritesTheLabelHeaderThroughTheHelper(t *testing.T) {
	for name, want := range map[string]string{
		"Two words":        dashNB + "Two words",
		"Sixteen chars ok": dashSp + "Sixteen chars ok",
	} {
		dora := calculated()
		dora.Rows = Table(renamed(labelledRows(), name))
		hist := historyData()
		for _, col := range hist.History {
			renamed(col.Rows, name)
		}
		tbd := subRowsData()
		for i := range tbd.TbdMetrics {
			if tbd.TbdMetrics[i].Level == metrics.LabelRow {
				tbd.TbdMetrics[i].Name = name
			}
		}
		wantAll(t, "index.html", rendered(t, "index.html", dora), want+"</th>")
		wantAll(t, "history.html", rendered(t, "history.html", hist), want+": ")
		wantAll(t, "tbd.html", rendered(t, "tbd.html", tbd), want+"</th>")
	}
}
