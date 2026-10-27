package collect

// The merged pull requests of each repository (forsgren#255, step 4), for
// PR Lead Time (forsgren#256): data/pulls.csv next to the history
// (history.PullRequest), each with its first commit time, and the commits of
// each in data/pull_commits.csv (history.PullCommit; forsgren#463, step 6):
// every commit of the list read, a bot's pull request and a cut list
// included, none for a pull request whose created time stands in; they are
// written before the pull requests, so a pull request is never stored
// without its commits, and a pull_commits.csv that cannot be read refuses the
// run before GitHub is asked.
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
//     mechanism names it in the setup issue); the repository's line in
//     data/pulls_denied.csv says so, its name and the run's time, so the
//     page can tell a refused read from no pull requests (forsgren#337,
//     decision #332), and a later read that ends without an error, a list
//     cut at the page limit included, removes it; a budget stop or any
//     other error leaves the file as it was, since neither says whether the
//     pull requests can be read;
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
	// PullCommitsFile is the name, next to the history, of the file of the
	// commits of each merged pull request (forsgren#463, step 6).
	PullCommitsFile = "pull_commits.csv"
	// PullsReadFile is the name, next to the history, of the file that notes
	// when each repository's closed pull requests were last read.
	PullsReadFile = "pulls_read.csv"
	// PullsDeniedFile is the name, next to the history, of the file that
	// notes each repository whose pull request read GitHub refused with a
	// 403 in its latest read (forsgren#337, decision #332).
	PullsDeniedFile = "pulls_denied.csv"
	// pullCommitPagesAfterFirst is how many more requests a pull request's
	// commits can take after the first: GitHub lists at most 250, 100 a page.
	pullCommitPagesAfterFirst = 2
)

// pullCommitsFile is the path of the pull commits file next to o's history.
func (o Options) pullCommitsFile() string {
	return filepath.Join(filepath.Dir(o.History), PullCommitsFile)
}

// pullsFile is the path of the pull requests file next to o's history.
func (o Options) pullsFile() string { return filepath.Join(filepath.Dir(o.History), PullsFile) }

// pullsReadFile is the path of the pulls read file next to o's history.
func (o Options) pullsReadFile() string { return filepath.Join(filepath.Dir(o.History), PullsReadFile) }

// pullsDeniedFile is the path of the pulls denied file next to o's history.
func (o Options) pullsDeniedFile() string {
	return filepath.Join(filepath.Dir(o.History), PullsDeniedFile)
}

// loadPulls is h with the pull requests the pulls file holds; a missing file
// holds none, one that cannot be read refuses the run, and so does a pull
// commits file that cannot be read.
func (o Options) loadPulls(h held) (held, error) {
	lines, err := history.LoadPullCommits(o.pullCommitsFile())
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return h, err
	}
	stored, err := history.LoadPullRequests(o.pullsFile())
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return h, err
	}
	h.storedPulls = stored
	h.pulls, h.commitsListed = pullKeys(stored), commitKeys(lines)
	return h, nil
}

// pullKeys is the keys of pulls.
func pullKeys(pulls []history.PullRequest) map[history.IssueKey]bool {
	keys := make(map[history.IssueKey]bool, len(pulls))
	for _, p := range pulls {
		keys[p.Key()] = true
	}
	return keys
}

// commitKeys is the keys of the pull requests that lines are commits of.
func commitKeys(lines []history.PullCommit) map[history.IssueKey]bool {
	keys := make(map[history.IssueKey]bool, len(lines))
	for _, c := range lines {
		keys[history.IssueKeyOf(c.Repository, c.Number)] = true
	}
	return keys
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
func (o Options) collectPulls(ctx context.Context, h held, repo string) (stored int, whole bool, err error) {
	read, readErr := o.readPulls(ctx, h, repo)
	if _, serr := history.AppendPullCommits(o.pullCommitsFile(), read.commits); serr != nil {
		return 0, false, serr
	}
	stored, serr := history.AppendPullRequests(o.pullsFile(), read.pulls)
	if serr != nil {
		return stored, false, serr
	}
	whole, err = o.endPulls(h, repo, read.truncated, readErr)
	return stored, whole, err
}

// endPulls moves repo's marks after a read that ended on err, nil included,
// and says whether the read ended whole (not refused, not cut by the budget:
// forsgren#491) and what fails the repository.
func (o Options) endPulls(h held, repo string, truncated bool, err error) (bool, error) {
	switch {
	case errors.Is(err, github.ErrPullRequestsDenied):
		o.noteDenied(h, repo, err)
		return false, nil
	case errors.Is(err, github.ErrBudget):
		o.warn("collect: %s: the pull requests were cut short: %v; those read whole are stored, "+
			"the rest is read again by the next run\n", repo, err)
		o.reportPullsCut(repo)
		return false, nil
	case err != nil:
		return false, err
	}
	if truncated {
		o.warn("collect: %s: the pull request read is incomplete: only the newest %d page(s) were read, "+
			"and older pull requests may be skipped for good, since the read mark moves on\n", repo, o.Client.MaxPages())
	}
	h.pullsRead[strings.ToLower(repo)] = wholeSecond(o.Now)
	delete(h.denied, strings.ToLower(repo))
	delete(h.deniedBy, strings.ToLower(repo))
	return true, nil
}

// noteDenied warns of the refused pull request read err and notes repo and the
// refused token in the denied marks, which a read that ends without an error
// removes.
func (o Options) noteDenied(h held, repo string, err error) {
	o.warn("collect: %v; its pull requests are not read, the rest is collected\n", err)
	h.denied[strings.ToLower(repo)] = wholeSecond(o.Now)
	h.deniedBy[strings.ToLower(repo)] = o.Client.TokenName()
}

// pullsRead is what one read of a repository's pull requests gives: the
// merged ones read whole, their commits, and whether the list stopped at the
// page limit.
type pullsRead struct {
	pulls     []history.PullRequest
	commits   []history.PullCommit
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
		pull, commits, err := o.readPull(ctx, repo, p)
		if err != nil {
			return read, err
		}
		read.pulls = append(read.pulls, pull)
		read.commits = append(read.commits, commits...)
	}
	return read, nil
}

