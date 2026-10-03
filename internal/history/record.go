package history

import (
	"cmp"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// deployments is the format of data/deployments.csv, the history format v1.
var deployments = format[Record, key]{
	versionLine: "# forsgren history v1",
	columnLine:  "project,repository,kind,name,deployment_id,commit,created_at,state,task",
	decode:      toRecord,
	encode:      Record.fields,
	validate:    Record.validate,
	key:         Record.key,
	compare:     compareRecords,
}

// key identifies a deployment: the ID spaces of deployments, workflow runs
// and releases are separate at GitHub, so the kind is part of it. The
// repository is lower-case: GitHub's repository names ignore case, so
// Acme/App and acme/app are one repository.
type key struct {
	repository string
	kind       Kind
	id         int64
}

func (r Record) key() key { return key{strings.ToLower(r.Repository), r.Kind, r.ID} }

// compareRecords orders new lines by created-at, then ID (then repository
// and kind, so the order is total).
func compareRecords(a, b Record) int {
	return cmp.Or(a.CreatedAt.Compare(b.CreatedAt), cmp.Compare(a.ID, b.ID),
		cmp.Compare(a.Repository, b.Repository), cmp.Compare(a.Kind, b.Kind))
}

// fields are the columns of r's line.
func (r Record) fields() []string {
	return []string{
		r.Project, r.Repository, string(r.Kind), r.Name, strconv.FormatInt(r.ID, 10), r.Commit,
		r.CreatedAt.UTC().Format(timeLayout), string(r.State), r.Task,
	}
}

// toRecord reads the nine fields of a line.
func toRecord(f []string) (Record, error) {
	id, err := parseNumber("deployment_id", f[4])
	if err != nil {
		return Record{}, err
	}
	at, err := parseTime("created_at", f[6])
	if err != nil {
		return Record{}, err
	}
	return Record{
		Project: f[0], Repository: f[1], Kind: Kind(f[2]), Name: f[3], ID: id,
		Commit: f[5], CreatedAt: at, State: State(f[7]), Task: f[8],
	}, nil
}

// check is one rule of a record: whether it holds, and why not.
type check struct {
	ok  bool
	why string
}

// firstFailure is the reason of the first rule that does not hold, or nil.
func firstFailure(checks ...check) error {
	for _, c := range checks {
		if !c.ok {
			return errors.New(c.why)
		}
	}
	return nil
}

// validate says why r cannot be stored, or nil.
func (r Record) validate() error {
	return firstFailure(
		check{r.Project != "", "project is empty"},
		check{isRepository(r.Repository), fmt.Sprintf("repository %q is not owner/name", r.Repository)},
		check{isKind(r.Kind), fmt.Sprintf("kind %q is not environment, workflow or release", r.Kind)},
		check{r.Kind == KindRelease || r.Name != "", "name is empty"},
		check{r.ID > 0, "deployment_id is not positive"},
		check{isSHA(r.Commit), fmt.Sprintf("commit %q is not 40 or 64 lower-case hex digits", r.Commit)},
		check{isWholeSecond(r.CreatedAt), "created_at is empty or has a fraction of a second"},
		check{isState(r.State), fmt.Sprintf("state %q is not success, failure or other", r.State)},
		check{!strings.ContainsAny(r.Project+r.Repository+r.Name+r.Task, "\r\n"), "a field has a line break"},
	)
}

// isRepository says whether s is owner/name.
func isRepository(s string) bool {
	owner, name, ok := strings.Cut(s, "/")
	return ok && owner != "" && name != "" && !strings.Contains(name, "/")
}

// isSHA says whether s is a git object name in lower-case hex.
func isSHA(s string) bool {
	if len(s) != 40 && len(s) != 64 {
		return false
	}
	return strings.Trim(s, "0123456789abcdef") == ""
}

// isKind says whether k is one of the three kinds.
func isKind(k Kind) bool {
	switch k {
	case KindEnvironment, KindWorkflow, KindRelease:
		return true
	}
	return false
}

// isState says whether s is one of the three final states.
func isState(s State) bool {
	switch s {
	case StateSuccess, StateFailure, StateOther:
		return true
	}
	return false
}

// isWholeSecond says whether t is set and has no fraction of a second.
func isWholeSecond(t time.Time) bool {
	return !t.IsZero() && t.Equal(t.Truncate(time.Second))
}
