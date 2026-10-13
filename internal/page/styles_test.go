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
	rules := regexp.MustCompile(`(?s)(?:^|\n)h1\s*\{([^}]*)\}`).FindAllStringSubmatch(css, -1)
	if len(rules) != 1 {
		t.Fatalf("want one h1 rule in styles.css, got %d in:\n%s", len(rules), css)
	}
	if !strings.Contains(rules[0][1], "font-weight: 600;") {
		t.Errorf("want the h1 rule to be bold (600), got:\n%s", rules[0][1])
	}
	size := regexp.MustCompile(`font-size:\s*([0-9.]+)rem`).FindStringSubmatch(rules[0][1])
	if size == nil {
		t.Fatalf("want the h1 rule to set a font-size in rem, got:\n%s", rules[0][1])
	}
	if n, err := strconv.ParseFloat(size[1], 64); err != nil || n <= 1 {
		t.Errorf("want the h1 font-size above the body's 1rem, got %s", size[1])
	}
	if regexp.MustCompile(`\bcaption\s*\{`).MatchString(css) {
		t.Errorf("want no caption rule in styles.css, got:\n%s", css)
	}
}
