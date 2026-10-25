package collect

// The pushes to the default branch of each repository (forsgren#397, step 2,
// decision #400, option A), for time to main and batch size per push without
// deployments: data/pushes.csv next to the history (history.Push), from
// GitHub's repository activity list.
//
// The read is incremental by time: a run asks for the activity of the
// repository's default branch (asked once per run) since the repository's
// mark in data/pushes_read.csv less a day, never before history_days back,
// and since history_days back when there is no mark. It
// runs after the repository's pull requests, so nothing it meets takes them
// back:
//
//   - a push, a pull request merge and a force push are stored; each other
//     kind of activity is left out, and a push already stored (repository,
//     after SHA and time) is neither stored nor compared again;
//   - the commits themselves, the first-parent chain oldest first, each with
//     its author's login and author date, go in data/push_commits.csv from the
//     same compare, written before the repository's pushes so a push is never
//     stored without its commits (forsgren#397, step 3); a push whose count is
//     empty has no lines there, and a push stored by an earlier version is not
//     read again for them;
//   - commits is the number of commits the push added to the first-parent
//     chain, from the compare of before...after (a walk from after through
//     each first parent while it is a commit of the compare); a compare that
//     fails (no ancestor, a commit GitHub does not have), is cut, or does not
//     reach after leaves it empty with a note on stderr, never a guessed
//     number; a force push is stored without a compare, since its before is
//     no ancestor;
//   - a missing contents: read stores nothing and moves no mark, with a note
//     on stderr, and never fails the run; the repository's line in
//     data/pushes_denied.csv says so, so the page can tell a refused read
//     from no pushes, and a later read that ends without an error removes
//     it; a budget stop or any other error leaves the file as it was;
//   - a budget stop stores the pushes compared whole, moves no mark and never
//     fails the run: the next run reads the rest;
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
	// PushesFile is the name of the pushes file, kept next to the history.
	PushesFile = "pushes.csv"
	// PushesReadFile is the name, next to the history, of the file that notes
	// when each repository's pushes were last read.
	PushesReadFile = "pushes_read.csv"
	// PushesDeniedFile is the name, next to the history, of the file that
	// notes each repository whose push read GitHub refused with a 403 in its
	// latest read.
	PushesDeniedFile = "pushes_denied.csv"
	// PushCommitsFile is the name of the file of the commits each push brought.
	PushCommitsFile = "push_commits.csv"
)

// pushesFile is the path of the pushes file next to o's history.
func (o Options) pushesFile() string { return filepath.Join(filepath.Dir(o.History), PushesFile) }

// pushCommitsFile is the path of the push commits file next to o's history.
func (o Options) pushCommitsFile() string {
	return filepath.Join(filepath.Dir(o.History), PushCommitsFile)
}

// pushesReadFile is the path of the pushes read file next to o's history.
func (o Options) pushesReadFile() string {
	return filepath.Join(filepath.Dir(o.History), PushesReadFile)
}

// pushesDeniedFile is the path of the pushes denied file next to o's history.
func (o Options) pushesDeniedFile() string {
	return filepath.Join(filepath.Dir(o.History), PushesDeniedFile)
}

// loadPushes is h with the pushes the pushes file holds; a missing file holds
// none, one that cannot be read refuses the run.
func (o Options) loadPushes(h held) (held, error) {
	stored, err := history.LoadPushes(o.pushesFile())
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return h, err
	}
	if _, err := history.LoadPushCommits(o.pushCommitsFile()); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return h, err
	}
	h.pushes = make(map[history.PushKey]bool, len(stored))
	for _, p := range stored {
		h.pushes[p.Key()] = true
	}
	return h, nil
}

// pushesSince is where the read of repo's pushes starts: its mark less a day,
// never before history_days back.
func (o Options) pushesSince(h held, repo string) time.Time {
	if last, ok := h.pushesRead[strings.ToLower(repo)]; ok {
		return later(last.Add(-failuresReadOverlap), o.earliest)
	}
	return o.earliest
}

// collectPushes reads repo's pushes to main, stores the new ones and says how
// many it stored; see the top of this file for what ends the read.
func (o Options) collectPushes(ctx context.Context, h held, repo string) (int, error) {
	read, truncated, err := o.readPushes(ctx, h, repo)
	if _, serr := history.AppendPushCommits(o.pushCommitsFile(), read.commits); serr != nil {
		return 0, serr
	}
	stored, serr := history.AppendPushes(o.pushesFile(), read.pushes)
	if serr != nil {
		return stored, serr
	}
	return stored, o.endPushes(h, repo, truncated, err)
}

