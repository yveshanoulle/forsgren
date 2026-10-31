package page

import (
	"math"
	"strconv"
	"testing"
)

// APCA (the Accessible Perceptual Contrast Algorithm, 0.0.98G-4g, the
// candidate contrast method of WCAG 3) measures how far apart two colours
// look as Lc, 0 for none to about 106. Unlike the WCAG 2 ratio it weighs a
// difference among dark colours as smaller than the same ratio among light
// ones, which is how a faint shade looks in dark mode (forsgren#598).
const (
	apcaBlackThreshold = 0.022
	apcaBlackClamp     = 1.414
	apcaScale          = 1.14
	apcaOffset         = 0.027
	apcaLowClip        = 0.1
	apcaMinDeltaY      = 0.0005
)

// apcaLc is the APCA lightness contrast of the #rrggbb foreground on the
// #rrggbb background: positive for dark on light, negative for light on
// dark, 0 below the level APCA counts as a visible difference.
func apcaLc(t *testing.T, foreground, background string) float64 {
	t.Helper()
	fg, bg := apcaY(t, foreground), apcaY(t, background)
	if math.Abs(bg-fg) < apcaMinDeltaY {
		return 0
	}
	if bg > fg {
		return apcaClip((math.Pow(bg, 0.56)-math.Pow(fg, 0.57))*apcaScale) * 100
	}
	return apcaClip((math.Pow(bg, 0.65)-math.Pow(fg, 0.62))*apcaScale) * 100
}

// apcaClip is 0 for a contrast below APCA's low clip, else the contrast
// moved toward 0 by APCA's offset.
func apcaClip(contrast float64) float64 {
	if math.Abs(contrast) < apcaLowClip {
		return 0
	}
	return contrast - math.Copysign(apcaOffset, contrast)
}

// apcaY is APCA's screen luminance of the #rrggbb colour, with the soft
// clamp APCA puts on near-black.
func apcaY(t *testing.T, hex string) float64 {
	t.Helper()
	weights := [3]float64{0.2126729, 0.7151522, 0.0721750}
	y := 0.0
	for i, weight := range weights {
		n, err := strconv.ParseUint(hex[1+2*i:3+2*i], 16, 8)
		if err != nil {
			t.Fatalf("colour %q: %v", hex, err)
		}
		y += weight * math.Pow(float64(n)/255, 2.4)
	}
	if y < apcaBlackThreshold {
		y += math.Pow(apcaBlackThreshold-y, apcaBlackClamp)
	}
	return y
}

// TestApcaMatchesItsPublishedExamples: APCA's own examples, #888 on white
// Lc 63.1, white on #888 Lc -68.5, black on white Lc 106.0, white on black
// Lc -107.9, and a colour on itself 0.
func TestApcaMatchesItsPublishedExamples(t *testing.T) {
	for _, c := range []struct {
		foreground, background string
		want                   float64
	}{
		{"#888888", "#ffffff", 63.1}, {"#ffffff", "#888888", -68.5},
		{"#000000", "#ffffff", 106.0}, {"#ffffff", "#000000", -107.9}, {"#121212", "#121212", 0},
	} {
		if got := apcaLc(t, c.foreground, c.background); math.Abs(got-c.want) > 0.05 {
			t.Errorf("APCA %s on %s = Lc %.2f, want %.1f", c.foreground, c.background, got, c.want)
		}
	}
}
