package page

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// menuOf is the menu, the nav of the views, of a rendered page.
func menuOf(t *testing.T, name, html string) string {
	t.Helper()
	menu := regexp.MustCompile(`(?s)<nav class="views">.*?</nav>`).FindString(html)
	if menu == "" {
		t.Fatalf("%s: want a menu, got:\n%s", name, html)
	}
	return menu
}

// TestAnUnlistedRootPageIsWrittenWithoutAMenuEntry (forsgren#200): a root page
// the site lists as unlisted is written and counted, no page's menu has an
// entry for it, its own menu neither lists nor marks it, and the other
// entries stay. Its own page has no aria-current="page" at all, as no entry
// stands for it.
func TestAnUnlistedRootPageIsWrittenWithoutAMenuEntry(t *testing.T) {
	cases := map[string]menuEntry{
		"issues": {"issues.html", "Issues"}, "days": {"days.html", "Daily"}, "history": {"history.html", "History"},
	}
	for name, entry := range cases {
		t.Run(name, func(t *testing.T) {
			data := viewData()
			data.Unlisted = map[string]bool{name: true}
			wantWrittenUnlisted(t, data, entry)
		})
	}
}

// wantWrittenUnlisted fails t unless the site of data writes every page,
// among them the one of entry, and no menu has an entry for it, its own
// neither listing nor marking it.
func wantWrittenUnlisted(t *testing.T, data Data, entry menuEntry) {
	t.Helper()
	dir := t.TempDir()
	if n, err := WriteSite(dir, data); err != nil || n != len(PageNames()) {
		t.Fatalf("want all %d pages written and no error, got %d, %v", len(PageNames()), n, err)
	}
	if _, err := os.Stat(filepath.Join(dir, entry.href)); err != nil {
		t.Fatalf("want %s written, got %v", entry.href, err)
	}
	for _, page := range []string{"index.html", "scoring/index.html", "legend.html", entry.href} {
		wantNoEntry(t, page, rendered(t, page, data), entry)
	}
	wantNone(t, entry.href+" menu", menuOf(t, entry.href, rendered(t, entry.href, data)), `aria-current="page"`)
}

// wantNoEntry fails t unless the menu of the rendered page has no entry for
// the page of entry, and still has the others.
func wantNoEntry(t *testing.T, page, html string, entry menuEntry) {
	t.Helper()
	menu := menuOf(t, page, html)
	wantNone(t, page+" menu", menu, entry.href+`"`, ">"+entry.label+"<")
	wantAll(t, page+" menu", menu, "Standard", "Numbers and scoring")
}

// noindex is the tag that asks search engines to skip a page (forsgren#200).
const noindex = `<meta name="robots" content="noindex">`

// TestAnUnlistedRootPageAsksSearchEnginesToSkipIt (forsgren#200): the head of an
// unlisted root page carries the robots noindex tag, and the head of every
// other page of the site, the unlisted page's neighbours and a page that is
// listed, does not.
func TestAnUnlistedRootPageAsksSearchEnginesToSkipIt(t *testing.T) {
	for _, unlisted := range []string{"issues", "days", "history"} {
		t.Run(unlisted, func(t *testing.T) {
			data := viewData()
			data.Unlisted = map[string]bool{unlisted: true}
			for _, page := range PageNames() {
				head, _, _ := strings.Cut(rendered(t, page, data), "</head>")
				if got, want := strings.Contains(head, noindex), page == unlisted+".html"; got != want {
					t.Errorf("%s: want the noindex tag in the head: %v, got %v", page, want, got)
				}
			}
		})
	}
}
