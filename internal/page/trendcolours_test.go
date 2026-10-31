package page

import (
	"fmt"
	"math"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

// The canvases the trend colours sit on: light mode's is white in every
// browser; dark mode's is the browser's own, which varies, so the colours must
// hold on the lightest of the usual ones (Chrome's #121212, Firefox's #1c1b22
// and Safari's #1e1e1e).
var (
	lightCanvases = []string{"#ffffff"}
	darkCanvases  = []string{"#121212", "#1c1b22", "#1e1e1e"}
)

// minContrast is WCAG's contrast ratio for normal text, level AA.
const minContrast = 4.5

// TestTrendColoursHaveAContrastOfAtLeast4Point5InLightAndDark (forsgren#126,
// forsgren#114): styles.css colours the three trend classes, red for a rising
// count, green for a falling one and grey for one that did not change, each
// with light-dark(light, dark), and every colour reads at 4.5:1 or more against
// the page background in its mode. Colour is never the only signal: the arrow
// and the aria-label say the same.
func TestTrendColoursHaveAContrastOfAtLeast4Point5InLightAndDark(t *testing.T) {
	css := stylesCSS(t)
	for _, class := range []string{
		"trend-up", "trend-down", "trend-flat", "trend-flat-bugs", "bugs-zero", "highest", "highest-deploys",
	} {
		light, dark := trendColours(t, css, class)
		wantContrast(t, swatch{class, "light", light}, lightCanvases)
		wantContrast(t, swatch{class, "dark", dark}, darkCanvases)
	}
}

// trendColours are the light and the dark colour of the rule for class in css,
// as #rrggbb; it stops t when there is no such rule.
func trendColours(t *testing.T, css, class string) (light, dark string) {
	t.Helper()
	const hex = `\s*(#(?:[0-9a-f]{6}|[0-9a-f]{3}))\s*`
	rule := regexp.MustCompile(`(?is)\.` + class + `\s*\{[^}]*color:\s*light-dark\(` + hex + `,` + hex + `\)`)
	found := rule.FindStringSubmatch(css)
	if found == nil {
		t.Fatalf("want a .%s rule with color: light-dark(#rrggbb, #rrggbb) in styles.css, got:\n%s", class, css)
	}
	return longHex(found[1]), longHex(found[2])
}

// longHex is the colour as #rrggbb in lower case, whatever way the sheet writes
// it: stylelint --fix, which FBP runs on styles.css, shortens #000000 to #000,
// so a colour is compared by value, never as written (forsgren#212).
func longHex(colour string) string {
	colour = strings.ToLower(colour)
	if len(colour) == 4 {
		return "#" + strings.Repeat(colour[1:2], 2) + strings.Repeat(colour[2:3], 2) + strings.Repeat(colour[3:4], 2)
	}
	return colour
}

// TestColoursAreComparedByValueNotAsWritten (forsgren#212): a rule written with
// the short form the formatter produces, or in capitals, reads as the same
// colour as its long form, and a different colour still reads as different.
// The raw strings differ, which is what a comparison as written would trip on.
func TestColoursAreComparedByValueNotAsWritten(t *testing.T) {
	css := ".short { color: light-dark(#000, #FFF); }\n.long { color: light-dark(#000000, #ffffff); }\n" +
		".other { color: light-dark(#001, #fff); }"
	got := map[string][2]string{}
	for _, class := range []string{"short", "long", "other"} {
		light, dark := trendColours(t, css, class)
		got[class] = [2]string{light, dark}
	}
	want := map[string][2]string{
		"short": {"#000000", "#ffffff"}, "long": {"#000000", "#ffffff"}, "other": {"#000011", "#ffffff"},
	}
	for class, colours := range want {
		if got[class] != colours {
			t.Errorf(".%s reads %v, want %v", class, got[class], colours)
		}
	}
	if raw := "#000"; raw == got["long"][0] {
		t.Error("the raw short form equals the long one: the proof of a comparison as written is void")
	}
}

// swatch is the colour of a trend class in one mode.
type swatch struct{ class, mode, colour string }

// wantContrast fails t for each canvas that the swatch does not reach
// minContrast on, naming the measured ratio.
func wantContrast(t *testing.T, s swatch, canvases []string) {
	t.Helper()
	for _, canvas := range canvases {
		if ratio := contrast(t, s.colour, canvas); ratio < minContrast {
			t.Errorf(".%s in %s mode: %s on %s is %.2f:1, want at least %.1f:1",
				s.class, s.mode, s.colour, canvas, ratio, minContrast)
		}
	}
}

// contrast is the WCAG contrast ratio of the two #rrggbb colours.
func contrast(t *testing.T, a, b string) float64 {
	t.Helper()
	la, lb := luminance(t, a), luminance(t, b)
	return (math.Max(la, lb) + 0.05) / (math.Min(la, lb) + 0.05)
}

// luminance is the relative luminance of the #rrggbb colour hex.
func luminance(t *testing.T, hex string) float64 {
	t.Helper()
	var channels [3]float64
	for i := range channels {
		n, err := strconv.ParseUint(hex[1+2*i:3+2*i], 16, 8)
		if err != nil {
			t.Fatal(fmt.Errorf("colour %q: %w", hex, err))
		}
		channels[i] = linear(float64(n) / 255)
	}
	return 0.2126*channels[0] + 0.7152*channels[1] + 0.0722*channels[2]
}

// linear is an sRGB channel (0 to 1) as light intensity.
func linear(c float64) float64 {
	if c <= 0.03928 {
		return c / 12.92
	}
	return math.Pow((c+0.055)/1.055, 2.4)
}
