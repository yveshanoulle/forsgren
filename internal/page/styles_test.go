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
