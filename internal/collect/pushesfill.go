package collect

// The fill of the push commits of the stored merge pushes (forsgren#470,
// step 2). A pr_merge push stored before the push commits format v2 has lines
// with unknown parents and none for the branch commits its merge brought in,
// so the Mainline Lead Time cannot leave its merge commit out and count its
// branch. Once per repository each stored merge push with such a line is
// compared again, with the compare a push read makes (pushCompare), and its
// lines are replaced by the lines a push read writes today
// (history.BackfillPushCommits, the file rewritten whole). Every stored merge
// push counts, not only those of the DORA window. A compare that fails, is
// cut or does not reach the push's tip leaves the push's lines as they are,
// named on stderr, and does not keep the repository from being noted.
//
// The fill runs after the legacy commits backfill and before the push read
// (backfillThenPushes, forsgren#416): the first push read costs one compare
// per push and would starve a repair of data the page already shows. A fill
// cut short by the budget therefore ends the repository's run without the
// push read, so it sends no request after it.
//
// data/push_commits_filled.csv (a mark file, one time per repository) says
// which repositories were filled; it is noted only when the fill finished,
// at once, since what it filled is already stored. A fill ends as the push
// read does:
//
//   - a missing contents: read (a 403 on a compare) stores what was filled,
//     notes no fill, writes the denied mark of the push read and never fails
//     the run;
//   - a budget stop stores what was filled, notes no fill, adds the
//     repository to the report's pushes-cut lines and never fails the run, so
//     the next run continues with the merge pushes still unknown;
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

// PushCommitsFilledFile is the name, next to the history, of the file that
// notes which repositories had the lines of their stored merge pushes filled
// (forsgren#470).
const PushCommitsFilledFile = "push_commits_filled.csv"

// pushCommitsFilledFile is the path of the push commits filled file next to
// o's history.
func (o Options) pushCommitsFilledFile() string {
	return filepath.Join(filepath.Dir(o.History), PushCommitsFilledFile)
}

// tipKey is the identity of a push by its tip: the repository, lower-case, and
// the after SHA.
func tipKey(repository, after string) string { return strings.ToLower(repository) + "@" + after }

// legacyMerges is the pr_merge pushes among pushes that have a line of
// unknown parents among lines, once for each tip: several pushes can share
// one, and its lines are the same.
func legacyMerges(pushes []history.Push, lines []history.PushCommit) []history.Push {
	unknown := map[string]bool{}
	for _, c := range lines {
		k := tipKey(c.Repository, c.After)
		unknown[k] = unknown[k] || c.Parents == history.ParentsUnknown
	}
	var merges []history.Push
	for _, p := range pushes {
		if k := tipKey(p.Repository, p.After); p.Kind == history.PushKindPRMerge && unknown[k] {
			merges = append(merges, p)
			unknown[k] = false
		}
	}
	return merges
}

// fillMergePushes fills the lines of repo's stored merge pushes once; see the
// top of this file for what ends it. It says whether the budget cut the fill
// short, in which case the push read waits for the next run.
func (o Options) fillMergePushes(ctx context.Context, h held, repo string) (bool, error) {
	if _, done := h.mergesFilled[strings.ToLower(repo)]; done {
		return false, nil
	}
	lines, err := o.readMergeFill(ctx, h, repo)
	if _, serr := history.BackfillPushCommits(o.pushCommitsFile(), lines); serr != nil {
		return false, serr
	}
	return o.endMergeFill(h, repo, err)
}

// readMergeFill is the current lines of repo's merge pushes with unknown
// parents, up to the first error that ends the fill.
func (o Options) readMergeFill(ctx context.Context, h held, repo string) ([]history.PushCommit, error) {
	var lines []history.PushCommit
	for _, p := range h.legacyMerges {
		if !strings.EqualFold(p.Repository, repo) {
			continue
		}
		if err := o.Client.Reserve(repo, 1); err != nil {
			return lines, err
		}
		commits, chain, why, err := o.pushCompare(ctx, p)
		switch {
		case err != nil:
			return lines, err
		case why != "":
			o.warn("collect: %s: push %s...%s: %s; its lines stay as they are\n", repo, p.Before, p.After, why)
		default:
			lines = append(lines, pushCommitsOf(p, commits, chain)...)
		}
	}
	return lines, nil
}

// endMergeFill notes repo filled after a fill that ended on err, nil included,
// and says whether the budget cut it short and what fails the repository.
func (o Options) endMergeFill(h held, repo string, err error) (bool, error) {
	switch {
	case github.IsRefused(err):
		o.warn("collect: %v; its push commits are not filled, the rest is collected\n", err)
		o.notePushesDenied(h, repo)
		return false, nil
	case errors.Is(err, github.ErrBudget):
		o.warn("collect: %s: the push commits were cut short: %v; those filled are stored, "+
			"the rest is filled by the next run\n", repo, err)
		o.reportPushesCut(repo)
		return true, nil
	case err != nil:
		return false, err
	}
	h.mergesFilled[strings.ToLower(repo)] = wholeSecond(o.Now)
	return false, nil
}
