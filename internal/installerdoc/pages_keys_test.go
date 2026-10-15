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
