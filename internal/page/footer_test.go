package page

import (
	"strings"
	"testing"
)

// footerEntries are the footer's links in its order (forsgren#128,
// forsgren#370, forsgren#582): Settings, Legend, Dictionary, then Data.
var footerEntries = []menuEntry{
	{"settings.html", "Settings"}, {"legend.html", "Legend"},
	{"dictionary.html", "Dictionary"}, {"data.html", "Data"},
}

// wantFooter is the footer's line of links of a page whose links start with
// base: the entry of current plain text marked aria-current="page", as in the
// menu, the others links; no entry is current when current is empty.
func wantFooter(base, current string) string {
	return `<p>` + strings.Join(entryParts(footerEntries, base, current, "page"), " ") + `</p>`
}

// TestFooterMarksThePageItIsOn (forsgren#596): on the Settings, Legend,
// Dictionary and Data pages the footer names the page itself as plain text
// marked aria-current="page", as the menu does, and links the others; every
// other page links all four.
func TestFooterMarksThePageItIsOn(t *testing.T) {
	data := dataPageData()
	for _, e := range footerEntries {
		got := rendered(t, e.href, data)
		wantAll(t, e.href, got, wantFooter("", e.href))
		wantNone(t, e.href, got, `<a href="`+e.href+`">`)
	}
	wantAll(t, "index.html", rendered(t, "index.html", data), wantFooter("", ""))
	wantAll(t, "scoring/index.html", rendered(t, "scoring/index.html", data), wantFooter("../", ""))
}
