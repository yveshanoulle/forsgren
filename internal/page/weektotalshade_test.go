package page

import (
	"fmt"
	"math"
	"regexp"
	"strconv"
	"testing"
)

// The Week page's Total row is shaded (forsgren#552 step 2, Yves's ruling):
// its row, class week-total, has a background mixed from the text colour, so it follows
// the light and the dark scheme with no colour of its own, and the text and
// the highest marks still read at 4.5:1 or more on it. Dark mode mixes in
// more of the text colour than light mode (forsgren#598), so the shade is
// seen in both.

// shadeMix is one color-mix of the text colour into the canvas; its figure is
// the share of the text colour.
const shadeMix = `color-mix\(in srgb, currentcolor (\d+)%, transparent\)`

// totalShade is the declaration that shades the Week Total row: a
// light-dark() of the light mode's mix and the dark mode's.
var totalShade = regexp.MustCompile(`background-color:\s*light-dark\(\s*` + shadeMix + `,\s*` + shadeMix + `\s*\);`)

// shadeMode is the Total row's shade in one mode: the text colour, the
// canvases it is mixed into and the share of the text colour.
type shadeMode struct {
	mode, text string
	canvases   []string
	percent    int
}

// colour is the light or the dark colour of a light-dark() pair, the one
// this mode shows.
func (m shadeMode) colour(light, dark string) string {
	if m.mode == "dark" {
		return dark
	}
	return light
}

// shadeModes are the light and the dark shade of the Total row background,
// read from styles.css; it stops t when the rule is missing.
func shadeModes(t *testing.T) []shadeMode {
	t.Helper()
	for _, body := range stylesSheet(t).bodies("tr.week-total") {
		if found := totalShade.FindStringSubmatch(body); found != nil {
			return []shadeMode{
				{"light", "#000000", lightCanvases, wholeNumber(t, found[1])},
				{"dark", "#ffffff", darkCanvases, wholeNumber(t, found[2])},
			}
		}
	}
	t.Fatalf("want a tr.week-total rule with %s in styles.css", totalShade)
	return nil
}

// wholeNumber is the whole number s; it stops t when s is none.
func wholeNumber(t *testing.T, s string) int {
	t.Helper()
	n, err := strconv.Atoi(s)
	if err != nil {
		t.Fatal(err)
	}
	return n
}

// TestWeekTotalRowIsShadedFromTheTextColour: the Total row background is
// the text colour mixed into the canvas, between 1% and 25% in each mode,
// and the Total row carries the class.
func TestWeekTotalRowIsShadedFromTheTextColour(t *testing.T) {
	for _, m := range shadeModes(t) {
		if m.percent < 1 || m.percent > 25 {
			t.Errorf("want a subtle %s shade, 1%% to 25%% of the text colour, got %d%%", m.mode, m.percent)
		}
	}
	wantAll(t, "week.html", rendered(t, "week.html", weekPageData()),
		weekTotalRowStart+"\n            <th scope=\"row\">Total</th>")
}

// weekMarks are the classes of the Week page's highest cells: the red of
// Failed and Fail rate (forsgren#545) and the blue of Deploys (forsgren#597).
var weekMarks = []string{"highest", "highest-deploys"}

// TestWeekTotalRowKeepsItsTextAndRedMarksReadable: on the shaded row, the
// text (black on white, white on each dark canvas) and the light and dark
// colour of each mark, the red of .highest and the blue of .highest-deploys,
// reach 4.5:1.
func TestWeekTotalRowKeepsItsTextAndRedMarksReadable(t *testing.T) {
	css := stylesCSS(t)
	for _, m := range shadeModes(t) {
		for _, canvas := range m.canvases {
			shade := []string{mix(m.text, canvas, m.percent)}
			wantContrast(t, swatch{"total text", m.mode, m.text}, shade)
			for _, mark := range weekMarks {
				wantContrast(t, swatch{mark, m.mode, m.colour(trendColours(t, css, mark))}, shade)
			}
		}
	}
}

// minShadeLc is the least APCA contrast the Total row's shade must have
// against the page background (forsgren#598): a non-text area has no WCAG
// minimum, so the floor is what light mode's 8% shade on white measures,
// Lc 9.4, which Yves sees, rounded down. The WCAG 2 ratio cannot hold it:
// it rates an 8% dark shade higher (1.22:1 on #121212) than the light one
// (1.19:1), the opposite of what the eye sees in dark mode, where APCA
// gives that dark shade Lc 0.
const minShadeLc = 9

// TestWeekTotalShadeIsVisibleInLightAndDark: the shaded Total row stands
// out from the page background by at least minShadeLc in both modes, on
// white and on each usual dark canvas.
func TestWeekTotalShadeIsVisibleInLightAndDark(t *testing.T) {
	for _, m := range shadeModes(t) {
		for _, canvas := range m.canvases {
			shade := mix(m.text, canvas, m.percent)
			if lc := math.Abs(apcaLc(t, shade, canvas)); lc < minShadeLc {
				t.Errorf("Total row shade in %s mode: %s on %s is Lc %.1f, want at least Lc %d",
					m.mode, shade, canvas, lc, minShadeLc)
			}
		}
	}
}

// mix is percent of the #rrggbb colour over the #rrggbb canvas, as the
// browser paints a color-mix with transparent on it.
func mix(colour, canvas string, percent int) string {
	share := float64(percent) / 100
	out := "#"
	for i := 1; i < 7; i += 2 {
		c, _ := strconv.ParseUint(colour[i:i+2], 16, 8)
		b, _ := strconv.ParseUint(canvas[i:i+2], 16, 8)
		out += fmt.Sprintf("%02x", int(float64(c)*share+float64(b)*(1-share)+0.5))
	}
	return out
}

// TestMixPaintsTheShareOverTheCanvas: 10% black on white is #e6e6e6, 0% the
// canvas, 100% the colour.
func TestMixPaintsTheShareOverTheCanvas(t *testing.T) {
	for _, c := range []struct {
		percent int
		want    string
	}{{10, "#e6e6e6"}, {0, "#ffffff"}, {100, "#000000"}} {
		if got := mix("#000000", "#ffffff", c.percent); got != c.want {
			t.Errorf("mix %d%% black on white = %s, want %s", c.percent, got, c.want)
		}
	}
}
