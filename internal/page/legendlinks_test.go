package page

import (
	"bytes"
	"html"
	"regexp"
	"slices"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/dictionary"
)

// The legend links each entry it mentions to the Dictionary page (forsgren#370,
// step 3). The rule: the first mention of an entry in each section of the
// legend (each h2, and the text before the first) is a link, by the entry's
// labels, matched as whole words with the case the label is written in, the
// longest label first; a heading and a link are never linked inside.

var (
	linkFixture = []dictionary.Entry{
		{Name: "Lead time for changes", Kind: dictionary.KindNumber},
		{Name: "Issue lead time", Kind: dictionary.KindNumber, Shown: []string{"Lead time"}},
		{Name: "window", Kind: dictionary.KindTerm},
		{Name: "Report Start", Kind: dictionary.KindTerm, Shown: []string{"Report Start", "Report End"}},
	}
	// linkFixtureDoc has the shape of a page: head, main with two sections.
	linkFixtureDoc = `<title>window</title><main><h1>The window</h1>` +
		`<p>The window and the window again. Report End then Report Start. Lead time for changes, Lead time.</p>` +
		`<h2>The window</h2><p>Mid-window <a href="x.html">the window</a> and the window, Lead time.</p>` +
		`<h2>Other</h2><p>Nothing. A windowed thing, and window-based.</p></main><p>window</p>`
)

func TestLinkEntriesLinksTheFirstMentionPerSection(t *testing.T) {
	got := linkEntries(linkFixtureDoc, "", linkFixture)
	want := `<title>window</title><main><h1>The window</h1>` +
		`<p>The <a href="dictionary.html#window">window</a> and the window again. ` +
		`<a href="dictionary.html#report-start">Report End</a> then Report Start. ` +
		`<a href="dictionary.html#lead-time-for-changes">Lead time for changes</a>, ` +
		`<a href="dictionary.html#issue-lead-time">Lead time</a>.</p>` +
		`<h2>The window</h2><p>Mid-window <a href="x.html">the window</a> and the ` +
		`<a href="dictionary.html#window">window</a>, ` +
		`<a href="dictionary.html#issue-lead-time">Lead time</a>.</p>` +
		`<h2>Other</h2><p>Nothing. A windowed thing, and window-based.</p></main><p>window</p>`
	if got != want {
		t.Errorf("linkEntries:\n got %s\nwant %s", got, want)
	}
}

func TestLinkEntriesPrefixesTheBase(t *testing.T) {
	got := linkEntries("<main><p>the window</p></main>", "../", linkFixture)
	if want := `<main><p>the <a href="../dictionary.html#window">window</a></p></main>`; got != want {
		t.Errorf("linkEntries with a base:\n got %s\nwant %s", got, want)
	}
}

// A "<" with no ">" after it is text, not a tag.
func TestLinkEntriesReadsALoneLessThanSignAsText(t *testing.T) {
	got := linkEntries("<main><p>1 < 2 the window", "", linkFixture)
	if want := `<main><p>1 < 2 the <a href="dictionary.html#window">window</a>`; got != want {
		t.Errorf("linkEntries:\n got %s\nwant %s", got, want)
	}
}

// entryLink is a link to an entry of the Dictionary page; its text is $1.
// The wording tests read the legend without them (rendered).
var entryLink = regexp.MustCompile(`<a href="(?:\.\./)?dictionary\.html#[^"]*">(.*?)</a>`)

var (
	dictionaryHref = regexp.MustCompile(`href="dictionary\.html#([^"]*)"`)
	headingOrLink  = regexp.MustCompile(`(?s)<h[1-6][^>]*>.*?</h[1-6]>|<a [^>]*>.*?</a>`)
	anyTag         = regexp.MustCompile(`<[^>]*>`)
	headingTag     = regexp.MustCompile(`(?s)<h[1-6][^>]*>.*?</h[1-6]>`)
	nested         = regexp.MustCompile(`<a [^>]*>[^<]*<a `)
)

