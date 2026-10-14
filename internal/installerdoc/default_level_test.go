package installerdoc

import (
	"os"
	"path/filepath"
	"regexp"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// TestInstallerDefaultLevelIsTheStartersLevel (forsgren#150): the level the
// installer names as the default in the auto-update question, and the one in
// the config it writes, are the level forsgren's own starter has.
func TestInstallerDefaultLevelIsTheStartersLevel(t *testing.T) {
	path := filepath.Join(t.TempDir(), "forsgren.config.yml")
	if err := os.WriteFile(path, []byte(config.Starter), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg, err := config.Load(path)
	if err != nil {
		t.Fatalf("want the starter to load, got %v", err)
	}
	doc := readInstaller(t)
	question := regexp.MustCompile("Default: `auto_update: true` with\\s+`auto_update_level: (\\w+)`")
	written := regexp.MustCompile(`(?m)^auto_update_level: (\w+)$`)
	shown := map[string]*regexp.Regexp{
		"the Default in the auto-update question": question,
		"the step 9 config":                       written,
	}
	for where, re := range shown {
		m := re.FindStringSubmatch(doc)
		if m == nil {
			t.Errorf("no level found in %s", where)
			continue
		}
		if m[1] != cfg.AutoUpdateLevel {
			t.Errorf("%s has level %q, want the starter's %q", where, m[1], cfg.AutoUpdateLevel)
		}
	}
}
