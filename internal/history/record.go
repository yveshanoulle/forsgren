package history

import (
	"bytes"
	"encoding/csv"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// key identifies a deployment: the ID spaces of deployments, workflow runs
// and releases are separate at GitHub, so the kind is part of it.
type key struct {
	repository string
	kind       Kind
	id         int64
}

func (r Record) key() key { return key{r.Repository, r.Kind, r.ID} }

// encode is the line of r, with its newline.
func (r Record) encode() []byte {
	var buf bytes.Buffer
	w := csv.NewWriter(&buf)
	// A csv.Writer on a bytes.Buffer cannot fail.
	_ = w.Write([]string{
		r.Project, r.Repository, string(r.Kind), r.Name, strconv.FormatInt(r.ID, 10), r.Commit,
		r.CreatedAt.UTC().Format(timeLayout), string(r.State), r.Task,
	})
	w.Flush()
	return buf.Bytes()
}

// decode reads one line of records, without its newline.
func decode(line string) (Record, error) {
	if line == "" {
		return Record{}, errors.New("the line is empty")
	}
	r := csv.NewReader(strings.NewReader(line))
	r.FieldsPerRecord = 9
	fields, err := r.Read()
	if err != nil {
		return Record{}, fmt.Errorf("want 9 comma-separated fields: %w", err)
	}
	return toRecord(fields)
}

// toRecord reads the nine fields of a line and judges the record.
func toRecord(f []string) (Record, error) {
	id, err := strconv.ParseInt(f[4], 10, 64)
	if err != nil || strconv.FormatInt(id, 10) != f[4] {
		return Record{}, fmt.Errorf("deployment_id %q is not a whole number", f[4])
	}
	at, err := time.Parse(timeLayout, f[6])
	if err != nil {
		return Record{}, fmt.Errorf("created_at %q is not RFC 3339 UTC like 2026-09-01T10:00:00Z", f[6])
	}
	rec := Record{
		Project: f[0], Repository: f[1], Kind: Kind(f[2]), Name: f[3], ID: id,
		Commit: f[5], CreatedAt: at, State: State(f[7]), Task: f[8],
	}
	return rec, rec.validate()
}

// validate says why r cannot be stored, or nil.
func (r Record) validate() error {
	for _, c := range []struct {
		ok  bool
		why string
	}{
		{r.Project != "", "project is empty"},
		{isRepository(r.Repository), fmt.Sprintf("repository %q is not owner/name", r.Repository)},
		{isKind(r.Kind), fmt.Sprintf("kind %q is not environment, workflow or release", r.Kind)},
		{r.Kind == KindRelease || r.Name != "", "name is empty"},
		{r.ID > 0, "deployment_id is not positive"},
		{isSHA(r.Commit), fmt.Sprintf("commit %q is not 40 or 64 lower-case hex digits", r.Commit)},
		{isWholeSecond(r.CreatedAt), "created_at is empty or has a fraction of a second"},
		{isState(r.State), fmt.Sprintf("state %q is not success, failure or other", r.State)},
		{!strings.ContainsAny(r.Project+r.Repository+r.Name+r.Task, "\r\n"), "a field has a line break"},
	} {
		if !c.ok {
			return errors.New(c.why)
		}
	}
	return nil
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
