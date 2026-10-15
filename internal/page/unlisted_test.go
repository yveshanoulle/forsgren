package page

import (
	"os"
	"path/filepath"
	"regexp"
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
