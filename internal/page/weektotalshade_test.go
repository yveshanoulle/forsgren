package page

import (
	"fmt"
	"regexp"
	"strconv"
	"testing"
)

// The Week page's Total row is shaded (forsgren#552 step 2, Yves's ruling):
// its row, class week-total, has a background mixed from the text colour, so it follows
// the light and the dark scheme with no colour of its own, and the text and
// the red highest marks still read at 4.5:1 or more on it.

// totalShade is the declaration that shades the Week Total row; its one
// figure is the share of the text colour in the background.
var totalShade = regexp.MustCompile(`background-color:\s*color-mix\(in srgb, currentcolor (\d+)%, transparent\);`)

// shadePercent is the share of the text colour in the Total row background,
// read from styles.css; it stops t when the rule is missing.
func shadePercent(t *testing.T) int {
	t.Helper()
	for _, body := range stylesSheet(t).bodies("tr.week-total") {
		if found := totalShade.FindStringSubmatch(body); found != nil {
			percent, err := strconv.Atoi(found[1])
			if err != nil {
				t.Fatal(err)
			}
			return percent
		}
	}
	t.Fatalf("want a tr.week-total rule with %s in styles.css", totalShade)
	return 0
}

// TestWeekTotalRowIsShadedFromTheTextColour: the Total row background is
// the text colour mixed into the canvas, between 1% and 20%, and the Total
// row carries the class.
func TestWeekTotalRowIsShadedFromTheTextColour(t *testing.T) {
	if percent := shadePercent(t); percent < 1 || percent > 20 {
		t.Errorf("want a subtle shade, 1%% to 20%% of the text colour, got %d%%", percent)
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
	percent := shadePercent(t)
	css := stylesCSS(t)
	for _, canvas := range lightCanvases {
		shade := mix("#000000", canvas, percent)
		wantContrast(t, swatch{"total text", "light", "#000000"}, []string{shade})
		for _, mark := range weekMarks {
			light, _ := trendColours(t, css, mark)
			wantContrast(t, swatch{mark, "light", light}, []string{shade})
		}
	}
	for _, canvas := range darkCanvases {
		shade := mix("#ffffff", canvas, percent)
		wantContrast(t, swatch{"total text", "dark", "#ffffff"}, []string{shade})
		for _, mark := range weekMarks {
			_, dark := trendColours(t, css, mark)
			wantContrast(t, swatch{mark, "dark", dark}, []string{shade})
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
