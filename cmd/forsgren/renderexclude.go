package main

import (
	"fmt"
	"io"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// withoutExcluded is the stored deployments and their commits less those that
// the config's `exclude:` lists take back (forsgren#667), the files left as
// they are, as failuresOf leaves out the withdrawn failure issues. Each
// exclusion whose task no stored deployment of its repository has is one
// warning line on stderr, and excludes nothing.
func withoutExcluded(cfg config.Config, records []history.Record, commits []history.Commit, stderr io.Writer,
) ([]history.Record, []history.Commit) {
	exclusions := exclusionsOf(cfg)
	for _, e := range history.Unmatched(records, exclusions) {
		_, _ = fmt.Fprintf(stderr, "render: warning: repository %q: exclude task %q matches no stored deployment; "+
			"it excludes nothing\n", e.Repository, e.Task)
	}
	return history.WithoutExcluded(records, commits, exclusions)
}

// exclusionsOf is every repository's `exclude:` list of cfg, each exclusion
// with its repository.
func exclusionsOf(cfg config.Config) []history.Exclusion {
	var out []history.Exclusion
	for _, p := range cfg.Projects {
		for _, r := range p.Repositories {
			for _, e := range r.Exclude {
				out = append(out, history.Exclusion{Repository: r.Name, Task: e.Task, Before: e.Before})
			}
		}
	}
	return out
}
