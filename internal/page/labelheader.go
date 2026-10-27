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

// wordJoiner is U+2060, which allows no break on either side. The en dash is
// line break class BA, and UAX #14 LB12a lets a break stand before a no-break
// space that follows a BA, so the no-break space alone does not glue the dash
// to the label (forsgren#526).
const wordJoiner = "\u2060"

// labelView is the visible part of a label or service row's header: the
// decorative dash with its space, and the label (the "labelheader" template).
type labelView struct{ Dash, Text string }

// labelHeaderOf is the view every table that has a label or service row
// writes its header with. A label of oneLineLabel characters or fewer
// (counted as runes) has a non-breaking space for each of its spaces and for
// the one after the dash, a word joiner before that one, so the header stays
// on one line; a longer label keeps ordinary spaces and may wrap
// (forsgren#511, #526).
func labelHeaderOf(label string) labelView {
	if utf8.RuneCountInString(label) <= oneLineLabel {
		return labelView{Dash: "–" + wordJoiner + noBreakSpace, Text: strings.ReplaceAll(label, " ", noBreakSpace)}
	}
	return labelView{Dash: "– ", Text: label}
}
