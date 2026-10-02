// Package history is the history format v1 (forsgren#12, step 4): the file
// data/deployments.csv in an installation's data repository, which holds the
// deployments `forsgren collect` has found. This is the compiling stub of the
// red step: nothing is read or written yet.
package history

import (
	"errors"
	"fmt"
	"time"
)

// Kind says how a deployment was found: by the repository's rule.
type Kind string

// The three kinds, as configured in forsgren.config.yml.
const (
	KindEnvironment Kind = "environment"
	KindWorkflow    Kind = "workflow"
	KindRelease     Kind = "release"
)

// State is the final state of a deployment.
type State string

// The three final states.
const (
	StateSuccess State = "success"
	StateFailure State = "failure"
	StateOther   State = "other"
)

// Record is one deployment. CreatedAt is UTC and whole seconds.
type Record struct {
	Project    string
	Repository string // owner/name
	Kind       Kind
	Name       string // the environment or the workflow file; empty for a release
	ID         int64  // the deployment's ID at GitHub
	Commit     string // the commit SHA, lower-case hex
	CreatedAt  time.Time
	State      State
	Task       string // may be empty
}

// The refusals.
var (
	ErrUnknownVersion = errors.New("unknown history format version")
	ErrMalformed      = errors.New("malformed history")
	ErrInvalidRecord  = errors.New("invalid history record")
)

// MalformedError names the line of a history file that is not in the format.
type MalformedError struct {
	Path   string
	Line   int // 1-based
	Reason string
}

func (e *MalformedError) Error() string {
	return fmt.Sprintf("%s: line %d: %s: %s", e.Path, e.Line, ErrMalformed, e.Reason)
}

// Is makes errors.Is(err, ErrMalformed) true.
func (e *MalformedError) Is(target error) bool { return target == ErrMalformed }

// store is what Append found at the path.
type store struct{}

// Load is a stub: it reads nothing.
func Load(path string) ([]Record, error) { return nil, nil }

// Append is a stub: it stores nothing.
func Append(path string, records []Record) (int, error) { return 0, nil }

// write is a stub: it writes nothing.
func write(path string, st store, fresh []Record) error { return nil }
