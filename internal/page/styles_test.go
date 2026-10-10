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

// TestCaptionFontIsLargerThanBody (forsgren#45, step 2): the caption rule in
// styles.css sets a font-size in rem above 1, the body's size (the body sets
// none, so it is 1rem). Parsed, not matched as one exact string, so the size
// can be tuned without touching the test.
func TestCaptionFontIsLargerThanBody(t *testing.T) {
	css := stylesCSS(t)
	rule := regexp.MustCompile(`(?s)\bcaption\s*\{([^}]*)\}`).FindStringSubmatch(css)
	if rule == nil {
		t.Fatalf("want a caption rule in styles.css, got:\n%s", css)
	}
	size := regexp.MustCompile(`font-size:\s*([0-9.]+)rem`).FindStringSubmatch(rule[1])
	if size == nil {
		t.Fatalf("want the caption rule to set a font-size in rem, got:\n%s", rule[1])
	}
	if n, err := strconv.ParseFloat(size[1], 64); err != nil || n <= 1 {
		t.Errorf("want the caption font-size above the body's 1rem, got %s", size[1])
	}
}
