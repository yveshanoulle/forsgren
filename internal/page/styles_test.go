package page

import (
	"regexp"
	"strconv"
	"strings"
	"testing"
)

// stylesCSS is the embedded styles.css the site is written with.
func stylesCSS(t *testing.T) string {
	t.Helper()
	css, err := files.ReadFile("styles.css")
	if err != nil {
		t.Fatal(err)
	}
	return string(css)
}

// cssSheet is a stylesheet read into its rules, so a test finds a rule by its
// selector instead of matching the file's text; text is the file as written,
// for the failure messages.
type cssSheet struct {
	text  string
	rules []cssRule
}

// cssRule is one rule of a stylesheet: its selector list, joined by ", ",
// and its declarations as written between the braces.
type cssRule struct {
	selector, body string
}

// stylesSheet is the embedded styles.css read into its rules.
func stylesSheet(t *testing.T) cssSheet {
	t.Helper()
	return parseCSS(stylesCSS(t))
}

// parseCSS reads css into its rules in their order, comments left out.
func parseCSS(css string) cssSheet {
	sheet := cssSheet{text: css}
	bare := regexp.MustCompile(`(?s)/\*.*?\*/`).ReplaceAllString(css, "")
	for _, r := range regexp.MustCompile(`([^{}]+)\{([^}]*)\}`).FindAllStringSubmatch(bare, -1) {
		parts := strings.Split(r[1], ",")
		for i, part := range parts {
			parts[i] = strings.TrimSpace(part)
		}
		sheet.rules = append(sheet.rules, cssRule{selector: strings.Join(parts, ", "), body: r[2]})
	}
	return sheet
}

// bodies are the bodies of the rules whose selector is selector.
func (s cssSheet) bodies(selector string) (bodies []string) {
	for _, r := range s.rules {
		if r.selector == selector {
			bodies = append(bodies, r.body)
		}
	}
	return bodies
}

// declares tells whether a rule whose selector is selector holds declaration,
// written as "property: value".
func (s cssSheet) declares(selector, declaration string) bool {
	for _, body := range s.bodies(selector) {
		if declares(body, declaration) {
			return true
		}
	}
	return false
}

// selectorsDeclaring are the selectors of the rules that hold declaration.
func (s cssSheet) selectorsDeclaring(declaration string) (selectors []string) {
	for _, r := range s.rules {
		if declares(r.body, declaration) {
			selectors = append(selectors, r.selector)
		}
	}
	return selectors
}

// declares tells whether body holds declaration, "property: value", with any
// space after the colon.
func declares(body, declaration string) bool {
	property, value, _ := strings.Cut(declaration, ": ")
	pattern := `(?:^|[\s;])` + regexp.QuoteMeta(property) + `:\s*` + regexp.QuoteMeta(value) + `;`
	return regexp.MustCompile(pattern).MatchString(body)
}

// TestLabelDashIsDecorative (forsgren#38, review): the dash before a label
// row's heading is drawn for the eye only, with empty alternative text, so
// a screen reader reads "Acme Shop: API", never "en dash API".
func TestLabelDashIsDecorative(t *testing.T) {
	css := stylesCSS(t)
	if want := `.label th::before {
  content: "– " / "";
}`; !strings.Contains(css, want) {
		t.Errorf("want styles.css to hold\n%s\ngot:\n%s", want, css)
	}
}

// TestOneH1RuleStylesEveryPagesHeading (forsgren#135, step 10): styles.css has
// one h1 rule, which every page's heading uses, so changing it in one place
// changes all: bold and a font-size in rem above the body's 1rem, the look the
// caption had. No caption rule is left, as no table has a caption.
func TestOneH1RuleStylesEveryPagesHeading(t *testing.T) {
	sheet := stylesSheet(t)
	checkHeadingLook(t, h1Rule(t, sheet))
	if regexp.MustCompile(`\bcaption\s*\{`).MatchString(sheet.text) {
		t.Errorf("want no caption rule in styles.css, got:\n%s", sheet.text)
	}
}

