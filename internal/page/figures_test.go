package page

import (
	"regexp"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// TestTbdNotesCountsOfAThousandOrMoreHaveTheSeparator (forsgren#528): the
// counts the Notes list names are written like the cells' counts.
func TestTbdNotesCountsOfAThousandOrMoreHaveTheSeparator(t *testing.T) {
	data := tbdData()
	data.TbdMetrics[0].MainLead.UnknownPushes = 1282
	got := rendered(t, "tbd.html", data)
	wantAll(t, "tbd.html", got, "Acme Shop 1\u202f282</li>")
}

// TestIssuesTableCountsOfAThousandOrMoreHaveTheSeparator (forsgren#528,
// decision #529 A): the counts of the issues and days tables, the trend change
// and its label included, are written with a comma from 1000 on.
func TestIssuesTableCountsOfAThousandOrMoreHaveTheSeparator(t *testing.T) {
	data := calculated()
	data.IssueDays = []metrics.IssueDay{{Date: october(12), New: 1282, Completed: 1000, NotPlanned: 2000, Duplicate: 3000,
		Other: 4000, Open: 12345, OpenChange: 1500, Total: 1234567, OpenBugs: 1100, OpenBugsChange: -1200, Active: true}}
	got := rendered(t, "days.html", data)
	wantAll(t, "days.html", got, ">1\u202f282</td>", ">1\u202f000</td>", ">2\u202f000</td>", ">3\u202f000</td>",
		">4\u202f000</td>", ">1\u202f234\u202f567</td>", "12\u202f345 <span", "+1\u202f500", "increased by 1\u202f500",
		"1\u202f100 <span", "−1\u202f200", "decreased by 1\u202f200")
	wantNone(t, "days.html", got, ">1282<", "12345", "1234567", "1500", "1200")
}

// numRow is row for the numbers view, whose figure cells are class num
// (forsgren#528, decision #530 A).
func numRow(heading string, cells ...string) *regexp.Regexp {
	pattern := `<th scope="row">` + regexp.QuoteMeta(heading) + `</th>`
	for _, cell := range cells {
		pattern += `\s*<td class="num">` + regexp.QuoteMeta(cell) + `</td>`
	}
	return regexp.MustCompile(pattern)
}

// TestFigureCellsAreRightAligned (forsgren#528, decision #530 A): a cell that
// holds only a figure carries class num, which styles.css right-aligns, on the
// TBD table, the issues and days tables and the numbers view; a cell with words
// (Per repository, a push state, the no-data sentence, the band text of the
// standard and scoring views) carries none.
func TestFigureCellsAreRightAligned(t *testing.T) {
	tbd := rendered(t, "tbd.html", subRowsData())
	wantAll(t, "tbd.html", tbd, `<td class="num">3</td>`, `<td class="num" aria-describedby=`)
	if regexp.MustCompile(`<td>[^P]`).MatchString(tbd) {
		t.Errorf("want only Per repository in a cell without class, got:\n%s", tbd)
	}
	if !regexp.MustCompile(`<td( colspan="\d+")?>Per repository</td>`).MatchString(tbd) {
		t.Errorf("want Per repository in a cell without class num, got:\n%s", tbd)
	}
	states := rendered(t, "tbd.html", tbdData())
	wantAll(t, "tbd.html", states, `<td colspan="4">Push activity not readable</td>`)
	wantNone(t, "tbd.html", states, `class="num" colspan`)
	days := calculated()
	days.IssueDays = []metrics.IssueDay{{Date: october(12), New: 7, Open: 5, Active: true}}
	wantAll(t, "days.html", rendered(t, "days.html", days), `<td class="num">7</td>`, `<td class="num">5 <span`)
	numbers := rendered(t, "numbers/index.html", viewData())
	wantNone(t, "numbers/index.html", numbers, `<td>`)
	wantAll(t, "numbers/index.html", numbers, `<td class="num">`)
	standard := rendered(t, "standard/index.html", viewData())
	wantNone(t, "standard/index.html", standard, `class="num"`)
}

// TestThousandsSeparatorSettingDecidesTheSeparatorOnEveryPage (forsgren#528,
// decision #529 B and its parameter): the narrow no-break space by default, a
// comma for comma, nothing for none, on the DORA table, the TBD page, the
// issues and days tables and the legend; the decimal point stays.
func TestThousandsSeparatorSettingDecidesTheSeparatorOnEveryPage(t *testing.T) {
	for setting, want := range map[string]string{"": "1 282", "narrow_space": "1 282", "comma": "1,282",
		"none": "1282"} {
		data := tbdData()
		data.ThousandsSeparator = setting
		data.TbdMetrics[0].Volume.Count = 1282
		data.TbdMetrics[0].Push.Commits = 1282
		data.IssueDays = []metrics.IssueDay{{Date: october(12), New: 1282, Active: true}}
		data.DoraDays = 180
		for _, name := range []string{"tbd.html", "days.html"} {
			wantAll(t, name+" "+setting, rendered(t, name, data), ">"+want+"</td>")
		}
		edge := strings.Replace(want, "282", "441", 1) + " and more in"
		wantAll(t, "legend.html "+setting, rendered(t, "legend.html", data), edge)
		wantNone(t, "tbd.html "+setting, rendered(t, "tbd.html", data), " 2 ", "6 0")
	}
}

// columnHeads are the attributes of the column headers of page by their text.
func columnHeads(page string) map[string]string {
	heads := map[string]string{}
	for _, m := range regexp.MustCompile(`<th (scope="col"[^>]*)>([^<]*)</th>`).FindAllStringSubmatch(page, -1) {
		heads[m[2]] = m[1]
	}
	return heads
}

// wantHeadsAligned fails t unless every column header but first carries class
// num, and first does not.
func wantHeadsAligned(t *testing.T, name string, heads map[string]string, first string) {
	t.Helper()
	if len(heads) < 5 {
		t.Fatalf("%s: want the column headers, got %v", name, heads)
	}
	for text, tag := range heads {
		if has := strings.Contains(tag, `class="num"`); has == (text == first) {
			t.Errorf("%s: want the %s header with class num only if it is not the first, got %s", name, text, tag)
		}
	}
}

// TestFigureColumnHeadersAlignWithTheirCells (forsgren#528, decision #530 A and
// Yves's note: headers align consistently with their numeric cells): the column
// headers of the figure columns carry class num as their cells do, the first
// column's header (Project, Date) does not, and neither do the headers of the
// standard and scoring views; the headers spanning several columns (scope
// colgroup) keep their alignment, the start of the group.
func TestFigureColumnHeadersAlignWithTheirCells(t *testing.T) {
	days := calculated()
	days.IssueDays = []metrics.IssueDay{{Date: october(12), New: 7, Active: true}}
	for name, c := range map[string]struct {
		page, first string
		data        Data
	}{
		"tbd median": {"tbd.html", "Project", tbdData()},
		"tbd all":    {"tbd.html", "Project", inFigures(tbdData(), true)},
		"days":       {"days.html", "Date", days},
		"numbers":    {"numbers/index.html", "Project", viewData()},
	} {
		wantHeadsAligned(t, name, columnHeads(rendered(t, c.page, c.data)), c.first)
	}
	for _, view := range []string{"standard/index.html", "scoring/index.html"} {
		wantNone(t, view, rendered(t, view, viewData()), `<th scope="col" class="num"`)
	}
	wantNone(t, "tbd.html", rendered(t, "tbd.html", inFigures(tbdData(), true)), `scope="colgroup" class`)
}

// TestStylesRightAlignTheFigureCells(forsgren#528): one rule, .num, aligns on
// the right with tabular figures.
func TestStylesRightAlignTheFigureCells(t *testing.T) {
	sheet := stylesSheet(t)
	for _, declaration := range []string{"text-align: right", "font-variant-numeric: tabular-nums"} {
		if !sheet.declares(".num", declaration) {
			t.Errorf("want the .num rule to declare %q, got:\n%s", declaration, sheet.text)
		}
	}
}