// toStore says whether p is a pull request of repo to store: merged within
// history_days and not stored yet. One closed without a merge has the zero
// merged time, before history_days too.
func (o Options) toStore(h held, repo string, p github.ClosedPullRequest) bool {
	return !p.MergedAt.Before(o.earliest) && !h.pulls[history.IssueKeyOf(repo, p.Number)]
}

// The account types of GitHub (user.type) that say who opened a pull
// request: a bot account, every GitHub App's bot among them, and a person.
const (
	botUserType    = "Bot"
	personUserType = "User"
)

// botOf is the bot status of a pull request whose author's account type is
// userType (forsgren#345, Yves's answer on #349, Option B): a bot for "Bot",
// a person for "User" only, and unknown for any other type (Organization,
// Mannequin) or none, never guessed to be a person.
func botOf(userType string) history.BotStatus {
	switch userType {
	case botUserType:
		return history.ByBot
	case personUserType:
		return history.ByHuman
	}
	return history.BotUnknown
}

// readPull is p's line of data/pulls.csv, with its first commit time and its
// bot status, and its commits, read only while the request budget has room
// for every page of them. The first commit time is the earliest author date of the commits,
// and the commits are lines of data/pull_commits.csv, bots' pull requests
// included, a cut list's too (its pull request line says it is cut;
// forsgren#463, step 6). A commit list that gives no usable date
// (github.ErrNoCommitDate: no commit, or one without an author date) has the
// created time stand in, named on stderr (forsgren#300), and so does one
// GitHub's answer for cannot be read (github.ErrAnswer), with its own warning
// naming the repository and the pull request (decision #313); neither gives
// commit lines. A cut one keeps its time with the cut flag (forsgren#299).
// Every other error, a rate limit or GitHub's error answer, is returned.
func (o Options) readPull(ctx context.Context, repo string, p github.ClosedPullRequest,
) (history.PullRequest, []history.PullCommit, error) {
	if err := o.Client.Reserve(repo, pullCommitPagesAfterFirst); err != nil {
		return history.PullRequest{}, nil, err
	}
	listed, cut, err := o.Client.PullCommits(ctx, repo, p.Number)
	pull := pullLineOf(repo, p, earliestAuthored(listed), cut)
	switch {
	case errors.Is(err, github.ErrNoCommitDate):
		o.warn("collect: %v; its created time stands in for its first commit time\n", err)
	case errors.Is(err, github.ErrAnswer):
		o.warn("collect: %s: pull request %d: the answer for its commits is malformed or unreadable: %v; "+
			"its created time stands in for its first commit time\n", repo, p.Number, err)
	case err != nil:
		return history.PullRequest{}, nil, err
	default:
		return pull, pullCommitsOf(repo, p.Number, listed), nil
	}
	pull.FirstCommitAt, pull.FirstCommitCut, pull.CreatedStandsIn = time.Time{}, false, true
	return pull, nil, nil
}

// pullLineOf is p of repo as a line of data/pulls.csv, its first commit time
// first, cut or not, its bot status from its author's account type.
func pullLineOf(repo string, p github.ClosedPullRequest, first time.Time, cut bool) history.PullRequest {
	return history.PullRequest{
		Repository: repo, Number: p.Number, CreatedAt: wholeSecond(p.CreatedAt),
		MergedAt: wholeSecond(p.MergedAt), MergeCommit: p.MergeCommit, UpdatedAt: wholeSecond(p.UpdatedAt),
		FirstCommitAt: wholeSecond(first), FirstCommitCut: cut, Bot: botOf(p.UserType),
	}
}

// earliestAuthored is the earliest author date of commits, zero for none.
func earliestAuthored(commits []github.PullCommit) time.Time {
	var first time.Time
	for _, c := range commits {
		if first.IsZero() || c.AuthoredAt.Before(first) {
			first = c.AuthoredAt
		}
	}
	return first
}

// pullCommitsOf is commits as lines of pull request number of repo.
func pullCommitsOf(repo string, number int64, commits []github.PullCommit) []history.PullCommit {
	lines := make([]history.PullCommit, 0, len(commits))
	for _, c := range commits {
		lines = append(lines, history.PullCommit{Repository: repo, Number: number, SHA: c.SHA, Author: c.Author,
			AuthoredAt: wholeSecond(c.AuthoredAt)})
	}
	return lines
}
