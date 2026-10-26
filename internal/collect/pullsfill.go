package collect

// The fill of the commits of the stored merged pull requests (forsgren#470,
// step 1). A pull request stored before data/pull_commits.csv existed has no
// commit lines, and the Mainline Lead Time cannot replace its squash commit
// by them. Once per repository, after its pull requests are read, each
// stored pull request of the repository whose first commit time is real (not
// CreatedStandsIn) and that has no line in pull_commits.csv gets its commits
// read, with the request budget reserved first as readPull does, and
// appended. Every stored pull request counts, not only those of the DORA
// window: an installation may widen dora_days later.
//
// data/pull_commits_filled.csv (a mark file, one time per repository) says
// which repositories were filled. A repository is noted only when its fill
// finished, and it is noted at once, not at the end of the run: what it
// filled is already stored. A pull request whose commit list cannot be read
// (github.ErrAnswer, ErrNoCommitDate) is named on stderr and left without
// lines, as readPull has the created time stand in, and does not keep the
// repository from being noted. Otherwise a fill ends as the read of the pull
// requests does:
//
//   - a missing pull-requests: read (ErrPullRequestsDenied) stores what was
//     filled, notes no fill, writes the denied mark and never fails the run;
//   - a budget stop stores what was filled, notes no fill, adds the
//     repository to the report's pull-commits-fill-cut lines and never fails the run, so
//     the next run continues with the pull requests still without lines;
//   - any other error stores what was filled, notes no fill and fails the
//     repository.

import (
	"context"
	"errors"
	"path/filepath"
	"strings"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// PullCommitsFilledFile is the name, next to the history, of the file that
// notes which repositories had the commits of their stored pull requests
// filled (forsgren#470).
const PullCommitsFilledFile = "pull_commits_filled.csv"

// pullCommitsFilledFile is the path of the pull commits filled file next to
// o's history.
func (o Options) pullCommitsFilledFile() string {
	return filepath.Join(filepath.Dir(o.History), PullCommitsFilledFile)
}

// fillPullCommits fills the commits of repo's stored pull requests once; see
// the top of this file for what ends it.
func (o Options) fillPullCommits(ctx context.Context, h held, repo string) error {
	if _, done := h.pullsFilled[strings.ToLower(repo)]; done {
		return nil
	}
	lines, err := o.readFill(ctx, repo, h.pullsWithoutCommits(repo))
	if _, serr := history.AppendPullCommits(o.pullCommitsFile(), lines); serr != nil {
		return serr
	}
	return o.endFill(h, repo, err)
}

// pullsWithoutCommits is the pull requests stored when the run began, of repo
// (ignoring case), whose first commit time is real and that had no line in
// pull_commits.csv, in the order of pulls.csv.
func (h held) pullsWithoutCommits(repo string) []history.PullRequest {
	var todo []history.PullRequest
	for _, p := range h.storedPulls {
		if strings.EqualFold(p.Repository, repo) && h.needsCommits(p) {
			todo = append(todo, p)
		}
	}
	return todo
}

// needsCommits says the stored pull request p has a real first commit time
// and no line in pull_commits.csv.
func (h held) needsCommits(p history.PullRequest) bool {
	return !p.CreatedStandsIn && !h.commitsListed[p.Key()]
}

// readFill is the commit lines of the pull requests todo of repo, up to the
// first error that ends the fill.
func (o Options) readFill(ctx context.Context, repo string, todo []history.PullRequest,
) ([]history.PullCommit, error) {
	var lines []history.PullCommit
	for _, p := range todo {
		if err := o.Client.Reserve(repo, pullCommitPagesAfterFirst); err != nil {
			return lines, err
		}
		listed, _, err := o.Client.PullCommits(ctx, repo, p.Number)
		switch {
		case errors.Is(err, github.ErrAnswer):
			o.warn("collect: %s: pull request %d: the answer for its commits is malformed or unreadable: %v; "+
				"it stays without commit lines\n", repo, p.Number, err)
		case err != nil:
			return lines, err
		default:
			lines = append(lines, pullCommitsOf(repo, p.Number, listed)...)
		}
	}
	return lines, nil
}

// endFill notes repo filled after a fill that ended on err, nil included, and
// says what fails the repository.
func (o Options) endFill(h held, repo string, err error) error {
	switch {
	case errors.Is(err, github.ErrPullRequestsDenied):
		o.noteDenied(h, repo, err)
		return nil
	case errors.Is(err, github.ErrBudget):
		o.warn("collect: %s: the pull request commits were cut short: %v; those filled are stored, "+
			"the rest is filled by the next run\n", repo, err)
		o.reportPullFillCut(repo)
		return nil
	case err != nil:
		return err
	}
	h.pullsFilled[strings.ToLower(repo)] = wholeSecond(o.Now)
	return nil
}
