package page

import (
	"strings"
	"unicode/utf8"
)

// oneLineLabel is the longest label, in characters, that stays on one line
// (forsgren#511).
const oneLineLabel = 15

// noBreakSpace is U+00A0, the space that is no break point.
const noBreakSpace = " "

// labelView is the visible part of a label or service row's header: the
// decorative dash with its space, and the label (the "labelheader" template).
type labelView struct{ Dash, Text string }

// labelHeaderOf is the view every table that has a label or service row
// writes its header with. A label of oneLineLabel characters or fewer
// (counted as runes) has a non-breaking space for each of its spaces and for
// the one after the dash, so the header stays on one line; a longer label
// keeps ordinary spaces and may wrap (forsgren#511).
func labelHeaderOf(label string) labelView {
	space := " "
	if utf8.RuneCountInString(label) <= oneLineLabel {
		space = noBreakSpace
	}
	return labelView{Dash: "–" + space, Text: strings.ReplaceAll(label, " ", space)}
}
