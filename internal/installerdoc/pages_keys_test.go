package installerdoc

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// starterPages are issues_page and days_page as forsgren's own starter loads
// them, written as the starter writes them (forsgren#159).
func starterPages(t *testing.T) (issues, days string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "forsgren.config.yml")
	if err := os.WriteFile(path, []byte(config.Starter), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg, err := config.Load(path)
	if err != nil {
		t.Fatalf("want the starter to load, got %v", err)
	}
	return "issues_page: " + string(cfg.IssuesPage), "days_page: " + string(cfg.DaysPage)
}

// TestDocsAndInstallerStateTheStartersPageKeys (forsgren#159): the agent
// installer's step 2 asks about the two pages with the starter's defaults, its
// step 9 example config writes both keys as the starter does, the
// configuration reference names both with their defaults, and the page
// reference says the pages can be hidden.
func TestDocsAndInstallerStateTheStartersPageKeys(t *testing.T) {
	issues, days := starterPages(t)
	cases := map[string]string{
		"agent-installer.md step 2":     section(t, installerFile, "Step 2."),
		"agent-installer.md step 9":     section(t, installerFile, "Step 9."),
		"docs/configuration.md":         readRepoFileAsOneLine(t, "docs/configuration.md"),
		"docs/pages-and-views.md":       readRepoFileAsOneLine(t, "docs/pages-and-views.md"),
		"docs/updating-and-releases.md": readRepoFileAsOneLine(t, "docs/updating-and-releases.md"),
	}
	for name, text := range cases {
		for _, want := range []string{issues, days} {
			if !strings.Contains(asOneLine(text), want) {
				t.Errorf("%s does not state %q, the starter's value", name, want)
			}
		}
	}
}

// TestNewInstallationsStartWithTheIssuesPageOff (forsgren#285): the starter
// writes issues_page: false, the agent installer's step 2 gives it as the
// default of question 10, and its step 9 example config writes it.
func TestNewInstallationsStartWithTheIssuesPageOff(t *testing.T) {
	const want = "issues_page: false"
	if issues, _ := starterPages(t); issues != want {
		t.Errorf("want the starter to write %q, got %q", want, issues)
	}
	if !strings.Contains(asOneLine(section(t, installerFile, "Step 2.")), "Default: `"+want+"`") {
		t.Errorf("agent-installer.md step 2 does not give %q as the default", want)
	}
	if !strings.Contains(section(t, installerFile, "Step 9."), "\n"+want+"\n") {
		t.Errorf("agent-installer.md step 9 does not write the line %q", want)
	}
}

// TestUpdatingDocSaysTheDailyPageGoesAt130 (forsgren#159): the update notes
// say plainly that from 1.3.0 an installation without days_page loses its
// Daily page until it sets days_page: true.
func TestUpdatingDocSaysTheDailyPageGoesAt130(t *testing.T) {
	const want = "From 1.3.0 an installation that does not set days_page loses its Daily page until it sets " +
		"days_page: true."
	if !strings.Contains(readRepoFileAsOneLine(t, "docs/updating-and-releases.md"), want) {
		t.Errorf("docs/updating-and-releases.md does not say %q", want)
	}
}

// TestInstallerExplainsTheThreeValuesOfThePageQuestions (forsgren#200): step 2
// names true, unlisted and false in questions 10, 12 and 13; questions 12 and
// 13, whose default is unlisted, say what unlisted is, that the person can open
// the page at its address and that true puts it in the menu.
func TestInstallerExplainsTheThreeValuesOfThePageQuestions(t *testing.T) {
	ask := asOneLine(section(t, installerFile, "Step 2."))
	for _, tc := range []struct{ start, end, address string }{
		{"10. **The Issues page", "11. **The DORA window**", ""},
		{"12. **The Numbers and scoring page**", "13. **The History page**", "numbers-scoring/"},
		{"13. **The History page**", "## Step 3.", "history.html"},
	} {
		_, rest, _ := strings.Cut(ask, tc.start)
		question, _, _ := strings.Cut(rest, tc.end)
		for _, text := range []string{"`true`", "`unlisted`", "`false`", "no menu entry", "not generated", tc.address} {
			if !strings.Contains(question, text) {
				t.Errorf("agent-installer.md question %q does not say %q", tc.start, text)
			}
		}
	}
}
