package dictionary

import (
	"strings"
	"testing"
)

// bookDifferences are the sentences the Dictionary says where forsgren's
// Mainline Throughput Indicator differs from Steve Smith's book (forsgren#587,
// differences 2 and 3 of the review in #586).
var bookDifferences = []struct{ name, sentence string }{
	{"Mainline Lead Time", "Steve Smith's book counts from the push of the commit to a remote branch, " +
		"a time GitHub does not give, so a commit pushed directly to main shows seconds, not 0."},
	{"Mainline Throughput Indicator", "Its variation is shown as the p90 when tbd_figures is all, " +
		"not as the book's standard deviation, and the default view shows the median alone."},
}

// TestTheMainlineEntriesSayWhereTheyDifferFromTheBook (forsgren#587): the
// Mainline Lead Time starts at the author date, and the p90 stands in for the
// book's standard deviation.
func TestTheMainlineEntriesSayWhereTheyDifferFromTheBook(t *testing.T) {
	for _, d := range bookDifferences {
		if e := entryNamed(t, d.name); !strings.Contains(e.Definition, d.sentence) {
			t.Errorf("%s: want %q in the definition %q", d.name, d.sentence, e.Definition)
		}
	}
}
