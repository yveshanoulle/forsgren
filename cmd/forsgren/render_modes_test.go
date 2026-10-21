package main

import (
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// modePage is an optional page and its key: the file it is written to, the
// address its menu entry has, and the mode its key has when the config leaves
// the key out.
type modePage struct {
	key, file, href string
	def             config.PageMode
}

// modePages are the five pages with a page key (forsgren#159, #55, #68, #200, #253).
var modePages = []modePage{
	{"issues_page", "issues.html", "issues.html", config.PageOn},
	{"days_page", "days.html", "days.html", config.PageOff},
	{"history_page", "history.html", "history.html", config.PageUnlisted},
	{"tbd_page", "tbd.html", "tbd.html", config.PageUnlisted},
	{"numbers_scoring_page", "numbers-scoring/index.html", "numbers-scoring/", config.PageUnlisted},
}

// noindexTag is the tag an unlisted page carries in its head.
const noindexTag = `<meta name="robots" content="noindex">`

// wantMode fails t unless the page is in dir as its mode says: written unless
// the mode is false, in the menu of index.html only when the mode is true, and
// asking search engines to skip it only when the mode is unlisted.
func wantMode(t *testing.T, dir string, p modePage, mode config.PageMode) {
	t.Helper()
	html, err := os.ReadFile(filepath.Clean(filepath.Join(dir, p.file)))
	if written := err == nil; written != (mode != config.PageOff) {
		t.Errorf("%s: want %s written: %v, got %v", p.key, p.file, mode != config.PageOff, err)
	}
	head, _, _ := strings.Cut(string(html), "</head>")
	if got := strings.Contains(head, noindexTag); got != (mode == config.PageUnlisted) {
		t.Errorf("%s: want the noindex tag: %v, got %v", p.key, mode == config.PageUnlisted, got)
	}
	if got := strings.Contains(readSite(t, dir, "index.html"), `href="`+p.href+`"`); got != (mode == config.PageOn) {
		t.Errorf("%s: want the menu to link %s: %v, got %v", p.key, p.href, mode == config.PageOn, got)
	}
}

// TestRenderHandlesEachPageKeyByItsMode (forsgren#200): with --config, a page
// whose key is true is written and in the menu, unlisted is written with no
// menu entry and the noindex tag, and false is not written; a key left out, or
// not accepted, has its default (issues true, days false, history and numbers
// and scoring unlisted).
func TestRenderHandlesEachPageKeyByItsMode(t *testing.T) {
	for _, p := range modePages {
		for name, tc := range map[string]struct {
			line string
			want config.PageMode
		}{
			"absent": {"", p.def}, "true": {p.key + ": true\n", config.PageOn},
			"unlisted": {p.key + ": unlisted\n", config.PageUnlisted}, "false": {p.key + ": false\n", config.PageOff},
			"not accepted": {p.key + ": yes\n", p.def},
		} {
			t.Run(p.key+" "+name, func(t *testing.T) {
				dir := renderInto(t, "--config", writeConfig(t, validConfig+tc.line))
				wantMode(t, dir, p, tc.want)
			})
		}
	}
}

// TestRenderWithoutAConfigListsEveryPage (forsgren#200): without --config no
// page is hidden or unlisted.
func TestRenderWithoutAConfigListsEveryPage(t *testing.T) {
	dir := renderInto(t)
	for _, p := range modePages {
		wantMode(t, dir, p, config.PageOn)
	}
}

// TestRenderFollowsEachChangeOfAPageKeyInAReusedOutDir (forsgren#159, #199,
// #200): in one out dir reused across runs, a page follows its key at every
// change: true to false removes the file, unlisted to false removes it,
// unlisted to true gives the page its menu entry back and takes its noindex
// tag away, and true to unlisted does the reverse; the page is checked after
// each run for its file, its menu entry and its tag.
func TestRenderFollowsEachChangeOfAPageKeyInAReusedOutDir(t *testing.T) {
	on, unlisted, off := config.PageOn, config.PageUnlisted, config.PageOff
	for name, runs := range map[string][]config.PageMode{
		"true, unlisted, false": {on, unlisted, off}, "true, false": {on, off}, "unlisted, false": {unlisted, off},
		"unlisted, true": {unlisted, on}, "true, unlisted": {on, unlisted}, "false, unlisted, true": {off, unlisted, on},
	} {
		for _, p := range modePages {
			t.Run(p.key+": "+name, func(t *testing.T) {
				dir := filepath.Join(t.TempDir(), "site")
				for _, mode := range runs {
					renderModeInto(t, dir, p, mode)
					wantMode(t, dir, p, mode)
				}
			})
		}
	}
}

// renderModeInto renders into dir, which may hold an earlier run, with the
// page's key set to mode.
func renderModeInto(t *testing.T, dir string, p modePage, mode config.PageMode) {
	t.Helper()
	args := []string{"render", "--out", dir, "--config", writeConfig(t, validConfig+p.key+": "+string(mode)+"\n")}
	if code, _, stderr := runCommand(args...); code != 0 {
		t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
	}
}

// linkToAnOptionalPage finds a link to the history page or the numbers and
// scoring page, from the root or from a folder.
var linkToAnOptionalPage = regexp.MustCompile(`href="[^"]*(history\.html|tbd\.html|numbers-scoring/)`)

// TestNoGeneratedPageLinksToAnUnlistedPageOutsideTheMenu (forsgren#200): with
// the History and the Numbers and scoring page unlisted, no file the render
// writes links to either of them, from the menu or from anywhere else; set
// true, the same pages are linked, so the scan is not blind.
func TestNoGeneratedPageLinksToAnUnlistedPageOutsideTheMenu(t *testing.T) {
	for mode, wantLinks := range map[config.PageMode]bool{config.PageUnlisted: false, config.PageOn: true} {
		file := writeConfig(t, validConfig+daysOn+"history_page: "+string(mode)+"\ntbd_page: "+string(mode)+
			"\nnumbers_scoring_page: "+string(mode)+"\n")
		found := linksToOptionalPages(t, renderInto(t, "--config", file))
		if wantLinks != (len(found) > 0) {
			t.Errorf("%s: want links to the two pages: %v, got %v", mode, wantLinks, found)
		}
	}
}

// linksToOptionalPages are the links to the history page or the numbers and
// scoring page in every html file under dir, each as its file and the link.
func linksToOptionalPages(t *testing.T, dir string) []string {
	t.Helper()
	var found []string
	err := filepath.WalkDir(dir, func(path string, entry fs.DirEntry, err error) error {
		if err == nil && strings.HasSuffix(path, ".html") {
			if link := linkToAnOptionalPage.FindString(readFile(t, path)); link != "" {
				found = append(found, filepath.Base(filepath.Dir(path))+"/"+filepath.Base(path)+": "+link)
			}
		}
		return err
	})
	if err != nil {
		t.Fatal(err)
	}
	return found
}