// h1Rule is the body of the one h1 rule of sheet; it stops t when there is
// not exactly one.
func h1Rule(t *testing.T, sheet cssSheet) string {
	t.Helper()
	rules := sheet.bodies("h1")
	if len(rules) != 1 {
		t.Fatalf("want one h1 rule in styles.css, got %d in:\n%s", len(rules), sheet.text)
	}
	return rules[0]
}

// checkHeadingLook fails t unless rule is bold (600) and sets a font-size in
// rem above the body's 1rem.
func checkHeadingLook(t *testing.T, rule string) {
	t.Helper()
	if !strings.Contains(rule, "font-weight: 600;") {
		t.Errorf("want the h1 rule to be bold (600), got:\n%s", rule)
	}
	size := regexp.MustCompile(`font-size:\s*([0-9.]+)rem`).FindStringSubmatch(rule)
	if size == nil {
		t.Fatalf("want the h1 rule to set a font-size in rem, got:\n%s", rule)
	}
	if n, err := strconv.ParseFloat(size[1], 64); err != nil || n <= 1 {
		t.Errorf("want the h1 font-size above the body's 1rem, got %s", size[1])
	}
}

// TestBodyWidthGrowsWithTheScreenUpToAWideCap (forsgren#153, step 1): every
// page shares one body, and its max-width is a cap in rem wide enough for a
// 1800px screen (112.5rem), so below the cap the page and its tables follow
// the screen. The old 48rem held the tables to 768px.
func TestBodyWidthGrowsWithTheScreenUpToAWideCap(t *testing.T) {
	sheet := stylesSheet(t)
	rules := sheet.bodies("body")
	if len(rules) == 0 {
		t.Fatalf("want a body rule in styles.css, got:\n%s", sheet.text)
	}
	width := regexp.MustCompile(`max-width:\s*([0-9.]+)rem`).FindStringSubmatch(rules[0])
	if width == nil {
		t.Fatalf("want the body rule to set a max-width in rem, got:\n%s", rules[0])
	}
	const screen1800px = 112.5
	if n, err := strconv.ParseFloat(width[1], 64); err != nil || n < screen1800px {
		t.Errorf("want the body max-width at least %vrem (a 1800px screen), got %srem", screen1800px, width[1])
	}
}

// TestEveryTableFillsTheBodyAndNoOtherRuleSetsItsWidth (forsgren#153, step 3):
// the table rule sets width: 100%, so a table fills the body, whatever its
// page or column count, and the tables of all pages are equally wide. No other
// rule sets a width on a table or on its scroll box, so no page can differ.
func TestEveryTableFillsTheBodyAndNoOtherRuleSetsItsWidth(t *testing.T) {
	sheet := stylesSheet(t)
	tables := sheet.bodies("table")
	if len(tables) != 1 {
		t.Fatalf("want one table rule in styles.css, got %d", len(tables))
	}
	if !declares(tables[0], "width: 100%") {
		t.Errorf("want the table rule to set width: 100%%, got:\n%s", tables[0])
	}
	for _, selector := range otherTableWidthSelectors(sheet) {
		t.Errorf("want no width on %q (the table rule is the one source)", selector)
	}
}

// otherTableWidthSelectors are the selectors of the rules of sheet, other
// than the table rule, on a table or .table-scroll that set a width or a
// max-width.
func otherTableWidthSelectors(sheet cssSheet) (selectors []string) {
	onTable := regexp.MustCompile(`(^|[\s,])(table|\.table-scroll)\b`)
	setsWidth := regexp.MustCompile(`(?:^|[\s;])(?:max-)?width\s*:`)
	for _, r := range sheet.rules {
		if r.selector == "table" {
			continue
		}
		if onTable.MatchString(r.selector) && setsWidth.MatchString(r.body) {
			selectors = append(selectors, r.selector)
		}
	}
	return selectors
}

// TestTheScrollbarSpaceIsAlwaysReserved (forsgren#153): the html rule sets
// scrollbar-gutter: stable, so a page with a vertical scrollbar and one
// without have the same width and the centred page does not jump between them.
func TestTheScrollbarSpaceIsAlwaysReserved(t *testing.T) {
	sheet := stylesSheet(t)
	if !sheet.declares("html", "scrollbar-gutter: stable") {
		t.Errorf("want an html rule with scrollbar-gutter: stable in styles.css, got:\n%s", sheet.text)
	}
}