// endPushes moves repo's marks after a read that ended on err, nil included,
// and says what fails the repository.
func (o Options) endPushes(h held, repo string, truncated bool, err error) error {
	key := strings.ToLower(repo)
	switch {
	case errors.Is(err, github.ErrPushesDenied):
		o.warn("collect: %v; its pushes are not read, the rest is collected\n", err)
		h.pushesDenied[key] = wholeSecond(o.Now)
		h.pushesDeniedBy[key] = o.Client.TokenName()
		return nil
	case errors.Is(err, github.ErrBudget):
		o.warn("collect: %s: the pushes were cut short: %v; those compared are stored, "+
			"the rest is read again by the next run\n", repo, err)
		o.reportPushesCut(repo)
		return nil
	case err != nil:
		return err
	}
	if truncated {
		o.warn("collect: %s: the push read is incomplete: only the newest %d page(s) were read, "+
			"and older pushes may be skipped for good, since the read mark moves on\n", repo, o.Client.MaxPages())
	}
	h.pushesRead[key] = wholeSecond(o.Now)
	delete(h.pushesDenied, key)
	delete(h.pushesDeniedBy, key)
	return nil
}

// pushesRead is what one read of a repository's pushes gives: the pushes to
// store each with its commit count, and the commits those pushes brought.
type pushesRead struct {
	pushes  []history.Push
	commits []history.PushCommit
}

// readPushes is repo's activity on its default branch since its mark, up to
// the first error, and whether the list stopped at the page limit.
func (o Options) readPushes(ctx context.Context, h held, repo string) (pushesRead, bool, error) {
	var read pushesRead
	branch, err := o.defaultBranch(ctx, h, repo)
	if err != nil {
		return read, false, err
	}
	activities, truncated, err := o.Client.BranchActivities(ctx, repo, branch, o.pushesSince(h, repo))
	if err != nil {
		return read, truncated, err
	}
	for _, a := range activities {
		push := pushOf(repo, a)
		if h.pushes[push.Key()] {
			continue
		}
		counted, commits, err := o.countCommits(ctx, push)
		if err != nil {
			return read, truncated, err
		}
		read.pushes = append(read.pushes, counted)
		read.commits = append(read.commits, commits...)
	}
	return read, truncated, nil
}

// pushOf is a with no commit count yet.
func pushOf(repo string, a github.Activity) history.Push {
	return history.Push{Repository: repo, PushedAt: wholeSecond(a.PushedAt), Before: a.Before, After: a.After,
		Kind: a.Kind, Bot: botOf(a.ActorType)}
}

// countCommits is p with the commits it added to the first-parent chain and
// those commits, oldest first, or with none when the count cannot be told,
// named on stderr. Only a rate limit or an error answer of GitHub is
// returned.
func (o Options) countCommits(ctx context.Context, p history.Push) (history.Push, []history.PushCommit, error) {
	if p.Kind == github.ActivityForcePush {
		o.warn("collect: %s: force push at %s (%s...%s); its commits column stays empty\n",
			p.Repository, p.PushedAt.Format(time.RFC3339), p.Before, p.After)
		return p, nil, nil
	}
	commits, cut, err := o.Client.Compare(ctx, p.Repository, p.Before, p.After)
	switch {
	case errors.Is(err, github.ErrNotAncestor), errors.Is(err, github.ErrMissingCommit):
		o.noCount(p, err.Error())
		return p, nil, nil
	case err != nil:
		return p, nil, err
	case cut:
		o.noCount(p, "the list of commits is cut")
		return p, nil, nil
	}
	chain := firstParentChain(commits, p.After)
	if len(chain) == 0 {
		o.noCount(p, "the compare does not reach the push's tip")
	}
	p.Commits = int64(len(chain))
	return p, pushCommitsOf(p, chain), nil
}

// pushCommitsOf is the commits of chain (the tip first) as lines of p's
// push, oldest first.
func pushCommitsOf(p history.Push, chain []github.Commit) []history.PushCommit {
	lines := make([]history.PushCommit, 0, len(chain))
	for i := len(chain) - 1; i >= 0; i-- {
		lines = append(lines, history.PushCommit{Repository: p.Repository, After: p.After, SHA: chain[i].SHA,
			Author: chain[i].Author, AuthoredAt: wholeSecond(chain[i].AuthoredAt)})
	}
	return lines
}

// noCount says on stderr why p, a push to main, has no commit count.
func (o Options) noCount(p history.Push, why string) {
	o.warn("collect: %s: push %s...%s: %s; its commits column stays empty\n", p.Repository, p.Before, p.After, why)
}

// firstParentChain is the commits of the first-parent chain from tip through
// each first parent, tip first, while each is a commit of commits; none when
// tip is not one of them.
func firstParentChain(commits []github.Commit, tip string) []github.Commit {
	bySHA := make(map[string]github.Commit, len(commits))
	for _, c := range commits {
		bySHA[c.SHA] = c
	}
	var chain []github.Commit
	for sha := tip; ; {
		c, in := bySHA[sha]
		if !in {
			return chain
		}
		delete(bySHA, sha)
		chain = append(chain, c)
		if len(c.Parents) == 0 {
			return chain
		}
		sha = c.Parents[0]
	}
}
