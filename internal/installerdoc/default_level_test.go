package installerdoc

import (
	"regexp"
	"testing"
)

// TestInstallerDefaultLevelIsTheStartersLevel (forsgren#150): the level the
// installer names as the default in the auto-update question, and the one in
// the config it writes, are the level forsgren's own starter has.
func TestInstallerDefaultLevelIsTheStartersLevel(t *testing.T) {
	level := starterLevel(t)
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
		if m[1] != level {
			t.Errorf("%s has level %q, want the starter's %q", where, m[1], level)
		}
	}
}
