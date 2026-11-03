package page

import (
	"strconv"
	"strings"
	"testing"
)

// The Integration table (forsgren#622, step 2; decision #623, recommendation
// C): a second table below the TBD table, under an h2, with the TBD table's
// rows and the four Integration groups, so the TBD table keeps its columns.

// integrationCells are the cells of tbdData's projects in the second table, in
// the two ways the key tbd_figures shows them: the commits per working day per
// developer, the share of developers integrating on most working days, the
// trunk freshness and the longest gap (the median, and with all the longest
// too); a push state spans all of them.
var integrationCells = map[string][2]string{
	"Acme Shop": {"1.1 | 41% | 2.0 | 3.0",
		"1.3 | 1.1 | 2.4 | 0.6 | 41% | 2.5 | 2.0 | 6.0 | 1.8 | 3.0 | 9"},
	"Acme Tools": {"0.8 | 50% | 3.5 | 5.5",
		"0.9 | 0.8 | - | 0.3 | 50% | 4.0 | 3.5 | - | 2.1 | 5.5 | 7"},
	"Acme Docs": {"@4Push activity not readable", "@11Push activity not readable"},
	"Acme Web":  {"@4Pushes not collected yet", "@11Pushes not collected yet"},
}

// integrationGroups are the groups of the second table with all the figures,
// each with its columns and their aria-labels.
var integrationGroups = []struct {
	name    string
	columns []string
	labels  []string
}{
	{"Commits per working day", []string{"mean", "median", "p90", "SD"}, []string{
		"the mean of commits per working day per developer", "the median of commits per working day per developer",
		"the p90 of commits per working day per developer",
		"the standard deviation of commits per working day per developer"}},
	{"Regular integrators", []string{"regular share"},
		[]string{"share of developers integrating on most working days"}},
	{"Trunk freshness", []string{"mean", "median", "p90", "SD"}, []string{
		"the mean of trunk freshness in working days", "the median of trunk freshness in working days",
		"the p90 of trunk freshness in working days", "the standard deviation of trunk freshness in working days"}},
	{"Longest gap", []string{"median", "longest gap"}, []string{
		"the median of longest gap per developer in working days", "the longest gap of any developer in working days"}},
}

// integrationMedianHeaders are the headers of the second table with the median
// only: a header for each group, its aria-label saying what it is.
var integrationMedianHeaders = [][2]string{
	{"Commits per working day", "median commits per working day per developer"},
	{"Regular integrators", "share of developers integrating on most working days"},
	{"Trunk freshness", "median trunk freshness in working days"},
	{"Longest gap", "median longest gap per developer in working days"},
}

// integrationPart is the page from the h2 of the second table on.
func integrationPart(t *testing.T, data Data) string {
	t.Helper()
	_, part, found := strings.Cut(rendered(t, "tbd.html", data), `<h2 id="tbd-integration-heading">Integration</h2>`)
	if !found {
		t.Fatal("want the h2 Integration with the id tbd-integration-heading, got none")
	}
	return part
}

// integrationRow is the row of project in the second table, cells as the
// template writes them.
func integrationRow(all bool, project string) string {
	return "<th scope=\"row\">" + project + "</th>\n            " + tds(at(integrationCells[project], all)) + "\n"
}

// TestTheIntegrationTableIsASecondTableUnderItsOwnHeading: the h2 names the
// region of the table below it, which has no caption.
func TestTheIntegrationTableIsASecondTableUnderItsOwnHeading(t *testing.T) {
	part := integrationPart(t, tbdData())
	wantAll(t, "integration", part,
		`<div class="table-scroll" role="region" aria-labelledby="tbd-integration-heading" tabindex="0">`)
	wantNone(t, "integration", part, "<caption")
	if got := strings.Count(rendered(t, "tbd.html", tbdData()), "<table"); got != 2 {
		t.Errorf("want 2 tables, got %d", got)
	}
}

// TestTheIntegrationTableHasOneHeaderRowWithTheMedianOnly: Project and a header
// for each group, with the aria-labels, in one row.
func TestTheIntegrationTableHasOneHeaderRowWithTheMedianOnly(t *testing.T) {
	cells := []string{`<th scope="col">Project</th>`}
	for _, h := range integrationMedianHeaders {
		cells = append(cells, `<th scope="col" aria-label="`+h[1]+`" class="num">`+h[0]+`</th>`)
	}
	want := "<thead>\n          <tr>\n            " + strings.Join(cells, "\n            ") +
		"\n          </tr>\n        </thead>"
	wantAll(t, "integration", integrationPart(t, tbdData()), want)
}

// TestTheIntegrationTableHasTwoLevelHeadersWithAllTheFigures: each group is a
// column group on top, its columns beneath, 11 in all.
func TestTheIntegrationTableHasTwoLevelHeadersWithAllTheFigures(t *testing.T) {
	const indent = "\n            "
	tops := []string{`<th scope="col" rowspan="2">Project</th>`}
	var beneath []string
	for _, g := range integrationGroups {
		tops = append(tops, `<th scope="colgroup" colspan="`+strconv.Itoa(len(g.columns))+`">`+g.name+`</th>`)
		for i, c := range g.columns {
			beneath = append(beneath, `<th scope="col" aria-label="`+g.labels[i]+`" class="num">`+c+`</th>`)
		}
	}
	part := integrationPart(t, inFigures(tbdData(), true))
	wantAll(t, "integration", part, strings.Join(tops, indent), strings.Join(beneath, indent))
	if len(beneath) != 11 {
		t.Errorf("want 11 columns after the project, got %d", len(beneath))
	}
}

// TestTheIntegrationTableShowsTheRowsOfEachProject: the figures and the push
// states across the columns, in both figure modes.
func TestTheIntegrationTableShowsTheRowsOfEachProject(t *testing.T) {
	for _, all := range []bool{false, true} {
		part := integrationPart(t, inFigures(tbdData(), all))
		for _, project := range []string{"Acme Shop", "Acme Tools", "Acme Docs", "Acme Web"} {
			wantAll(t, project, part, integrationRow(all, project))
		}
	}
}

// TestTheTbdTableHasNoIntegrationColumn: the first table keeps its columns.
func TestTheTbdTableHasNoIntegrationColumn(t *testing.T) {
	for _, all := range []bool{false, true} {
		got := rendered(t, "tbd.html", inFigures(tbdData(), all))
		first, _, _ := strings.Cut(got, `<h2 id="tbd-integration-heading">`)
		wantNone(t, "tbd table", first, "Commits per working day", "Regular integrators", "Trunk freshness",
			"Longest gap")
	}
}

// TestTheIntegrationTableSpansItsColumnsForNoDataAndServices: a project without
// data is one sentence across the 4 (11) columns, a service row says Per
// repository across them, a label row is class label, and sub_rows: false
// leaves the label rows out.
func TestTheIntegrationTableSpansItsColumnsForNoDataAndServices(t *testing.T) {
	for all, span := range map[bool]string{false: "4", true: "11"} {
		noData := integrationPart(t, withoutData(all))
		wantAll(t, "no data", noData, "<th scope=\"row\">Acme Docs</th>\n            <td colspan=\""+span+
			"\">currently no data for this project in the last 30 days</td>")
		data := inFigures(subRowsData(), all)
		part := integrationPart(t, data)
		wantAll(t, "service", part, labelCell("Acme Shop", "API")+"\n            <td colspan=\""+span+
			"\">Per repository</td>", labelCell("Acme Shop", "Website"), "<tr class=\"label\">")
		data.HideSubRows = true
		wantNone(t, "sub rows off", integrationPart(t, data), "Per repository", "Website")
	}
}
