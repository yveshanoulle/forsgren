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
	css := stylesCSS(t)
	checkHeadingLook(t, h1Rule(t, css))
	if regexp.MustCompile(`\bcaption\s*\{`).MatchString(css) {
		t.Errorf("want no caption rule in styles.css, got:\n%s", css)
	}
}

// h1Rule is the body of the one h1 rule of css; it stops t when there is not
// exactly one.
func h1Rule(t *testing.T, css string) string {
	t.Helper()
	rules := regexp.MustCompile(`(?s)(?:^|\n)h1\s*\{([^}]*)\}`).FindAllStringSubmatch(css, -1)
	if len(rules) != 1 {
		t.Fatalf("want one h1 rule in styles.css, got %d in:\n%s", len(rules), css)
	}
	return rules[0][1]
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
	css := stylesCSS(t)
	rule := regexp.MustCompile(`(?s)(?:^|\n)body\s*\{([^}]*)\}`).FindStringSubmatch(css)
	if rule == nil {
		t.Fatalf("want a body rule in styles.css, got:\n%s", css)
	}
	width := regexp.MustCompile(`max-width:\s*([0-9.]+)rem`).FindStringSubmatch(rule[1])
	if width == nil {
		t.Fatalf("want the body rule to set a max-width in rem, got:\n%s", rule[1])
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
	tables, others := tableWidthRules(stylesCSS(t))
	if len(tables) != 1 {
		t.Fatalf("want one table rule in styles.css, got %d", len(tables))
	}
	if !strings.Contains(tables[0], "width: 100%;") {
		t.Errorf("want the table rule to set width: 100%%, got:\n%s", tables[0])
	}
	for _, selector := range others {
		t.Errorf("want no width on %q (the table rule is the one source)", selector)
	}
}

// tableWidthRules are the bodies of the rules of css whose selector is table,
// and the selectors of the other rules on a table or .table-scroll that set a
// width or a max-width.
func tableWidthRules(css string) (tables, others []string) {
	onTable := regexp.MustCompile(`(^|[\s,])(table|\.table-scroll)\b`)
	setsWidth := regexp.MustCompile(`(?:^|[\s;])(?:max-)?width\s*:`)
	for _, r := range regexp.MustCompile(`(?s)([^{}]+)\{([^}]*)\}`).FindAllStringSubmatch(css, -1) {
		selector := strings.TrimSpace(r[1])
		switch {
		case selector == "table":
			tables = append(tables, r[2])
		case onTable.MatchString(selector) && setsWidth.MatchString(r[2]):
			others = append(others, selector)
		}
	}
	return tables, others
}

// TestTheScrollbarSpaceIsAlwaysReserved (forsgren#153): the html rule sets
// scrollbar-gutter: stable, so a page with a vertical scrollbar and one
// without have the same width and the centred page does not jump between them.
func TestTheScrollbarSpaceIsAlwaysReserved(t *testing.T) {
	css := stylesCSS(t)
	if !regexp.MustCompile(`(?s)(?:^|\n)html\s*\{[^}]*scrollbar-gutter:\s*stable;`).MatchString(css) {
		t.Errorf("want an html rule with scrollbar-gutter: stable in styles.css, got:\n%s", css)
	}
}

// TestNoWrapCellsAreScopedByClass (forsgren#153): a table with class no-wrap
// keeps each cell on one line (a date, a number with its trend), while a table
// without it, such as the settings table with its long cells, still wraps. So
// the rule is on .no-wrap th and .no-wrap td, never on every th, td or table.
func TestNoWrapCellsAreScopedByClass(t *testing.T) {
	css := stylesCSS(t)
	scoped := regexp.MustCompile(`(?s)(?:^|\n)\.no-wrap th,\s*\.no-wrap td\s*\{[^}]*white-space:\s*nowrap;`)
	if !scoped.MatchString(css) {
		t.Errorf("want a .no-wrap th, .no-wrap td rule with white-space: nowrap in styles.css, got:\n%s", css)
	}
	for _, selector := range nowrapSelectors(css) {
		if !strings.Contains(selector, "no-wrap") && !strings.Contains(selector, "visually-hidden") {
			t.Errorf("want white-space: nowrap only under .no-wrap, got it on %q", selector)
		}
	}
}

// nowrapSelectors are the selectors of the rules of css that set
// white-space: nowrap.
func nowrapSelectors(css string) (selectors []string) {
	for _, r := range regexp.MustCompile(`(?s)([^{}]+)\{([^}]*)\}`).FindAllStringSubmatch(css, -1) {
		if strings.Contains(r[2], "white-space: nowrap") {
			selectors = append(selectors, strings.TrimSpace(r[1]))
		}
	}
	return selectors
}
