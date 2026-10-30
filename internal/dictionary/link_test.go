package dictionary

import (
	"strings"
	"testing"
)

// bookLink is where Steve Smith's book Measuring Continuous Delivery is
// published (forsgren#585).
const bookLink = "https://leanpub.com/measuringcontinuousdelivery"

// TestParseReadsALink (forsgren#585): an entry may name the web address of the
// source its From line names.
func TestParseReadsALink(t *testing.T) {
	got, err := parse("- {name: A, kind: term, definition: d, from: f, link: 'https://example.com/a'}")
	if err != nil || len(got) != 1 {
		t.Fatalf("parse = %v, %v; want one entry", got, err)
	}
	if got[0].Link != "https://example.com/a" {
		t.Errorf("link = %q, want https://example.com/a", got[0].Link)
	}
}

// TestParseRefusesALinkThatIsNoWebAddress: a link is an https address with no
// white space and nothing Markdown would read as the end of the link.
func TestParseRefusesALinkThatIsNoWebAddress(t *testing.T) {
	for _, link := range []string{"http://example.com", "example.com", "https://", "https://a b",
		"https://a)b", "javascript:alert(1)"} {
		text := "- {name: A, kind: term, definition: d, from: f, link: '" + link + "'}"
		if _, err := parse(text); err == nil {
			t.Errorf("parse accepted the link %q", link)
		}
	}
}

// TestTheMainlineThroughputIndicatorNamesItsSource (forsgren#585): the term is
// in the dictionary, its two metrics in its definition, and it comes from
// Steve Smith's book Measuring Continuous Delivery, linked.
func TestTheMainlineThroughputIndicatorNamesItsSource(t *testing.T) {
	e := entryNamed(t, "Mainline Throughput Indicator")
	if e.Kind != KindTerm {
		t.Errorf("kind = %q, want %q", e.Kind, KindTerm)
	}
	for _, want := range []string{"Mainline Interval", "Mainline Lead Time", "Steve Smith",
		"Measuring Continuous Delivery"} {
		if !strings.Contains(e.Definition, want) {
			t.Errorf("want %q in the definition %q", want, e.Definition)
		}
	}
	if e.From != "Steve Smith's book Measuring Continuous Delivery." || e.Link != bookLink {
		t.Errorf("from %q linked to %q, want the book linked to %s", e.From, e.Link, bookLink)
	}
}

// entryNamed is the entry of the dictionary called name, failing t without one.
func entryNamed(t *testing.T, name string) Entry {
	t.Helper()
	for _, e := range entries(t) {
		if e.Name == name {
			return e
		}
	}
	t.Fatalf("the dictionary has no entry %q", name)
	return Entry{}
}

// TestMarkdownLinksTheFromLineOfAnEntryWithALink (forsgren#585): docs/dictionary.md
// writes the From line of an entry with a link as a Markdown link.
func TestMarkdownLinksTheFromLineOfAnEntryWithALink(t *testing.T) {
	want := "\nFrom: [Steve Smith's book Measuring Continuous Delivery.](" + bookLink + ")\n"
	if !strings.Contains(markdown(t), want) {
		t.Errorf("want the From line%s", want)
	}
}
