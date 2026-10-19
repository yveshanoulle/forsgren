package collect

// A repository cut short at the request budget keeps what it read whole
// (forsgren#64, step 2, decisions #238 and #239). Lists come newest first, so
// a cut leaves the newest days read and the older ones not; and a deployment
// is read whole only once its statuses and, for a success, its commits
// comparison are. So a cut keeps every UTC calendar day after the day of the
// item whose request was refused, its records and their commits, and the
// read mark moves to the start of the oldest such day. The day of that item
// is thrown away, with everything older, and read again by the next run.
// Statuses are read only while the budget has room left for the comparisons
// of the successes read so far (github.Client.Reserve), so a day that was
// read can be compared.

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// cutShort is a request budget error with the creation time of the item whose
// request was refused; zero when it was a list's, so none of the list was read.
type cutShort struct {
	err error
	at  time.Time
}

func (c *cutShort) Error() string { return c.err.Error() }
func (c *cutShort) Unwrap() error { return c.err }

// cutAt is err as the cut of the item created at at when it is the budget's,
// else err itself.
func cutAt(err error, at time.Time) error {
	if errors.Is(err, github.ErrBudget) {
		return &cutShort{err, at}
	}
	return err
}

// cutOf is err's cut, when it is one.
func cutOf(err error) (*cutShort, bool) {
	var c *cutShort
	return c, errors.As(err, &c)
}

// dayAfter is the start of the UTC calendar day after the one t is in.
func dayAfter(t time.Time) time.Time { return t.UTC().Truncate(24 * time.Hour).Add(24 * time.Hour) }

// statusesOf is the statuses of deployment id, or the budget's cut when the
// budget has no room for them and the owed comparisons after them.
func (o Options) statusesOf(ctx context.Context, repo string, id int64, owed int) ([]github.DeploymentStatus, error) {
	if err := o.Client.Reserve(repo, owed); err != nil {
		return nil, err
	}
	return o.Client.DeploymentStatuses(ctx, repo, id)
}

// tagCommitOf is the commit of a release's tag, or the budget's cut as
// statusesOf has it.
func (o Options) tagCommitOf(ctx context.Context, repo, tag string, owed int) (string, error) {
	if err := o.Client.Reserve(repo, owed); err != nil {
		return "", err
	}
	return o.Client.TagCommit(ctx, repo, tag)
}

// wholeDays is where the whole days of a read cut at an item created at at
// start: the first instant after at's day, and whether the cut leaves any.
// The first chunk of a repository, and the older chunk, keep their days;
// the recent read of a repository with a reach keeps none yet.
func (w windows) wholeDays(at time.Time) (time.Time, bool) {
	if at.IsZero() {
		return time.Time{}, false
	}
	from := dayAfter(at)
	switch {
	case w.first:
		return from, !from.After(w.now)
	case !w.older.Until.IsZero() && at.Before(w.older.Until):
		return earlier(from, w.older.Until), true
	}
	return time.Time{}, false
}

// reachAfter is where the reach moves to when the days from from on are kept:
// from for the first chunk and the older chunk, unless that is where the
// older chunk started, and it stays (zero) for the rest.
func (w windows) reachAfter(from time.Time) time.Time {
	if w.first || from.Before(w.older.Until) {
		return from
	}
	return time.Time{}
}

// kept is f as a read cut at an item created at at leaves it: the records of
// the whole days, and the reach those days give. A read that keeps no record
// moves no reach, so a day with none is read again with the days behind it.
func (w windows) kept(f found, at time.Time) found {
	from, ok := w.wholeDays(at)
	f.reach = time.Time{}
	if !ok {
		f.records, f.successes = nil, 0
		return f
	}
	f.records = slices.DeleteFunc(slices.Clone(f.records), func(r history.Record) bool { return r.CreatedAt.Before(from) })
	if len(f.records) > 0 {
		f.reach = w.reachAfter(from)
	}
	return f
}

// cutRead is the read of the recent window ended by err: what is kept when it
// is the budget's cut, else nothing.
func (w windows) cutRead(f found, err error) (found, error) {
	if c, ok := cutOf(err); ok {
		return w.kept(f, c.at), err
	}
	return found{}, err
}

// cutOlder is cutRead for the older chunk. A cut that read none of it (its
// list) keeps the recent window whole, so it is taken as a cut at the chunk's
// newest instant.
func (w windows) cutOlder(f found, err error) (found, error) {
	c, ok := cutOf(err)
	if !ok {
		return found{}, err
	}
	at := c.at
	if at.IsZero() {
		at = w.older.Until.Add(-time.Nanosecond)
	}
	return w.kept(f, at), err
}

// keepCommits is the commits of the deployments f keeps or the history
// already holds (a stored success that waited for a previous).
func (h held) keepCommits(commits []history.Commit, f found) []history.Commit {
	kept := map[int64]bool{}
	for _, r := range f.records {
		kept[r.ID] = true
	}
	return slices.DeleteFunc(slices.Clone(commits), func(c history.Commit) bool {
		return !kept[c.DeploymentID] && !h.ids[entry{source{strings.ToLower(c.Repository), c.Kind}, c.DeploymentID}]
	})
}

// whole is what a repository read of its deployments: the records and the
// commits of the new successes.
type whole struct {
	found
	commits []history.Commit
}

// empty says whether there is nothing to store.
func (w whole) empty() bool { return len(w.records) == 0 && len(w.commits) == 0 }

// deploymentsOf reads one repository's deployments and compares its new
// successes. A budget cut gives what is whole, with the cut as the error;
// any other error gives nothing.
func (o Options) deploymentsOf(ctx context.Context, h held, project string, r config.Repository) (whole, error) {
	f, err := o.read(ctx, h, history.Record{Project: project, Repository: r.Name, Name: r.Deployment.Name},
		r.Deployment.Kind)
	if _, cut := cutOf(err); err != nil && !cut {
		return whole{}, err
	}
	commits, cerr := o.commitsOf(ctx, h, h.fresh(f.records))
	if c, ok := cutOf(cerr); ok {
		f = f.win.kept(f, c.at)
		return whole{f, h.keepCommits(commits, f)}, cerr
	}
	if cerr != nil {
		return whole{}, cerr
	}
	return whole{f, commits}, err
}

// keepWhole ends a repository that stopped on err after deployments it read
// whole: a budget cut stores them with their commits, moves the reach, and
// is returned for collectProject to name; any other error is returned as it
// is, with nothing stored. Nothing of the issues is stored and no mark of
// them moves, for their read is stored whole or not at all.
func (o Options) keepWhole(h held, repo string, w whole, err error) error {
	if !errors.Is(err, github.ErrBudget) {
		return err
	}
	if w.empty() {
		return err
	}
	stored, serr := o.store(batch{records: w.records, commits: w.commits})
	if serr != nil {
		return fmt.Errorf("%s: %w", repo, serr)
	}
	h.noteReach(repo, w.reach)
	o.report(repo, w.found, stored)
	o.warn("collect: %s: cut short; the days read whole are stored, the rest is read again by the next run\n", repo)
	return err
}

// earlier is the earlier of a and b.
func earlier(a, b time.Time) time.Time {
	if a.Before(b) {
		return a
	}
	return b
}
