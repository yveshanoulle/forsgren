package collect

// The one-time catch-up of failure_start (forsgren#245), for an installation
// that stored failure issues before collect read their comments (forsgren#37):
// each stored failure of a repository that has an empty failure_start, can
// still count (canStillCount) and no withdrawal takes back has its comments
// read once with CommentRecords, and a block found there is stored as a new
// line of the failure. A refused read fails the repository, like the other
// reads.
//
// data/starts_checked.csv (a mark file, one time per repository) says which
// repositories were caught up. It is written only when every repository of the
// run finished, so a run that failed or was cut short anywhere does the
// catch-up again, which only reads comments and stores nothing it has stored;
// an installation that has done it gets no second one. A repository added to
// the configuration later is caught up with the same rule, once.

import (
	"context"
	"path/filepath"
	"slices"
	"strings"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// StartsCheckedFile is the name, next to the history, of the file that notes
// which repositories had their failure starts caught up.
const StartsCheckedFile = "starts_checked.csv"

// startsCheckedFile is the path of the starts checked file next to o's history.
func (o Options) startsCheckedFile() string {
	return filepath.Join(filepath.Dir(o.History), StartsCheckedFile)
}

// withStartCatchUp is fresh, the failure issues of repo to store, with the
// lines of its catch-up added when repo has not been caught up: the stored
// failures that the run did not just read themselves (fresh holds those, their
// comments already read).
func (o Options) withStartCatchUp(ctx context.Context, h held, repo string, fresh []history.Failure,
) ([]history.Failure, error) {
	if _, done := h.checked[strings.ToLower(repo)]; done {
		return fresh, nil
	}
	for _, n := range o.startsToCatchUp(h, repo, fresh) {
		start, err := o.commentStart(ctx, repo, n)
		if err != nil {
			return nil, err
		}
		if !start.IsZero() {
			f := h.failures[history.IssueKeyOf(repo, n)]
			f.FailureStart = start
			fresh = append(fresh, f)
		}
	}
	return fresh, nil
}

// startsToCatchUp is the numbers of repo's stored failures to read the
// comments of, oldest first: those that lack a start (needsStart) and are not
// among fresh.
func (o Options) startsToCatchUp(h held, repo string, fresh []history.Failure) []int64 {
	read := map[history.IssueKey]bool{}
	for _, f := range fresh {
		read[f.Key()] = true
	}
	var out []int64
	for key, f := range h.failures {
		if strings.EqualFold(f.Repository, repo) && !read[key] && o.needsStart(h, key, f) {
			out = append(out, f.Issue)
		}
	}
	slices.Sort(out)
	return out
}

// needsStart says whether the stored failure f has no failure_start, can still
// count and is not withdrawn.
func (o Options) needsStart(h held, key history.IssueKey, f history.Failure) bool {
	return f.FailureStart.IsZero() && o.canStillCount(f) && !h.withdrawn[key]
}

// noteStartsDone notes that repo was caught up in this run: it is kept in
// h.checked only when every repository finished (finishStarts).
func (h held) noteStartsDone(repo string) { h.startsDone[strings.ToLower(repo)] = true }

// finishStarts moves the mark of every repository caught up in this run to the
// run's time, unless a repository failed or was cut short (failed counts both).
func (o Options) finishStarts(h held, failed int) {
	if failed > 0 {
		return
	}
	for repo := range h.startsDone {
		if _, done := h.checked[repo]; !done {
			h.checked[repo] = wholeSecond(o.Now)
		}
	}
}
