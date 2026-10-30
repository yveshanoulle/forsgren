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

// legendBookDifferences are the sentences the TBD section says where the
// Mainline Lead Time and the indicator's variation differ from the book
// (forsgren#587, differences 2 and 3 of the review in #586).
var legendBookDifferences = []string{
	"So this page shows its own Mainline Lead Time, over every commit that reached main, and two views of it:",
	"<p>On this page the Mainline Lead Time starts at the author date of a commit. The book counts from the " +
		"push of the commit to a remote branch, but GitHub gives forsgren no time for a push to a branch. So a " +
		"branch worked on for days counts from the author date of its first commit, and a commit pushed directly " +
		"to main shows the seconds between its commit and its push, where the book counts 0.</p>",
	"<p>The book reads the indicator as an average and a variation: the median and the standard deviation. " +
		"This page shows no standard deviation. The default view shows the median alone, and when all three " +
		"figures are shown the p90 stands in for the variation.</p>",
}

// TestLegendSaysWhereTheMainlineLeadTimeDiffersFromTheBook (forsgren#587): the
// TBD section says that the Mainline Lead Time starts at the author date and
// that the p90 stands in for the book's standard deviation; "in full" is
// retired in legendTbdRetired.
func TestLegendSaysWhereTheMainlineLeadTimeDiffersFromTheBook(t *testing.T) {
	section := legendTbdSection(t, rendered(t, "legend.html", calculated()))
	wantAll(t, "legend.html", section, legendBookDifferences...)
}
