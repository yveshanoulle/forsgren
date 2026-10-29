package page

import (
	"html"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/dictionary"
)

// TestDictionaryPageMatchesGolden (forsgren#370, step 2): dictionary.html is
// made from the embedded dictionary alone, so it reads the same whatever the
// data is.
func TestDictionaryPageMatchesGolden(t *testing.T) {
	checkPageGolden(t, "dictionary.html", "testdata/dictionary.golden.html", calculated())
}

// TestDictionaryPageHasTwoSectionsOfEntries: Numbers, then Terms, each a
// heading, and every entry of the dictionary once, in its section, with an
// anchor id, its name, its definition and its source.
func TestDictionaryPageHasTwoSectionsOfEntries(t *testing.T) {
	got := rendered(t, "dictionary.html", viewData())
	wantAll(t, "dictionary.html", got, "<title>Dictionary · forsgren</title>", "<h1>Dictionary</h1>",
		`<h2 id="numbers">Numbers</h2>`, `<h2 id="terms">Terms</h2>`)
	terms := strings.Index(got, `<h2 id="terms">`)
	if numbers := strings.Index(got, `<h2 id="numbers">`); numbers < 0 || terms < numbers {
		t.Fatalf("want the Numbers section before the Terms section, got %d and %d", numbers, terms)
	}
	wantSection(t, got, dictionary.KindNumber, [2]int{0, terms})
	wantSection(t, got, dictionary.KindTerm, [2]int{terms, len(got)})
	if n, want := strings.Count(got, "<dt id="), len(dictionaryEntries(t)); n != want {
		t.Errorf("want %d entries on the page, got %d", want, n)
	}
}

// wantSection fails t unless every entry of the kind is on the page between the
// offsets span holds, from and to.
func wantSection(t *testing.T, got, kind string, span [2]int) {
	t.Helper()
	for _, e := range dictionarySection(t, kind) {
		wantEntry(t, got, e)
		if where := strings.Index(got, `<dt id="`+e.Anchor()+`">`); where < span[0] || where >= span[1] {
			t.Errorf("%s %q is in the wrong section", kind, e.Name)
		}
	}
}

// wantEntry fails t unless the page has the entry's anchor, heading,
// definition and source.
func wantEntry(t *testing.T, got string, e dictionary.Entry) {
	t.Helper()
	wantAll(t, "dictionary.html", got, `<dt id="`+e.Anchor()+`">`+html.EscapeString(e.Heading())+`</dt>`,
		"<dd>"+html.EscapeString(e.Definition)+"</dd>", "<dd>From: "+html.EscapeString(e.From)+"</dd>")
}

func dictionarySection(t *testing.T, kind string) []dictionary.Entry {
	t.Helper()
	section, err := dictionary.Section(kind)
	if err != nil || len(section) == 0 {
		t.Fatalf("Section(%s) = %d entries, %v", kind, len(section), err)
	}
	return section
}

func dictionaryEntries(t *testing.T) []dictionary.Entry {
	t.Helper()
	all, err := dictionary.Entries()
	if err != nil {
		t.Fatal(err)
	}
	return all
}
