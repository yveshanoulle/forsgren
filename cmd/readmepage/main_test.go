package main

import (
	"bytes"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// TestRunRendersTheRealReadmeToTheStarterPage (forsgren#132): the README of
// this repository becomes index.html, titled forsgren, with its five metric
// links and the live example as absolute links and no relative href left.
func TestRunRendersTheRealReadmeToTheStarterPage(t *testing.T) {
	out := filepath.Join(t.TempDir(), "starter")
	var stderr bytes.Buffer
	if code := run([]string{"--readme", "../../README.md", "--out", out}, &stderr); code != 0 {
		t.Fatalf("want exit 0, got %d: %s", code, stderr.String())
	}
	raw, err := os.ReadFile(filepath.Clean(filepath.Join(out, "index.html")))
	if err != nil {
		t.Fatalf("the page is not written: %v", err)
	}
	page := string(raw)
	for _, want := range wantedFromTheReadme() {
		if !strings.Contains(page, want) {
			t.Errorf("the page lacks %q", want)
		}
	}
	for _, href := range notAbsolute(page) {
		t.Errorf("a href that is not an absolute https link: %q", href)
	}
}

// notAbsolute are the hrefs of page that do not start with https://.
func notAbsolute(page string) []string {
	var bad []string
	for _, href := range regexp.MustCompile(`<a href="([^"]*)"`).FindAllStringSubmatch(page, -1) {
		if !strings.HasPrefix(href[1], "https://") {
			bad = append(bad, href[1])
		}
	}
	return bad
}

// wantedFromTheReadme is what the starter page must show of the README: its
// title and heading, the live example, and one absolute link into the
// reference for each of the five metrics.
func wantedFromTheReadme() []string {
	const metrics = "https://github.com/yveshanoulle/forsgren/blob/main/docs/pages-and-views.md#"
	wants := []string{
		"<title>forsgren</title>", `<h1 id="forsgren">forsgren</h1>`,
		`<a href="https://forsgren.forsgren.be">`,
	}
	for _, anchor := range []string{
		"deployment-frequency", "lead-time-for-changes", "failed-deployment-recovery-time",
		"change-fail-rate", "deployment-rework-rate",
	} {
		wants = append(wants, `<a href="`+metrics+anchor+`">`)
	}
	return wants
}

// TestRunFailsLoudOnBadInput (forsgren#132): a missing --out is a usage
// error (exit 2), and a README that is missing, outside the renderer's
// subset, or cannot be written to is a failure (exit 1); each says why on
// stderr, and none leaves a page behind.
func TestRunFailsLoudOnBadInput(t *testing.T) {
	dir := t.TempDir()
	fence := filepath.Join(dir, "fence.md")
	if err := os.WriteFile(fence, []byte("# T\n\n```\ncode\n```\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	good := filepath.Join(dir, "good.md")
	if err := os.WriteFile(good, []byte("# T\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	cases := []struct {
		name   string
		args   []string
		code   int
		stderr string
	}{
		{"no --out", []string{"--readme", good}, 2, "--out <dir> is required"},
		{"an unknown flag", []string{"--nope"}, 2, "flag provided but not defined"},
		{"a missing README", []string{"--readme", filepath.Join(dir, "gone.md"), "--out", dir}, 1, "gone.md"},
		{"a construct outside the subset", []string{"--readme", fence, "--out", dir}, 1, "fence.md: unsupported Markdown"},
		{"an --out that is a file", []string{"--readme", good, "--out", good}, 1, "good.md"},
	}
	for _, c := range cases {
		var stderr bytes.Buffer
		if code := run(c.args, &stderr); code != c.code || !strings.Contains(stderr.String(), c.stderr) {
			t.Errorf("%s: want exit %d with %q on stderr, got exit %d and %q", c.name, c.code, c.stderr, code, stderr.String())
		}
	}
}

// TestRunStylesTheStarterPageWithTheSitesStylesheet (forsgren#132): the page
// links styles.css, and styles.css next to it is the one stylesheet the
// metrics site is styled with, so the project page looks like the page it
// describes (colour scheme, width, phone layout) with no stylesheet of its
// own.
func TestRunStylesTheStarterPageWithTheSitesStylesheet(t *testing.T) {
	out := filepath.Join(t.TempDir(), "starter")
	var stderr bytes.Buffer
	if code := run([]string{"--readme", "../../README.md", "--out", out}, &stderr); code != 0 {
		t.Fatalf("want exit 0, got %d: %s", code, stderr.String())
	}
	page := mustRead(t, filepath.Join(out, "index.html"))
	if !bytes.Contains(page, []byte(`<link rel="stylesheet" href="styles.css">`)) {
		t.Errorf("the page does not link styles.css:\n%s", page)
	}
	got := mustRead(t, filepath.Join(out, "styles.css"))
	if want := mustRead(t, "../../internal/page/styles.css"); !bytes.Equal(got, want) {
		t.Errorf("styles.css is not the site's stylesheet (%d bytes, want %d)", len(got), len(want))
	}
}

// mustRead is the file at path, or a fatal test failure naming it.
func mustRead(t *testing.T, path string) []byte {
	t.Helper()
	raw, err := os.ReadFile(filepath.Clean(path))
	if err != nil {
		t.Fatalf("cannot read %s: %v", path, err)
	}
	return raw
}
