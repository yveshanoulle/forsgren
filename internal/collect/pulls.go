package collect

// The merged pull requests of each repository (forsgren#255, step 4), for
// Mainline Lead Time (forsgren#256): data/pulls.csv next to the history
// (history.PullRequest), each with its first commit time.
//
// The read is incremental by updated time: a run asks for the closed pull
// requests updated since the repository's mark in data/pulls_read.csv less a
// day, never before history_days back, and since history_days back when there
// is no mark. A pull request closed without a merge, merged before
// history_days back, or already stored is not asked for its commits and not
// stored. It runs after the repository's deployments and issues are stored,
// so nothing it meets takes them back:
//
//   - a missing pull-requests: read stores none and moves no mark, with a note
//     on stderr, and never fails the run (Yves's ruling on #255; the needs
//     mechanism names it in the setup issue);
//   - a pull request's commits are read only while the request budget has
//     room for all their pages; at its margin the pull requests read whole
//     are stored and the mark stays, so the next run reads the rest, the one
//     interrupted included, again without failing the run; the report names
//     the repository as incomplete for its pull requests (forsgren#320,
//     decisions #304, #307, #308);
//   - a pull request merged before history_days back is skipped, never a
//     stop: the list is by updated time, and a later one can be in the
//     window (decision #310);
//   - a list cut at the page limit is named on stderr as an incomplete read
//     that may skip older pull requests for good, and the mark moves: the
//     list is newest first, so the same mark would read the same pages
//     (decision #309);
//   - any other error stores what was read whole and fails the repository.

import (
	"context"
	"errors"
	"io/fs"
	"path/filepath"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

const (
	// PullsFile is the name of the pull requests file, kept next to the
	// history.
	PullsFile = "pulls.csv"
	// PullsReadFile is the name, next to the history, of the file that notes
	// when each repository's closed pull requests were last read.
	PullsReadFile = "pulls_read.csv"
	// pullCommitPagesAfterFirst is how many more requests a pull request's
	// commits can take after the first: GitHub lists at most 250, 100 a page.
	pullCommitPagesAfterFirst = 2
)

// pullsFile is the path of the pull requests file next to o's history.
func (o Options) pullsFile() string { return filepath.Join(filepath.Dir(o.History), PullsFile) }

// pullsReadFile is the path of the pulls read file next to o's history.
func (o Options) pullsReadFile() string { return filepath.Join(filepath.Dir(o.History), PullsReadFile) }

// loadPulls is h with the pull requests the pulls file holds; a missing file
// holds none, one that cannot be read refuses the run.
func (o Options) loadPulls(h held) (held, error) {
	stored, err := history.LoadPullRequests(o.pullsFile())
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return h, err
	}
	h.pulls = make(map[history.IssueKey]bool, len(stored))
	for _, p := range stored {
		h.pulls[p.Key()] = true
	}
	return h, nil
}

// pullsSince is where the read of repo's pull requests starts: its mark less
// a day, never before history_days back.
func (o Options) pullsSince(h held, repo string) time.Time {
	if last, ok := h.pullsRead[strings.ToLower(repo)]; ok {
		return later(last.Add(-failuresReadOverlap), o.earliest)
	}
	return o.earliest
}

// collectPulls reads repo's merged pull requests, stores the new ones and
// says how many it stored; see the top of this file for what ends the read.
func (o Options) collectPulls(ctx context.Context, h held, repo string) (int, error) {
	read, err := o.readPulls(ctx, h, repo)
	stored, serr := history.AppendPullRequests(o.pullsFile(), read.pulls)
	if serr != nil {
		return stored, serr
	}
	return stored, o.endPulls(h, repo, read.truncated, err)
}

// endPulls moves repo's mark after a read that ended on err, nil included,
// and says what fails the repository.
func (o Options) endPulls(h held, repo string, truncated bool, err error) error {
	switch {
	case errors.Is(err, github.ErrPullRequestsDenied):
		o.warn("collect: %v; its pull requests are not read, the rest is collected\n", err)
		return nil
	case errors.Is(err, github.ErrBudget):
		o.warn("collect: %s: the pull requests were cut short: %v; those read whole are stored, "+
			"the rest is read again by the next run\n", repo, err)
		o.reportPullsCut(repo)
		return nil
	case err != nil:
		return err
	}
	if truncated {
		o.warn("collect: %s: the pull request read is incomplete: only the newest %d page(s) were read, "+
			"and older pull requests may be skipped for good, since the read mark moves on\n", repo, o.Client.MaxPages())
	}
	h.pullsRead[strings.ToLower(repo)] = wholeSecond(o.Now)
	return nil
}

// pullsRead is what one read of a repository's pull requests gives: the
// merged ones read whole, and whether the list stopped at the page limit.
type pullsRead struct {
	pulls     []history.PullRequest
	truncated bool
}

// readPulls is repo's closed pull requests since its mark, the merged ones to
// store each with its first commit time, up to the first error.
func (o Options) readPulls(ctx context.Context, h held, repo string) (pullsRead, error) {
	closed, truncated, err := o.Client.ClosedPullRequests(ctx, repo, o.pullsSince(h, repo))
	read := pullsRead{truncated: truncated}
	if err != nil {
		return read, err
	}
	for _, p := range closed {
		if !o.toStore(h, repo, p) {
			continue
		}
		pull, err := o.pullOf(ctx, repo, p)
		if err != nil {
			return read, err
		}
		read.pulls = append(read.pulls, pull)
	}
	return read, nil
}

// toStore says whether p is a pull request of repo to store: merged within
// history_days and not stored yet. One closed without a merge has the zero
// merged time, before history_days too.
func (o Options) toStore(h held, repo string, p github.ClosedPullRequest) bool {
	return !p.MergedAt.Before(o.earliest) && !h.pulls[history.IssueKeyOf(repo, p.Number)]
}

// pullOf is p with its first commit time, read only while the request budget
// has room for every page of its commits. A commit list that gives no usable
// date (github.ErrNoCommitDate: no commit, or one without an author date) has
// the created time stand in, named on stderr (forsgren#300), and so does one
// GitHub's answer for cannot be read (github.ErrAnswer), with its own warning
// naming the repository and the pull request (decision #313); a cut one keeps
// its time with the cut flag (forsgren#299). Every other error, a rate limit
// or GitHub's error answer, is returned.
func (o Options) pullOf(ctx context.Context, repo string, p github.ClosedPullRequest) (history.PullRequest, error) {
	if err := o.Client.Reserve(repo, pullCommitPagesAfterFirst); err != nil {
		return history.PullRequest{}, err
	}
	first, cut, err := o.Client.FirstCommitTime(ctx, repo, p.Number)
	pull := history.PullRequest{
		Repository: repo, Number: p.Number, CreatedAt: wholeSecond(p.CreatedAt),
		MergedAt: wholeSecond(p.MergedAt), MergeCommit: p.MergeCommit, UpdatedAt: wholeSecond(p.UpdatedAt),
		FirstCommitAt: wholeSecond(first), FirstCommitCut: cut,
	}
	switch {
	case errors.Is(err, github.ErrNoCommitDate):
		o.warn("collect: %v; its created time stands in for its first commit time\n", err)
	case errors.Is(err, github.ErrAnswer):
		o.warn("collect: %s: pull request %d: the answer for its commits is malformed or unreadable: %v; "+
			"its created time stands in for its first commit time\n", repo, p.Number, err)
	case err != nil:
		return history.PullRequest{}, err
	default:
		return pull, nil
	}
	pull.FirstCommitAt, pull.FirstCommitCut, pull.CreatedStandsIn = time.Time{}, false, true
	return pull, nil
}
