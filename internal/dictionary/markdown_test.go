package dictionary

import (
	"flag"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// update rewrites docs/dictionary.md from dictionary.yml:
// go test ./internal/dictionary -run TestDocsDictionaryIsTheGeneratedMarkdown -update
var update = flag.Bool("update", false, "rewrite docs/dictionary.md from dictionary.yml")

// docsDictionary is the committed docs/dictionary.md, from this package.
var docsDictionary = filepath.Join("..", "..", "docs", "dictionary.md")

// markdown is Markdown, failing the test on an error.
func markdown(t *testing.T) string {
	t.Helper()
	got, err := Markdown()
	if err != nil {
		t.Fatal(err)
	}
	return got
}

// TestMarkdownOpensWithTheGeneratedWarning (forsgren#578): the file says it is
// generated, from which file and how, before anything else.
func TestMarkdownOpensWithTheGeneratedWarning(t *testing.T) {
	got := markdown(t)
	first, _, _ := strings.Cut(got, "\n")
	for _, want := range []string{"Generated", "internal/dictionary/dictionary.yml", "do not edit", "-update"} {
		if !strings.Contains(first, want) {
			t.Errorf("want the first line to say %q, got %q", want, first)
		}
	}
	if !strings.Contains(got, "\n# Dictionary\n") {
		t.Errorf("want the heading # Dictionary, got:\n%s", got)
	}
}

// TestMarkdownListsTermsThenNumbersInTheOrderOfThePage: the Terms section,
// then the Numbers section, each entry once under its section's heading, in
// the order dictionary.Section gives the Dictionary page (alphabetical).
func TestMarkdownListsTermsThenNumbersInTheOrderOfThePage(t *testing.T) {
	got := markdown(t)
	terms, numbers := strings.Index(got, "\n## Terms\n"), strings.Index(got, "\n## Numbers\n")
	if terms < 0 || numbers < terms {
		t.Fatalf("want ## Terms before ## Numbers, got %d and %d", terms, numbers)
	}
	wantHeadingsInOrder(t, got[terms:numbers], KindTerm)
	wantHeadingsInOrder(t, got[numbers:], KindNumber)
}

// wantHeadingsInOrder fails unless part holds a ### heading for every entry of
// kind, in Section's order, and no other.
func wantHeadingsInOrder(t *testing.T, part, kind string) {
	t.Helper()
	section, err := Section(kind)
	if err != nil {
		t.Fatal(err)
	}
	headings := entryHeadings(part)
	if len(headings) != len(section) {
		t.Fatalf("%s: want %d headings, got %d", kind, len(section), len(headings))
	}
	for i, e := range section {
		if headings[i] != markdownText(e.Heading()) {
			t.Errorf("%s heading %d: want %q, got %q", kind, i, markdownText(e.Heading()), headings[i])
		}
	}
}

// entryHeadings are the ### headings of part, in order.
func entryHeadings(part string) []string {
	var headings []string
	for _, line := range strings.Split(part, "\n") {
		if heading, ok := strings.CutPrefix(line, "### "); ok {
			headings = append(headings, heading)
		}
	}
	return headings
}

// TestMarkdownHoldsEveryEntryAsThePageDoes: each entry's heading, definition
// and From line, as dictionary.html shows them.
func TestMarkdownHoldsEveryEntryAsThePageDoes(t *testing.T) {
	got := markdown(t)
	for _, e := range entries(t) {
		want := "### " + markdownText(e.Heading()) + "\n\n" + markdownText(e.Definition) +
			"\n\nFrom: " + markdownText(e.From) + "\n"
		if !strings.Contains(got, want) {
			t.Errorf("%q: want its entry\n%s", e.Name, want)
		}
	}
}

// TestMarkdownTextEscapesWhatMarkdownWouldRead: a definition's [bot] or
// dora_days reads as written, never as a link or emphasis.
func TestMarkdownTextEscapesWhatMarkdownWouldRead(t *testing.T) {
	cases := map[string]string{
		"ends in [bot]": `ends in \[bot\]`,
		"dora_days":     `dora\_days`,
		"a * b":         `a \* b`,
		"<b> `x`":       "\\<b\\> \\`x\\`",
		`a\b`:           `a\\b`,
		"plain words":   "plain words",
	}
	for in, want := range cases {
		if got := markdownText(in); got != want {
			t.Errorf("markdownText(%q) = %q, want %q", in, got, want)
		}
	}
}

// TestDocsDictionaryIsTheGeneratedMarkdown: the committed docs/dictionary.md
// is Markdown() byte for byte, so a change to dictionary.yml without the
// regenerated file, or a hand edit of the file, is red (in FBP and CI).
func TestDocsDictionaryIsTheGeneratedMarkdown(t *testing.T) {
	want := markdown(t)
	if *update {
		if err := os.WriteFile(docsDictionary, []byte(want), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	got, err := os.ReadFile(filepath.Clean(docsDictionary))
	if err != nil {
		t.Fatalf("read %s: %v (generate it with -update)", docsDictionary, err)
	}
	if string(got) != want {
		t.Errorf("%s differs from dictionary.yml: regenerate it with "+
			"go test ./internal/dictionary -run TestDocsDictionaryIsTheGeneratedMarkdown -update", docsDictionary)
	}
}
