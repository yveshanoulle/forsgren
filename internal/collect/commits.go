package collect

import (
	"cmp"
	"context"
	"errors"
	"fmt"
	"io/fs"
	"path/filepath"
	"slices"
	"time"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// CommitsFile is the name of the commits file, kept next to the history:
// data/commits.csv beside data/deployments.csv.
const CommitsFile = "commits.csv"

// commitsFile is the path of the commits file next to o's history.
func (o Options) commitsFile() string { return filepath.Join(filepath.Dir(o.History), CommitsFile) }

// checkCommits refuses a commits file that cannot be read, before GitHub is
// asked anything; a missing one is created by the first append.
func checkCommits(path string) error {
	if _, err := history.LoadCommits(path); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	return nil
}

// stream is one line of deployments that follow each other: a source's
// deployments with the same environment or workflow and the same task. A
// release's task is its tag, a new one with every release, so the releases
// of a repository are one stream.
type stream struct {
	source
	name, task string
}

// streamOf is the stream r belongs to.
func streamOf(r history.Record) stream {
	task := r.Task
	if r.Kind == history.KindRelease {
		task = ""
	}
	return stream{sourceOf(r), r.Name, task}
}

// order orders deployments by created_at, then ID.
func order(a, b history.Record) int {
	return cmp.Or(a.CreatedAt.Compare(b.CreatedAt), cmp.Compare(a.ID, b.ID))
}

// fresh is the records the history does not hold yet, oldest first: the
// deployments this run stores, and the only ones it compares. A deployment
// stored by an earlier run had its commits compared then, or was skipped
// for good, so no run compares it again.
func (h held) fresh(records []history.Record) []history.Record {
	var out []history.Record
	for _, r := range records {
		if !h.has(r, r.ID) {
			out = append(out, r)
		}
	}
	slices.SortStableFunc(out, order)
	return out
}

// previous is the newest success of r's stream before r: stored by an
// earlier run, or among this run's fresh records. A failure or another
// final state is never a previous, so its commits roll on to the next
// success.
func (h held) previous(r history.Record, fresh []history.Record) (history.Record, bool) {
	s := streamOf(r)
	var best history.Record
	found := false
	for _, c := range slices.Concat(h.successes[s], fresh) {
		if precedes(c, r, s) && newerThan(c, best, found) {
			best, found = c, true
		}
	}
	return best, found
}

// newerThan says whether c is newer than best, the newest so far, if found.
func newerThan(c, best history.Record, found bool) bool {
	return !found || order(best, c) < 0
}

// precedes says whether c can be the previous of r, of the stream s: a
// success of s before r.
func precedes(c, r history.Record, s stream) bool {
	return c.State == history.StateSuccess && streamOf(c) == s && order(c, r) < 0
}

// commitsOf compares each fresh success with its previous success and
// returns the commits to store; the first success of a stream has no
// known start, so it gets none.
func (o Options) commitsOf(ctx context.Context, h held, fresh []history.Record) ([]history.Commit, error) {
	var out []history.Commit
	for _, r := range fresh {
		prev, ok := h.previous(r, fresh)
		if r.State != history.StateSuccess || !ok {
			continue
		}
		commits, err := o.compare(ctx, prev, r)
		if err != nil {
			return nil, err
		}
		out = append(out, commits...)
	}
	return out, nil
}

// compare is the commits of r since prev. A list GitHub cut, a previous
// that is not an ancestor (a force-push, or a rollback to an older commit)
// and a commit GitHub does not have give r no commits, with a warning:
// that is the history's shape, not access, so the repository goes on. Any
// other error fails the repository.
func (o Options) compare(ctx context.Context, prev, r history.Record) ([]history.Commit, error) {
	commits, cut, err := o.Client.Compare(ctx, r.Repository, prev.Commit, r.Commit)
	switch {
	case errors.Is(err, github.ErrNotAncestor), errors.Is(err, github.ErrMissingCommit):
		o.warn("collect: %v; lead time skips deployment %d\n", err, r.ID)
		return nil, nil
	case err != nil:
		return nil, err
	case cut:
		o.warn("collect: %s: deployment %d: %d commits compared, list cut; lead time skips this deployment\n",
			r.Repository, r.ID, len(commits))
		return nil, nil
	}
	return deployed(r, commits), nil
}

// warn prints a warning on stderr.
func (o Options) warn(format string, a ...any) { _, _ = fmt.Fprintf(o.Stderr, format, a...) }

// deployed is commits as the commits of the deployment r: each with its
// author date (UTC, whole seconds) and r's created_at.
func deployed(r history.Record, commits []github.Commit) []history.Commit {
	out := make([]history.Commit, 0, len(commits))
	for _, c := range commits {
		out = append(out, history.Commit{
			Repository: r.Repository, Kind: r.Kind, DeploymentID: r.ID, SHA: c.SHA,
			AuthoredAt: c.AuthoredAt.UTC().Truncate(time.Second), DeployedAt: r.CreatedAt,
		})
	}
	return out
}
