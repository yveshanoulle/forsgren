package dictionary

import (
	"html"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func TestParseRefusesWhatCannotBeRead(t *testing.T) {
	cases := map[string]string{
		"unknown key":   "- {name: A, kind: term, definition: d, from: f, extra: x}",
		"no name":       "- {kind: term, definition: d, from: f}",
		"unknown kind":  "- {name: A, kind: word, definition: d, from: f}",
		"no definition": "- {name: A, kind: term, from: f}",
		"no source":     "- {name: A, kind: number, definition: d}",
		"repeated name": "- {name: A, kind: term, definition: d, from: f}\n" +
			"- {name: a, kind: number, definition: d, from: f}",
		"not a list":      "name: A",
		"not yaml at all": "- [unclosed",
	}
	for name, text := range cases {
		if _, err := parse(text); err == nil {
			t.Errorf("%s: parse accepted %q", name, text)
		}
	}
}

func TestParseReadsEntriesAndTheirLabels(t *testing.T) {
	text := "- {name: A, kind: term, definition: d, from: f}\n" +
		"- {name: B, kind: number, shown: [b1, b2], definition: d, from: f}"
	got, err := parse(text)
	if err != nil || len(got) != 2 {
		t.Fatalf("parse = %v, %v; want two entries", got, err)
	}
	if l := got[0].Labels(); len(l) != 1 || l[0] != "A" {
		t.Errorf("labels of A = %v, want [A]", l)
	}
}

func TestShownLabelsReplaceTheName(t *testing.T) {
	got, err := parse("- {name: B, kind: number, shown: [b1, b2], definition: d, from: f}")
	if err != nil || len(got) != 1 {
		t.Fatalf("parse = %v, %v; want one entry", got, err)
	}
	if l := got[0].Labels(); len(l) != 2 || l[1] != "b2" {
		t.Errorf("labels of B = %v, want [b1 b2]", l)
	}
}

func TestParseOfNothingIsNoEntries(t *testing.T) {
	if none, err := parse(""); err != nil || len(none) != 0 {
		t.Errorf("parse of nothing = %v, %v; want no entries", none, err)
	}
}

// The pages are the golden pages of internal/page: the renderer's output for
// the fixtures, held equal to it by that package's tests. Their settings pages
// are left out, whose table lists configuration keys, not figures.
const goldens = "../page/testdata/*.golden.html"

var (
	tags    = regexp.MustCompile(`(?s)<[^>]*>`)
	heads   = regexp.MustCompile(`(?s)<th\b[^>]*scope="col(?:group)?"[^>]*>(.*?)</th>`)
	labels  = regexp.MustCompile(`aria-label="([^"]*)"`)
	periods = regexp.MustCompile(`^\d{4} H[12]$|^Last 6 months`)
	// notFigures are column heads that name no figure: the row key, the
	// period or date a row is for, the weekdays, and the history's measure
	// column.
	notFigures = map[string]bool{
		"project": true, "period": true, "date": true, "measure": true,
		"monday": true, "tuesday": true, "wednesday": true, "thursday": true,
		"friday": true, "saturday": true, "sunday": true,
	}
)

// shownPages returns the heads of the figures the pages show (the text of
// their column and column-group heads, lower case) and the text of all pages,
// which a reader or a screen reader meets: visible text and aria-labels.
func shownPages(t *testing.T) (map[string]bool, string) {
	t.Helper()
	figures := map[string]bool{}
	var text strings.Builder
	for _, page := range goldenPages(t) {
		for _, head := range figureHeads(page) {
			figures[head] = true
		}
		text.WriteString(textOf(page))
	}
	return figures, text.String()
}

// goldenPages reads the golden pages, the settings ones left out.
func goldenPages(t *testing.T) [][]byte {
	t.Helper()
	files, err := filepath.Glob(goldens)
	if err != nil || len(files) == 0 {
		t.Fatalf("no golden pages at %s: %v", goldens, err)
	}
	var pages [][]byte
	for _, f := range files {
		if strings.HasPrefix(filepath.Base(f), "settings.") {
			continue
		}
		page, err := os.ReadFile(filepath.Clean(f))
		if err != nil {
			t.Fatal(err)
		}
		pages = append(pages, page)
	}
	return pages
}

// figureHeads are the column and column-group heads of a page that name a
// figure, in lower case.
func figureHeads(page []byte) []string {
	var out []string
	for _, m := range heads.FindAllSubmatch(page, -1) {
		head := plain(string(m[1]))
		if !notFigures[strings.ToLower(head)] && !periods.MatchString(head) {
			out = append(out, strings.ToLower(head))
		}
	}
	return out
}

// textOf is the visible text of a page, then its aria-labels, a line each.
func textOf(page []byte) string {
	var text strings.Builder
	text.WriteString(plain(string(page)) + "\n")
	for _, m := range labels.FindAllSubmatch(page, -1) {
		text.WriteString(html.UnescapeString(string(m[1])) + "\n")
	}
	return text.String()
}

// plain is the text of markup: no tags, entities read, white space single.
func plain(markup string) string {
	return strings.Join(strings.Fields(html.UnescapeString(tags.ReplaceAllString(markup, " "))), " ")
}

func entries(t *testing.T) []Entry {
	t.Helper()
	all, err := Entries()
	if err != nil {
		t.Fatal(err)
	}
	return all
}

// TestEveryFigureThePagesShowHasAnEntry holds one way: each head of a figure
// that a page shows is a label of some entry.
func TestEveryFigureThePagesShowHasAnEntry(t *testing.T) {
	figures, _ := shownPages(t)
	labelled := labelsOf(entries(t))
	for head := range figures {
		if !labelled[head] {
			t.Errorf("the pages show %q and the dictionary has no entry for it", head)
		}
	}
}

// labelsOf is every label of the entries, in lower case.
func labelsOf(all []Entry) map[string]bool {
	labelled := map[string]bool{}
	for _, e := range all {
		for _, l := range e.Labels() {
			labelled[strings.ToLower(l)] = true
		}
	}
	return labelled
}

// TestEveryEntryNamesSomethingThePagesShow holds the other way: a number has
// a label that heads a figure on a page, a term has a label that the pages'
// text says.
func TestEveryEntryNamesSomethingThePagesShow(t *testing.T) {
	figures, text := shownPages(t)
	for _, e := range entries(t) {
		if !shows(e, figures, text) {
			t.Errorf("%s %q (labels %q) is shown on no page", e.Kind, e.Name, e.Labels())
		}
	}
}

// shows is whether a page shows one of the entry's labels.
func shows(e Entry, figures map[string]bool, text string) bool {
	for _, l := range e.Labels() {
		if e.Kind == KindNumber && figures[strings.ToLower(l)] {
			return true
		}
		if e.Kind == KindTerm && regexp.MustCompile(`(?i)\b`+regexp.QuoteMeta(l)+`\b`).MatchString(text) {
			return true
		}
	}
	return false
}

// TestTheTermsAReaderMeetsAreDefined names the terms the issue lists. A term
// is found by no rule in the pages, so these are asked for by name.
func TestTheTermsAReaderMeetsAreDefined(t *testing.T) {
	have := map[string]bool{}
	for _, e := range entries(t) {
		if e.Kind == KindTerm {
			have[strings.ToLower(e.Name)] = true
		}
	}
	for _, term := range []string{"trunk", "mainline", "TBD", "DORA", "lead time", "rework", "band", "window",
		"bot", "unknown author", "cut", "stand-in"} {
		if !have[strings.ToLower(term)] {
			t.Errorf("the dictionary has no term %q", term)
		}
	}
}
