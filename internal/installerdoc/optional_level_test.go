package installerdoc

import (
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// levelTexts are the texts that talk about auto_update_level, by name.
func levelTexts(t *testing.T) map[string]string {
	t.Helper()
	texts := map[string]string{"internal/config/starter.yml": asOneLine(config.Starter)}
	for _, path := range []repoFile{installerFile, "README.md", "docs/configuration.md", "docs/updating-and-releases.md"} {
		texts[string(path)] = readRepoFileAsOneLine(t, path)
	}
	return texts
}

// TestNoTextSaysTheAutoUpdateLevelIsRequired (forsgren#157): the level is
// optional, so no text says it is required, that it has no default, or that
// its unset value is none.
func TestNoTextSaysTheAutoUpdateLevelIsRequired(t *testing.T) {
	banned := []string{
		"auto_update_level: is required",
		"required when auto_update is true",
		"It has no default",
		"`none` for an unset `auto_update_level`",
	}
	for path, text := range levelTexts(t) {
		for _, phrase := range banned {
			if strings.Contains(text, phrase) {
				t.Errorf("%s says %q, but auto_update_level is optional", path, phrase)
			}
		}
	}
}

// TestDocsStateThatTheAutoUpdateLevelDefaultsToTheStartersLevel (forsgren#157):
// the updating doc and the starter say the level may be left out and then is
// the starter's level.
func TestDocsStateThatTheAutoUpdateLevelDefaultsToTheStartersLevel(t *testing.T) {
	want := "defaults to `" + config.DefaultLevel + "`"
	texts := levelTexts(t)
	if level := starterLevel(t); config.DefaultLevel != level {
		t.Fatalf("want the default level to be the starter's %q", level)
	}
	for _, path := range []string{"docs/updating-and-releases.md", "docs/configuration.md"} {
		if !strings.Contains(texts[path], want) {
			t.Errorf("%s does not say the level %s", path, want)
		}
	}
	if !strings.Contains(texts["internal/config/starter.yml"], "auto_update_level: is optional") {
		t.Error("the starter does not say auto_update_level: is optional")
	}
}
