package main

import (
	"maps"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"
)

// runningVersionString finds the places where the docs name the running
// version, not a release in the past: the page footer ("Forsgren 1.3.0",
// capital F) and the setup issue title ("forsgren 1.3.0 needs more
// configuration"). Everything else with a version in it is history or an
// example ("From 1.3.0 ...", "v0.8.7 to v1.0.0", "forsgren 0.5.0") and is
// not matched.
var runningVersionString = regexp.MustCompile(
	`Forsgren (\d+\.\d+\.\d+)|forsgren (\d+\.\d+\.\d+) needs more configuration`)

// runningVersionsIn returns every running-version string in text, wrapped
// lines joined, as the version it names.
func runningVersionsIn(text string) []string {
	var found []string
	for _, m := range runningVersionString.FindAllStringSubmatch(strings.Join(strings.Fields(text), " "), -1) {
		found = append(found, m[1]+m[2])
	}
	return found
}

// docsNamingTheRunningVersion is how many running-version strings each file
// holds today; a file with fewer fails, so a reworded doc cannot make the
// pin vacuous. Raise the number when a doc gains one.
var docsNamingTheRunningVersion = map[string]int{
	"docs/configuration.md":         3,
	"docs/pages-and-views.md":       1,
	"docs/updating-and-releases.md": 1,
}

func TestRunningVersionRuleSeesStaleAndWrappedNotHistory(t *testing.T) {
	text := "footer says \"Forsgren 1.2.9\", title \"forsgren\n1.2.8 needs more configuration\"; " +
		"From 1.3.0 an installation; v0.8.7 to v1.0.0; forsgren 0.5.0; Upgrading to 1.3.0."
	got := strings.Join(runningVersionsIn(text), ",")
	if want := "1.2.9,1.2.8"; got != want {
		t.Fatalf("running versions = %q, want %q", got, want)
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

// runningVersionsInDocs is every running-version string of each doc file, by
// its name from the repository root.
func runningVersionsInDocs(t *testing.T) map[string][]string {
	t.Helper()
	found := map[string][]string{}
	for _, file := range docFiles(t) {
		name := strings.TrimPrefix(file, "../../")
		found[name] = append(found[name], runningVersionsIn(readFile(t, file))...)
	}
	return found
}

// TestDocsNameTheRunningVersion (forsgren#148, decision #170): every
// running-version string in the docs is `version`, the one source of the
// running version, and each file of docsNamingTheRunningVersion still holds
// its strings.
func TestDocsNameTheRunningVersion(t *testing.T) {
	found := runningVersionsInDocs(t)
	for _, name := range slices.Sorted(maps.Keys(found)) {
		for _, v := range found[name] {
			if v != releasedVersion {
				t.Errorf("%s says Forsgren %s, but version is %s: a release bump forgot it", name, v, releasedVersion)
			}
		}
	}
	for name, want := range docsNamingTheRunningVersion {
		if got := len(found[name]); got < want {
			t.Errorf("%s holds %d running-version strings, want at least %d", name, got, want)
		}
	}
}
