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
	out := starterOut(t)
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
	sources := map[string]string{
		"fence": "# T\n\n```\ncode\n```\n", "headless": "just words\n", "bare": "# T\n", "good": "# T\n\nA paragraph.\n",
	}
	path := writeReadmes(t, dir, sources)
	fence, headless, bare, good := path["fence"], path["headless"], path["bare"], path["good"]
	cases := []struct {
		name   string
		args   []string
		code   int
		stderr string
	}{
		{"no --out", []string{"--readme", good}, 2, "--out <dir> is required"},
		{"an unknown flag", []string{"--nope"}, 2, "flag provided but not defined"},
		{"a missing README", []string{"--readme", filepath.Join(dir, "gone.md"), "--out", dir}, 1, "gone.md"},
		{"a construct outside the subset", []string{"--readme", fence, "--out", dir}, 1, "fence.md:3: unsupported Markdown"},
		{"a README with no heading", []string{"--readme", headless, "--out", dir}, 1, "headless.md: the README has no"},
		{"a README with no paragraph", []string{"--readme", bare, "--out", dir}, 1,
			"bare.md: the README has no paragraph: its first paragraph is the page's description"},
		{"an --out that is a file", []string{"--readme", good, "--out", good}, 1, "good.md"},
	}
	for _, c := range cases {
		var stderr bytes.Buffer
		if code := run(c.args, &stderr); code != c.code || !strings.Contains(stderr.String(), c.stderr) {
			t.Errorf("%s: want exit %d with %q on stderr, got exit %d and %q", c.name, c.code, c.stderr, code, stderr.String())
		}
	}
}

// writeReadmes writes each source, by name, to <dir>/<name>.md, and returns
// the paths by name.
func writeReadmes(t *testing.T, dir string, sources map[string]string) map[string]string {
	t.Helper()
	path := map[string]string{}
	for name, src := range sources {
		path[name] = filepath.Join(dir, name+".md")
		if err := os.WriteFile(path[name], []byte(src), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	return path
}

// starterOut is the directory the starter page of the repository's README was
// written to.
func starterOut(t *testing.T) string {
	t.Helper()
	out := filepath.Join(t.TempDir(), "starter")
	var stderr bytes.Buffer
	if code := run([]string{"--readme", "../../README.md", "--out", out}, &stderr); code != 0 {
		t.Fatalf("want exit 0, got %d: %s", code, stderr.String())
	}
	return out
}

// TestRunStylesTheStarterPageWithTheSitesStylesheet (forsgren#132): the page
// links styles.css, and styles.css next to it is the one stylesheet the
// metrics site is styled with, so the project page looks like the page it
// describes (colour scheme, width, phone layout) with no stylesheet of its
// own.
func TestRunStylesTheStarterPageWithTheSitesStylesheet(t *testing.T) {
	wantSiteFile(t, "styles.css", `<link rel="stylesheet" href="styles.css">`)
}

// TestRunGivesTheStarterPageTheSitesFavicon (forsgren#218): the starter page has
// its own head, so it links favicon.svg itself, and the site's icon is written
// next to it.
func TestRunGivesTheStarterPageTheSitesFavicon(t *testing.T) {
	wantSiteFile(t, "favicon.svg", `<link rel="icon" href="favicon.svg" type="image/svg+xml">`)
}

// wantSiteFile fails unless the starter page holds link and the file name next
// to it is the site's own, as internal/page embeds it.
func wantSiteFile(t *testing.T, name, link string) {
	t.Helper()
	out := starterOut(t)
	if page := mustRead(t, filepath.Join(out, "index.html")); !bytes.Contains(page, []byte(link)) {
		t.Errorf("the page does not hold %s:\n%s", link, page)
	}
	got := mustRead(t, filepath.Join(out, name))
	if want := mustRead(t, "../../internal/page/"+name); !bytes.Equal(got, want) {
		t.Errorf("%s is not the site's own (%d bytes, want %d)", name, len(got), len(want))
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
