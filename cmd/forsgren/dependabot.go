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

// dependabotUpdates are the updates of a dependabot.yml, as far as the
// cooldown of the github-actions ecosystem goes.
type dependabotUpdates struct {
	Updates []struct {
		Ecosystem string `yaml:"package-ecosystem"`
		Cooldown  struct {
			DefaultDays int `yaml:"default-days"`
		} `yaml:"cooldown"`
	} `yaml:"updates"`
}

// cooldownDays is the cooldown of the github-actions updates in the file at
// path, the first such update that names one: its default-days, which is the
// whole of it for this ecosystem, because Dependabot applies semver-major-days,
// semver-minor-days and semver-patch-days only to ecosystems that support
// them and github-actions is not one (GitHub's Dependabot options reference,
// cooldown). 0 for none: no file, a file that is no YAML or holds no number,
// a negative number, or no cooldown. The include and exclude lists of a
// cooldown are not read.
func cooldownDays(path string) int {
	raw, err := os.ReadFile(filepath.Clean(path))
	if err != nil {
		return 0
	}
	var file dependabotUpdates
	if yaml.Unmarshal(raw, &file) != nil {
		return 0
	}
	for _, update := range file.Updates {
		if update.Ecosystem == "github-actions" && update.Cooldown.DefaultDays > 0 {
			return update.Cooldown.DefaultDays
		}
	}
	return 0
}
