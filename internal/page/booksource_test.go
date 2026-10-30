package page

import "testing"

// bookCredit is the book the Mainline Throughput Indicator comes from, linked
// (forsgren#585).
const bookCredit = `Steve Smith's book <a href="https://leanpub.com/measuringcontinuousdelivery">` +
	`Measuring Continuous Delivery</a>`

// TestDictionaryPageLinksTheSourceOfTheMainlineThroughputIndicator
// (forsgren#585): the entry's From line links the book.
func TestDictionaryPageLinksTheSourceOfTheMainlineThroughputIndicator(t *testing.T) {
	wantAll(t, "dictionary.html", rendered(t, "dictionary.html", viewData()),
		`<dt id="mainline-throughput-indicator">Mainline Throughput Indicator</dt>`,
		`<dd>From: <a href="https://leanpub.com/measuringcontinuousdelivery">`+
			`Steve Smith&#39;s book Measuring Continuous Delivery.</a></dd>`)
}

// TestLegendCreditsTheBookOfTheMainlineThroughputIndicator (forsgren#585): the
// TBD section names the book where it first names the indicator.
func TestLegendCreditsTheBookOfTheMainlineThroughputIndicator(t *testing.T) {
	section := legendTbdSection(t, rendered(t, "legend.html", calculated()))
	wantAll(t, "legend.html", section, "<p>The Mainline Throughput Indicator, named in "+bookCredit+
		", has one lead time, the Mainline Lead Time.")
}
