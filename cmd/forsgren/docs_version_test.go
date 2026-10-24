package main

import (
	"fmt"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// runningVersionString finds the places where a doc names the running
// version: the page footer ("Forsgren 1.3.0", capital F) and the setup issue
// title ("forsgren 1.3.0 needs more configuration"). The docs write
// <version> there (forsgren#237).
var runningVersionString = regexp.MustCompile(
	`Forsgren \d+\.\d+\.\d+|forsgren \d+\.\d+\.\d+ needs more configuration`)

// historyPhrase ends the text before a version that is history, not the
// running version: "since 1.3.0", "from 1.3.0", "in 1.3.0", "upgrading to
// 1.3.0", "until 1.3.0". It is the only place a doc may name the released
// version.
var historyPhrase = regexp.MustCompile(`(?i)\b(since|from|in|upgrading to|until) $`)

// docText is a doc with its lines joined by single spaces, so a phrase wrapped
// over two lines is one, and where each word came from.
type docText struct {
	text   string
	starts []int
	lines  []int
}

func docTextOf(text string) docText {
	var d docText
	var b strings.Builder
	for n, line := range strings.Split(text, "\n") {
		for _, word := range strings.Fields(line) {
			d.starts = append(d.starts, b.Len())
			d.lines = append(d.lines, n+1)
			b.WriteString(word + " ")
		}
	}
	d.text = b.String()
	return d
}

// lineAt is the line of the word that holds offset.
func (d docText) lineAt(offset int) int {
	i := sort.Search(len(d.starts), func(i int) bool { return d.starts[i] > offset })
	if i == 0 {
		return 1
	}
	return d.lines[i-1]
}

// namesRunningVersion lists, as "<name>:<line>: <snippet>", every place text
// names the running version: a running-version string with any X.Y.Z, and the
// released version anywhere but after a history phrase.
func namesRunningVersion(name, text, released string) []string {
	d := docTextOf(text)
	var found []string
	for _, m := range runningVersionString.FindAllStringIndex(d.text, -1) {
		found = append(found, fmt.Sprintf("%s:%d: %q", name, d.lineAt(m[0]), d.text[m[0]:m[1]]))
	}
	if released == "" {
		return found
	}
	released = `(^|[^0-9.])(` + regexp.QuoteMeta(released) + `)($|[^0-9]|\.($|[^0-9]))`
	for _, m := range regexp.MustCompile(released).FindAllStringSubmatchIndex(d.text, -1) {
		if !historyPhrase.MatchString(d.text[:m[4]]) {
			found = append(found, fmt.Sprintf("%s:%d: the released version %q outside a history phrase",
				name, d.lineAt(m[4]), d.text[m[4]:m[5]]))
		}
	}
	return found
}

func TestRunningVersionRuleSeesTheRunningVersionNotHistory(t *testing.T) {
	text := "footer says \"Forsgren 1.2.9\", title \"forsgren\n1.2.8 needs more configuration\"; " +
		"runs 1.2.9 now; since 1.2.9 a note; Upgrading to 1.2.9; From 1.3.0 an installation; " +
		"v0.8.7 to v1.0.0; forsgren 0.5.0; \"Forsgren <version>\"."
	got := strings.Join(namesRunningVersion("a.md", text, "1.2.9"), " | ")
	for _, want := range []string{`a.md:1: "Forsgren 1.2.9"`, `a.md:1: "forsgren 1.2.8 needs more configuration"`,
		`a.md:2: the released version "1.2.9" outside a history phrase`} {
		if !strings.Contains(got, want) {
			t.Errorf("want %q among the findings, got %s", want, got)
		}
	}
	if n := strings.Count(got, " | ") + 1; n != 4 {
		t.Errorf("want 4 findings (since, upgrading to, from and the placeholder are history), got %d: %s", n, got)
	}
}

// docFiles is README.md and every Markdown file in docs/, from this package.
func docFiles(t *testing.T) []string {
	t.Helper()
	files, err := filepath.Glob("../../docs/*.md")
	if err != nil {
		t.Fatal(err)
	}
	return append(files, "../../README.md")
}

// TestDocsNameNoRunningVersion (forsgren#237, ruling Q4): no doc names the
// running version, so a release rewrites no doc. Since forsgren#340 no file
// holds the released version, so only the running-version strings are looked
// for.
func TestDocsNameNoRunningVersion(t *testing.T) {
	for _, file := range docFiles(t) {
		name := strings.TrimPrefix(file, "../../")
		for _, found := range namesRunningVersion(name, readFile(t, file), "") {
			t.Errorf("%s: write <version>, not the version of the day", found)
		}
	}
}

// docsKeepingAPlaceholder is how many <version> placeholders each doc holds
// today; a file with fewer fails, so a reworded doc cannot make the pin
// vacuous. Raise the number when a doc gains one.
var docsKeepingAPlaceholder = map[string]int{
	"docs/configuration.md":         2,
	"docs/ci.md":                    1,
	"docs/pages-and-views.md":       2,
	"docs/updating-and-releases.md": 1,
}

func TestDocsKeepTheirVersionPlaceholders(t *testing.T) {
	for name, want := range docsKeepingAPlaceholder {
		if got := strings.Count(readFile(t, "../../"+name), "<version>"); got < want {
			t.Errorf("%s holds %d <version> placeholders, want at least %d", name, got, want)
		}
	}
}
