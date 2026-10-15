package page

import (
	"fmt"
	"math"
	"regexp"
	"strconv"
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
	for _, class := range []string{"trend-up", "trend-down", "trend-flat", "trend-flat-bugs"} {
		light, dark := trendColours(t, css, class)
		wantContrast(t, swatch{class, "light", light}, lightCanvases)
		wantContrast(t, swatch{class, "dark", dark}, darkCanvases)
	}
}

// trendColours are the light and the dark colour of the rule for class in css,
// as #rrggbb; it stops t when there is no such rule.
func trendColours(t *testing.T, css, class string) (light, dark string) {
	t.Helper()
	const hex = `\s*(#[0-9a-f]{6})\s*`
	rule := regexp.MustCompile(`(?s)\.` + class + `\s*\{[^}]*color:\s*light-dark\(` + hex + `,` + hex + `\)`)
	found := rule.FindStringSubmatch(css)
	if found == nil {
		t.Fatalf("want a .%s rule with color: light-dark(#rrggbb, #rrggbb) in styles.css, got:\n%s", class, css)
	}
	return found[1], found[2]
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
