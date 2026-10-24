package collect

// The one-time backfill of the legacy commits (forsgren#385): the lines of
// data/commits.csv stored before the commits format v3 have no parents and no
// committer date, and a line stored before v2 no author login either. GitHub
// still knows all three, so once per repository each stored deployment with
// legacy lines is compared with the previous success of its stream, the
// comparison collect uses for a new deployment, and the empty columns of the
// matching lines are filled (history.BackfillCommits, which rewrites the file
// whole). One comparison per deployment, not per commit.
//
// data/commits_backfilled.csv (a mark file, one time per repository) says
// which repositories were backfilled. It is written only when every
// repository of the run finished, like starts_checked.csv, so a run that
// failed or was cut short anywhere does the backfill again for the lines
// still legacy. A line GitHub no longer lists (a rewritten history, a cut
// list) stays legacy with a warning: it does not keep the backfill from being
// marked. The request budget applies: before each comparison one request is
// reserved, and a repository cut short keeps what it filled, writes it whole,
// and is not marked.

import (
	"context"
	"errors"
	"path/filepath"
	"strings"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// CommitsBackfilledFile is the name, next to the history, of the file that
// notes which repositories had their legacy commits backfilled.
const CommitsBackfilledFile = "commits_backfilled.csv"

// commitsBackfilledFile is the path of the commits backfilled file next to
// o's history.
func (o Options) commitsBackfilledFile() string {
	return filepath.Join(filepath.Dir(o.History), CommitsBackfilledFile)
}

// deploymentOf is the deployment a commit line belongs to, in one repository.
type deploymentOf struct {
	kind history.Kind
	id   int64
}

// backfillCut is the budget's cut of repo's backfill: the deployments, issues
// and pull requests were read, the legacy commits not all (forsgren#385).
type backfillCut struct {
	repo string
	err  error
}

func (c *backfillCut) Error() string { return c.err.Error() }
func (c *backfillCut) Unwrap() error { return c.err }

// backfillLegacy fills the legacy commits of repo once. It reads the commits
// file, compares each stored deployment of repo that has legacy lines, newest
// first, and writes what the comparisons gave before it returns, whether they
// all succeeded or not. It notes repo done only when all were tried.
func (o Options) backfillLegacy(ctx context.Context, h held, repo string) error {
	lower := strings.ToLower(repo)
	if _, done := h.backfilled[lower]; done {
		return nil
	}
	// A file that cannot be read has no legacy deployments here, and
	// BackfillCommits, which reads it again, reports why.
	stored, _ := history.LoadCommits(o.commitsFile())
	known, err := o.legacyKnown(ctx, h, repo, legacyDeployments(stored, repo))
	if errors.Is(err, github.ErrBudget) {
		err = &backfillCut{repo, err}
	}
	_, werr := history.BackfillCommits(o.commitsFile(), known)
	if err = errors.Join(err, werr); err == nil {
		h.filledDone[lower] = true
	}
	return err
}

// legacyDeployments is the deployments of repo (ignoring case) that have a
// legacy line among stored.
func legacyDeployments(stored []history.Commit, repo string) map[deploymentOf]bool {
	out := map[deploymentOf]bool{}
	for _, c := range stored {
		if c.Legacy() && strings.EqualFold(c.Repository, repo) {
			out[deploymentOf{c.Kind, c.DeploymentID}] = true
		}
	}
	return out
}

// legacyKnown is the commits GitHub gives for the stored successes of repo in
// deployments, newest first, each compared with its previous success; those
// compared so far when a comparison fails. A success with no previous one has
// no start and is left as it is.
func (o Options) legacyKnown(ctx context.Context, h held, repo string, deployments map[deploymentOf]bool,
) ([]history.Commit, error) {
	todo := h.successesOf(repo, deployments)
	var known []history.Commit
	for _, i := range newestFirst(todo) {
		prev, ok := h.previous(todo[i], nil)
		if !ok {
			continue
		}
		if err := o.Client.Reserve(repo, 1); err != nil {
			return known, err
		}
		commits, why, err := o.comparison(ctx, prev, todo[i])
		if err != nil {
			return known, err
		}
		if why != nil {
			o.warn("collect: backfill: deployment %d: %v; its legacy commits stay without author\n",
				todo[i].ID, why.err)
		}
		known = append(known, commits...)
	}
	return known, nil
}

// successesOf is the stored successes of repo (ignoring case) that are among
// deployments.
func (h held) successesOf(repo string, deployments map[deploymentOf]bool) []history.Record {
	var out []history.Record
	for _, successes := range h.successes {
		for _, r := range successes {
			if strings.EqualFold(r.Repository, repo) && deployments[deploymentOf{r.Kind, r.ID}] {
				out = append(out, r)
			}
		}
	}
	return out
}

// finishBackfilled moves the mark of every repository backfilled in this run
// to the run's time, unless a repository failed or was cut short (failed
// counts both).
func (o Options) finishBackfilled(h held, failed int) {
	if failed > 0 {
		return
	}
	for repo := range h.filledDone {
		if _, done := h.backfilled[repo]; !done {
			h.backfilled[repo] = wholeSecond(o.Now)
		}
	}
}
