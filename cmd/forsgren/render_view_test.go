package main

import (
	"strings"
	"testing"
)

// rootSwitch is the view switch on the root page: its links are relative to
// the root, the current view plain text.
var rootSwitch = map[string]string{
	"standard": `View: <span aria-current="page">standard</span> · <a href="numbers/">numbers</a>`,
	"numbers":  `View: <a href="standard/">standard</a> · <span aria-current="page">numbers</span>`,
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
// is that view, with the switch and the root's own links.
func TestRenderRootFollowsTheConfigView(t *testing.T) {
	for view, want := range rootSwitch {
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
// switch and no aria-current: an existing installation sees no change until
// it opts in.
func TestRenderRootWithoutAViewIsUnchanged(t *testing.T) {
	index := renderRoot(t, "")
	for _, text := range []string{"View:", "aria-current"} {
		if strings.Contains(index, text) {
			t.Errorf("want no %q on the root page without view:, got:\n%s", text, index)
		}
	}
	if !strings.Contains(index, "Between once") {
		t.Errorf("want the standard cells on the root page without view:, got:\n%s", index)
	}
}
