package config

// The stored deployments a repository takes back (forsgren#667): a mobile app
// that recorded every test-platform upload as a production deployment before
// it recorded real releases can leave those out of every metric and History.
//
//	repositories:
//	  - name: acme/ios-app
//	    exclude:
//	      - task: beta-upload                 # every deployment of the task
//	      - task: deploy
//	        before: 2026-06-01T00:00:00Z      # only those created before it
//
// The history files keep the records: render leaves them out, as it leaves
// out the failure issues of failures_withdrawn.csv.

import (
	"fmt"
	"time"

	"go.yaml.in/yaml/v3"
)

// Exclusion takes stored deployments of a repository back (forsgren#667):
// those of Task created before Before, or, when Before is zero, all of them.
type Exclusion struct {
	Task   string
	Before time.Time
}

// fileExclusion is one exclusion as the file writes it; Before is the node as
// written, empty when the key is left out.
type fileExclusion struct {
	Task   text      `yaml:"task"`
	Before yaml.Node `yaml:"before"`
}

// exclusionsOf checks each exclusion of the repository, in file order; where
// names the repository in an error.
func exclusionsOf(where string, list []fileExclusion) ([]Exclusion, error) {
	var out []Exclusion
	for _, f := range list {
		e, err := f.check()
		if err != nil {
			return nil, fmt.Errorf("%s: %w: task %q: %w", where, ErrExclude, string(f.Task), err)
		}
		out = append(out, e)
	}
	return out, nil
}

// check is the exclusion with its before read, zero when left out; a task is
// required.
func (f fileExclusion) check() (Exclusion, error) {
	e := Exclusion{Task: string(f.Task)}
	if isBlank(f.Task) {
		return Exclusion{}, errTaskEmpty
	}
	if f.Before.IsZero() {
		return e, nil
	}
	before, err := time.Parse(time.RFC3339, f.Before.Value)
	if err != nil {
		return Exclusion{}, fmt.Errorf("before %q is not an RFC 3339 time such as 2026-06-01T00:00:00Z",
			writtenOf(f.Before))
	}
	e.Before = before
	return e, nil
}
