package main

import (
	"os"
	"path/filepath"
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

// modePages are the four pages with a page key (forsgren#159, #55, #68, #200).
var modePages = []modePage{
	{"issues_page", "issues.html", "issues.html", config.PageOn},
	{"days_page", "days.html", "days.html", config.PageOff},
	{"history_page", "history.html", "history.html", config.PageUnlisted},
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

// TestRenderRemovesAPageWhoseKeyBecomesFalse (forsgren#159, #199, #200): an
// out dir that holds a page of an earlier run with its key true loses it when
// the key is false, and keeps it, unlisted, when the key is unlisted.
func TestRenderRemovesAPageWhoseKeyBecomesFalse(t *testing.T) {
	for _, p := range modePages {
		t.Run(p.key, func(t *testing.T) {
			dir := filepath.Join(t.TempDir(), "site")
			for _, mode := range []config.PageMode{config.PageOn, config.PageUnlisted, config.PageOff} {
				args := []string{"render", "--out", dir, "--config", writeConfig(t, validConfig+p.key+": "+string(mode)+"\n")}
				if code, _, stderr := runCommand(args...); code != 0 {
					t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
				}
				wantMode(t, dir, p, mode)
			}
		})
	}
}
