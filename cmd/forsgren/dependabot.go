package main

// The Dependabot cooldown (forsgren#194): how many days Dependabot waits after
// a release before it proposes it, read from the installation's
// .github/dependabot.yml.

import (
	"os"
	"path/filepath"

	"go.yaml.in/yaml/v3"
)

// dependabotFile is the installation's Dependabot configuration, where the
// workflow checks it out.
const dependabotFile = ".github/dependabot.yml"

// defaultCooldownDays is Dependabot's documented default cooldown, which it
// applies to a github-actions update that names no default-days (forsgren#195).
const defaultCooldownDays = 3

// dependabotUpdates are the updates of a dependabot.yml, as far as the
// cooldown of the github-actions ecosystem goes.
type dependabotUpdates struct {
	Updates []struct {
		Ecosystem string `yaml:"package-ecosystem"`
		Cooldown  struct {
			DefaultDays *int `yaml:"default-days"`
		} `yaml:"cooldown"`
	} `yaml:"updates"`
}

// cooldownDays is the cooldown of the github-actions updates in the file at
// path: the default-days of the first such update that names one, which is the
// whole of it for this ecosystem, because Dependabot applies semver-major-days,
// semver-minor-days and semver-patch-days only to ecosystems that support
// them and github-actions is not one (GitHub's Dependabot options reference,
// cooldown). An explicit 0 or a negative number is 0. When a github-actions
// update names no default-days, with no cooldown key, an empty one or only the
// semver days, it is Dependabot's own default, defaultCooldownDays (forsgren#195).
// 0 also for none: no file, a file that is no YAML or holds no number, or no
// github-actions update, which Dependabot does not update at all. The include
// and exclude lists of a cooldown are not read.
func cooldownDays(path string) int {
	raw, err := os.ReadFile(filepath.Clean(path))
	if err != nil {
		return 0
	}
	var file dependabotUpdates
	if yaml.Unmarshal(raw, &file) != nil {
		return 0
	}
	days := 0
	for _, update := range file.Updates {
		if update.Ecosystem != "github-actions" {
			continue
		}
		if update.Cooldown.DefaultDays != nil {
			return max(*update.Cooldown.DefaultDays, 0)
		}
		days = defaultCooldownDays
	}
	return days
}
