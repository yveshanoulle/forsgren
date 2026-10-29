package page

import "testing"

// TestDataCutColourHasAContrastOfAtLeast4Point5 (forsgren#583, step 3, Yves):
// the Data page's cut date has its own rule, .cut, a colour with
// light-dark(light, dark), and each reads at 4.5:1 or more against the page
// background in its mode. Colour is never the only signal: the … and the
// hidden "earlier data not yet read" say the same.
func TestDataCutColourHasAContrastOfAtLeast4Point5(t *testing.T) {
	light, dark := trendColours(t, stylesCSS(t), "cut")
	wantContrast(t, swatch{"cut", "light", light}, lightCanvases)
	wantContrast(t, swatch{"cut", "dark", dark}, darkCanvases)
}
