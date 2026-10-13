package main

import (
	"strings"
	"testing"
)

// rootMenu is the menu on the root page: its links are relative to
// the root, the current view plain text marked aria-current="true", as the
// root is not that view's page (Yves's ruling, forsgren#46).
var rootMenu = map[string]string{
	"standard": `View: <span aria-current="true">Standard</span> · <a href="numbers/">Numbers</a>`,
	"numbers":  `View: <a href="standard/">Standard</a> · <span aria-current="true">Numbers</span>`,
}

// renderRoot renders the config with view (none when empty) over the
// history and returns the root page.
func renderRoot(t *testing.T, view string) string {
	t.Helper()
	pinNow(t)
	config := validConfig
	if view != "" {
		config = "view: " + view + "\n" + validConfig
	}
	code, stderr, index := renderWith(t, "--config", writeConfig(t, config), "--data", writeHistory(t, acmeHistory()))
	if code != 0 {
		t.Fatalf("view %q: want exit 0, got %d (stderr %q)", view, code, stderr)
	}
	return index
}

// TestRenderRootFollowsTheConfigView (forsgren#46): with view: the root page
// is that view, with the menu and the root's own links.
func TestRenderRootFollowsTheConfigView(t *testing.T) {
	for view, want := range rootMenu {
		index := renderRoot(t, view)
		for _, text := range []string{want, `href="styles.css"`, `href="legend.html"`} {
			if !strings.Contains(index, text) {
				t.Errorf("view %s: want %s on the root page, got:\n%s", view, text, index)
			}
		}
		if strings.Contains(index, "../") {
			t.Errorf("view %s: want no link above the root, got:\n%s", view, index)
		}
	}
}

// TestRenderRootOfTheNumbersViewShowsNumbers (forsgren#46): no band text.
func TestRenderRootOfTheNumbersViewShowsNumbers(t *testing.T) {
	index := renderRoot(t, "numbers")
	for _, band := range []string{"Between once", "Less than"} {
		if strings.Contains(index, band) {
			t.Errorf("want only numbers on the numbers root, got %q in:\n%s", band, index)
		}
	}
}

// TestRenderRootWithoutAViewIsUnchanged (forsgren#46): no view key, no
// aria-current: the root shows the standard cells, and its menu marks no
// view (forsgren#128).
func TestRenderRootWithoutAViewIsUnchanged(t *testing.T) {
	index := renderRoot(t, "")
	if strings.Contains(index, "aria-current") {
		t.Errorf("want no aria-current on the root page without view:, got:\n%s", index)
	}
	if !strings.Contains(index, "Between once") {
		t.Errorf("want the standard cells on the root page without view:, got:\n%s", index)
	}
}