// TestNoWrapCellsAreScopedByClass (forsgren#153): a table with class no-wrap
// keeps each cell on one line (a date, a number with its trend), while a table
// without it, such as the settings table with its long cells, still wraps. So
// the rule is on .no-wrap th and .no-wrap td, never on every th, td or table.
func TestNoWrapCellsAreScopedByClass(t *testing.T) {
	sheet := stylesSheet(t)
	if !sheet.declares(".no-wrap th, .no-wrap td", "white-space: nowrap") {
		t.Errorf("want a .no-wrap th, .no-wrap td rule with white-space: nowrap in styles.css, got:\n%s", sheet.text)
	}
	for _, selector := range sheet.selectorsDeclaring("white-space: nowrap") {
		if !strings.Contains(selector, "no-wrap") && !strings.Contains(selector, "visually-hidden") {
			t.Errorf("want white-space: nowrap only under .no-wrap, got it on %q", selector)
		}
	}
}

// TestRunningTextHasAReadableMeasureWhileTablesKeepTheFullWidth (forsgren#153,
// decision #160 point 3): paragraphs and list items are capped at 72rem, so a
// line of the Legend stays readable on a wide screen, while the table rule
// has no max-width and so each table keeps the full width of the page.
func TestRunningTextHasAReadableMeasureWhileTablesKeepTheFullWidth(t *testing.T) {
	sheet := stylesSheet(t)
	if !sheet.declares("p, li", "max-width: 72rem") {
		t.Errorf("want a p, li rule with max-width: 72rem in styles.css, got:\n%s", sheet.text)
	}
	tables := sheet.bodies("table")
	if len(tables) == 1 && strings.Contains(tables[0], "max-width") {
		t.Errorf("want no max-width on the table rule, got:\n%s", tables[0])
	}
}

// chartColour matches what brings a colour into a rule: a colour literal or
// function, a variable, or a property that sets a colour.
var chartColour = regexp.MustCompile(`#[0-9a-fA-F]{3,8}\b` +
	`|\b(?:rgba?|hsla?|hwb|lab|lch|oklab|oklch|color|light-dark|var)\(` +
	`|(?:^|[\s;])(?:color|fill|stroke|background[a-z-]*|border[a-z-]*color|outline-color)\s*:`)

// chartRulesWithColour are the rules of sheet on an svg that bring a colour.
func chartRulesWithColour(sheet cssSheet) (rules []cssRule) {
	for _, r := range sheet.rules {
		if strings.Contains(r.selector, "svg") && chartColour.MatchString(r.body) {
			rules = append(rules, r)
		}
	}
	return rules
}

// TestHistoryChartStylesUseNoColours (forsgren#68): the History charts are
// sized by rules on the svg of a cell and its polyline, which exist, and bring
// no colour: no colour literal, function or variable, no colour property and no
// custom property in the sheet. The lines are drawn in currentcolor by the
// markup, so light and dark follow color-scheme and the text colour.
func TestHistoryChartStylesUseNoColours(t *testing.T) {
	sheet := stylesSheet(t)
	checkChartRules(t, sheet)
	for _, r := range chartRulesWithColour(sheet) {
		t.Errorf("want no colour in the rule %q, got:\n%s", r.selector, r.body)
	}
	if strings.Contains(sheet.text, "--") {
		t.Error("want no custom property (colour token) in styles.css")
	}
}

// checkChartRules fails t unless sheet has one rule on the svg of a cell, which
// scales it in its cell, and one on its polyline.
func checkChartRules(t *testing.T, sheet cssSheet) {
	t.Helper()
	for _, selector := range []string{"td svg", "td svg polyline"} {
		if n := len(sheet.bodies(selector)); n != 1 {
			t.Fatalf("want one %q rule in styles.css, got %d", selector, n)
		}
	}
	for _, declaration := range []string{"max-width: 100%", "height: auto"} {
		if !sheet.declares("td svg", declaration) {
			t.Errorf("want the chart to scale in its cell (%s), got %v", declaration, sheet.bodies("td svg"))
		}
	}
}
