package history

import (
	"cmp"
	"strings"
)

// Stream is one line of deployments that follow each other: a repository's
// deployments by one rule (its kind) to the same environment or workflow,
// with the same task. The repository is lower-case, as GitHub's names
// ignore case. A release's task is its tag, a new one with every release,
// so the releases of a repository are one stream.
//
// collect takes a deployment's commits since the previous success of its
// stream (forsgren#16), and recovery time recovers a failure by the next
// success of its stream (forsgren#17): one definition, so the two never
// drift apart.
type Stream struct {
	Repository string
	Kind       Kind
	Name, Task string
}

// Stream is the stream r belongs to.
func (r Record) Stream() Stream {
	task := r.Task
	if r.Kind == KindRelease {
		task = ""
	}
	return Stream{strings.ToLower(r.Repository), r.Kind, r.Name, task}
}

// Chronological orders deployments by created_at, then ID: the order in
// which the deployments of a stream follow each other.
func Chronological(a, b Record) int {
	return cmp.Or(a.CreatedAt.Compare(b.CreatedAt), cmp.Compare(a.ID, b.ID))
}
