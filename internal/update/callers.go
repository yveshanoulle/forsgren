package update

import (
	"maps"
	"slices"
)

// callers are the files of an installation's data repository that pin
// forsgren, each with the one workflow of forsgren it calls: forsgren.yml
// calls metrics.yml and forsgren-update.yml calls auto_update.yml.
var callers = map[string]string{
	".github/workflows/forsgren.yml":        "metrics.yml",
	".github/workflows/forsgren-update.yml": "auto_update.yml",
}

// Callers are the repository paths of the caller files, sorted.
func Callers() []string {
	return slices.Sorted(maps.Keys(callers))
}

// CallerWorkflows are the caller files by repository path, each with the
// workflow of forsgren it calls; a copy, the caller may change it.
func CallerWorkflows() map[string]string {
	return maps.Clone(callers)
}