// legendSections are the legend's sections, each h2 starting one, as HTML.
func legendSections(t *testing.T) []string {
	t.Helper()
	var page bytes.Buffer
	if err := Render(&page, "legend.html", viewData()); err != nil {
		t.Fatalf("Render legend.html: %v", err)
	}
	got := page.String()
	_, main, _ := strings.Cut(got, "<main>")
	main, _, _ = strings.Cut(main, "</main>")
	parts := strings.Split(main, "<h2")
	for i := 1; i < len(parts); i++ {
		parts[i] = "<h2" + parts[i]
	}
	return parts
}

func TestLegendLinksPointAtAnchorsOfTheDictionaryPage(t *testing.T) {
	page := rendered(t, "dictionary.html", viewData())
	all := strings.Join(legendSections(t), "")
	found := dictionaryHref.FindAllStringSubmatch(all, -1)
	if len(found) < 10 {
		t.Fatalf("want the legend to link many entries, got %d links", len(found))
	}
	for _, link := range found {
		if !strings.Contains(page, `<dt id="`+link[1]+`">`) {
			t.Errorf("legend links dictionary.html#%s, which the Dictionary page lacks", link[1])
		}
	}
	if heading := headingWithLink(all); heading != "" {
		t.Errorf("want no link inside a heading, got %s", heading)
	}
	if nested.MatchString(all) {
		t.Error("want no link inside a link")
	}
}

// headingWithLink is the first heading of doc that holds a link, or "".
func headingWithLink(doc string) string {
	for _, heading := range headingTag.FindAllString(doc, -1) {
		if strings.Contains(heading, "<a ") {
			return heading
		}
	}
	return ""
}

// mentioned are the anchors of the entries the section's text names: outside
// headings and links, a label as a whole word, a longer label of another
// entry taking its words first.
func mentioned(section string, entries []dictionary.Entry) []string {
	text := entryLink.ReplaceAllString(section, "$1")
	text = html.UnescapeString(anyTag.ReplaceAllString(headingOrLink.ReplaceAllString(text, " "), " "))
	var found []string
	for _, l := range labelsLongestFirst(entries) {
		var taken bool
		text, taken = takeWord(text, l[0])
		if taken && !slices.Contains(found, l[1]) {
			found = append(found, l[1])
		}
	}
	return found
}

// labelsLongestFirst are the labels of the entries with their anchors, as
// pairs of label and anchor, the longest label first.
func labelsLongestFirst(entries []dictionary.Entry) [][2]string {
	var labels [][2]string
	for _, e := range entries {
		for _, l := range e.Labels() {
			labels = append(labels, [2]string{l, e.Anchor()})
		}
	}
	slices.SortStableFunc(labels, func(a, b [2]string) int { return len(b[0]) - len(a[0]) })
	return labels
}

// takeWord is text with every whole-word occurrence of the label blanked, and
// whether there was one.
func takeWord(text, label string) (string, bool) {
	word := regexp.MustCompile(`(^|[^\p{L}\p{N}_-])` + regexp.QuoteMeta(label) + `($|[^\p{L}\p{N}_-])`)
	taken := false
	for word.MatchString(text) {
		taken = true
		text = word.ReplaceAllString(text, "$1 $2")
	}
	return text, taken
}

func TestLegendSectionsLinkEveryEntryTheyMentionOnce(t *testing.T) {
	entries := dictionaryEntries(t)
	for i, section := range legendSections(t) {
		want := mentioned(section, entries)
		if i == 0 && len(want) == 0 {
			t.Error("want the legend's opening to mention entries")
		}
		wantLinkedOnce(t, i, section, want)
	}
}

// wantLinkedOnce fails t unless the section links each anchor of want once and
// links no other.
func wantLinkedOnce(t *testing.T, i int, section string, want []string) {
	t.Helper()
	got := map[string]int{}
	for _, link := range dictionaryHref.FindAllStringSubmatch(section, -1) {
		got[link[1]]++
	}
	for _, anchor := range want {
		if got[anchor] != 1 {
			t.Errorf("section %d mentions %s: want one link, got %d", i, anchor, got[anchor])
		}
		delete(got, anchor)
	}
	for anchor, n := range got {
		t.Errorf("section %d links %s (%d) without mentioning it", i, anchor, n)
	}
}
