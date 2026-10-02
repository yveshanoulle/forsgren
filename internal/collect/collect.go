// Package collect is `forsgren collect` (forsgren#12, step 5): it reads each
// configured repository's deployments from GitHub by the repository's rule
// and appends the final ones to the history (internal/history).
//
// The rules (config v1, forsgren#6):
//
//   - environment=<name>: the GitHub Deployments to that environment. A
//     deployment is a success when any of its statuses was success (GitHub
//     marks a superseded deployment inactive, so the latest status says
//     nothing), a failure when none was and one was failure or error, and
//     not final otherwise. The task, the sha and the deployment's created_at
//     are stored.
//   - workflow=<file>: the runs of that workflow on the default branch,
//     from the repository itself (not a fork). The conclusions success and
//     failure are stored as they are, any other conclusion (cancelled,
//     skipped, timed_out, ...) as other; a run not completed is not final.
//     The run ID, head_sha and run_started_at are stored.
//   - release: the published releases, not drafts and not prereleases, as
//     successes, at their published_at, with their tag's commit and the tag
//     as the task.
//
// How far back it reads: a repository with nothing stored for its rule is
// read 90 days back (FirstRun); after that, from 7 days (Lookback) before
// the newest deployment stored for it, so a deployment that was not final
// at the last run is still found, but never more than 90 days back. Each
// list is cut at the client's page limit, newest first, and stderr says so.
//
// A repository is stored whole or not at all: its records are appended once
// all of them are read. A failure in one repository is printed and the
// others are still collected; Run then fails.
package collect

import (
	"cmp"
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

const (
	// FirstRun is how far back a repository is read when nothing is stored
	// for it yet, and the most any run reads back.
	FirstRun = 90 * 24 * time.Hour
	// Lookback is how far before its newest stored deployment a repository
	// is read again.
	Lookback = 7 * 24 * time.Hour
)

// ErrFailed: at least one repository could not be collected.
var ErrFailed = errors.New("repositories failed")

// Options is what one collect run works with.
type Options struct {
	Client  *github.Client
	History string // the path of data/deployments.csv
	Now     time.Time
	Stdout  io.Writer
	Stderr  io.Writer
}

// Run collects every repository of cfg: one line per repository on stdout,
// `<repo>: <n> new, <m> skipped (not final)`, and an error on stderr for each
// that failed. A history that cannot be read is refused before GitHub is
// asked anything.
func Run(ctx context.Context, cfg config.Config, o Options) error {
	h, err := loadHeld(o.History)
	if err != nil {
		return err
	}
	failed := 0
	for _, p := range cfg.Projects {
		failed += o.collectProject(ctx, h, p)
	}
	if failed > 0 {
		return fmt.Errorf("%d of %d %w", failed, cfg.RepositoryCount(), ErrFailed)
	}
	return nil
}

// collectProject collects the repositories of p and returns how many failed.
func (o Options) collectProject(ctx context.Context, h held, p config.Project) int {
	failed := 0
	for _, r := range p.Repositories {
		if err := o.collectRepository(ctx, h, p.Name, r); err != nil {
			_, _ = fmt.Fprintf(o.Stderr, "collect: %v\n", err)
			failed++
		}
	}
	return failed
}

// collectRepository reads one repository and appends its final deployments.
func (o Options) collectRepository(ctx context.Context, h held, project string, r config.Repository) error {
	f, err := o.fetch(ctx, h, history.Record{Project: project, Repository: r.Name, Name: r.Deployment.Name},
		r.Deployment.Kind)
	if err != nil {
		return err
	}
	n, err := history.Append(o.History, f.records)
	if err != nil {
		return fmt.Errorf("%s: %w", r.Name, err)
	}
	if f.truncated {
		_, _ = fmt.Fprintf(o.Stderr, "collect: %s: read the newest %d page(s) only; older deployments were not read\n",
			r.Name, o.Client.MaxPages())
	}
	_, _ = fmt.Fprintf(o.Stdout, "%s: %d new, %d skipped (not final)\n", r.Name, n, f.notFinal)
	return nil
}

// found is what one repository's rule found.
type found struct {
	records   []history.Record
	notFinal  int
	truncated bool
}

// add counts a deployment that is not final, or keeps the record of one
// that is.
func (f *found) add(r history.Record, final bool) {
	if !final {
		f.notFinal++
		return
	}
	f.records = append(f.records, r)
}

// with is base with one deployment's fields; the time in UTC, whole seconds.
func with(base history.Record, id int64, commit string, at time.Time, state history.State,
	task string,
) history.Record {
	base.ID, base.Commit, base.CreatedAt, base.State, base.Task = id, commit, at.UTC().Truncate(time.Second), state, task
	return base
}

// fetch reads one repository by its rule; base holds the project, the
// repository and the environment or workflow name.
func (o Options) fetch(ctx context.Context, h held, base history.Record, kind config.DeploymentKind) (found, error) {
	switch kind {
	case config.Workflow:
		base.Kind = history.KindWorkflow
		return o.workflow(ctx, h, base)
	case config.Release:
		base.Kind = history.KindRelease
		return o.releases(ctx, h, base)
	default:
		base.Kind = history.KindEnvironment
		return o.environment(ctx, h, base)
	}
}

// environment reads the deployments to one environment and judges each one
// not stored yet by its statuses.
func (o Options) environment(ctx context.Context, h held, base history.Record) (found, error) {
	deployments, truncated, err := o.Client.Deployments(ctx, base.Repository, base.Name, h.since(base, o.Now))
	if err != nil {
		return found{}, err
	}
	f := found{truncated: truncated}
	for _, d := range deployments {
		if h.has(base, d.ID) {
			continue
		}
		statuses, err := o.Client.DeploymentStatuses(ctx, base.Repository, d.ID)
		if err != nil {
			return found{}, err
		}
		state, final := outcome(statuses)
		f.add(with(base, d.ID, d.SHA, d.CreatedAt, state, d.Task), final)
	}
	return f, nil
}

// outcome is a deployment's final state from all its statuses, in any
// order: success when any was success (an inactive after it is GitHub
// marking it superseded); else failure when any was failure or error, which
// is then the latest final one; else not final.
func outcome(statuses []github.DeploymentStatus) (history.State, bool) {
	failed := false
	for _, s := range statuses {
		switch s.State {
		case "success":
			return history.StateSuccess, true
		case "failure", "error":
			failed = true
		}
	}
	return history.StateFailure, failed
}

// workflow reads the runs of one workflow on the default branch.
func (o Options) workflow(ctx context.Context, h held, base history.Record) (found, error) {
	branch, err := o.Client.DefaultBranch(ctx, base.Repository)
	if err != nil {
		return found{}, err
	}
	runs, truncated, err := o.Client.Runs(ctx, base.Repository, base.Name, branch, h.since(base, o.Now))
	if err != nil {
		return found{}, err
	}
	f := found{truncated: truncated}
	for _, r := range runs {
		if !strings.EqualFold(r.HeadRepository.FullName, base.Repository) {
			continue // a fork's run whose branch has the same name
		}
		state, final := conclusion(r)
		f.add(with(base, r.ID, r.HeadSHA, cmp.Or(r.RunStartedAt, r.CreatedAt), state, ""), final)
	}
	return f, nil
}

// conclusion is a run's final state, or not final while it runs.
func conclusion(r github.Run) (history.State, bool) {
	switch {
	case r.Status != "completed" || r.Conclusion == "":
		return "", false
	case r.Conclusion == "success":
		return history.StateSuccess, true
	case r.Conclusion == "failure":
		return history.StateFailure, true
	default:
		return history.StateOther, true
	}
}

// releases reads the published releases and looks up the commit of each one
// not stored yet.
func (o Options) releases(ctx context.Context, h held, base history.Record) (found, error) {
	releases, truncated, err := o.Client.Releases(ctx, base.Repository, h.since(base, o.Now))
	if err != nil {
		return found{}, err
	}
	f := found{truncated: truncated}
	for _, r := range releases {
		if !published(r) || h.has(base, r.ID) {
			continue
		}
		commit, err := o.Client.TagCommit(ctx, base.Repository, r.TagName)
		if err != nil {
			return found{}, err
		}
		f.add(with(base, r.ID, commit, r.PublishedAt, history.StateSuccess, r.TagName), true)
	}
	return f, nil
}

// published says whether a release is a deployment: published, and neither
// a draft nor a prerelease.
func published(r github.Release) bool {
	return !r.Draft && !r.Prerelease && !r.PublishedAt.IsZero()
}

// source is one repository read by one rule.
type source struct {
	repository string
	kind       history.Kind
}

// entry is one deployment in the history.
type entry struct {
	source
	id int64
}

// held is what the history holds: every deployment, and the newest
// created_at of each source.
type held struct {
	ids    map[entry]bool
	newest map[source]time.Time
}

// loadHeld reads the history at path; a missing file holds nothing.
func loadHeld(path string) (held, error) {
	records, err := history.Load(path)
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return held{}, err
	}
	h := held{ids: map[entry]bool{}, newest: map[source]time.Time{}}
	for _, r := range records {
		s := source{r.Repository, r.Kind}
		h.ids[entry{s, r.ID}] = true
		if r.CreatedAt.After(h.newest[s]) {
			h.newest[s] = r.CreatedAt
		}
	}
	return h, nil
}

// has says whether the deployment id of base's source is stored.
func (h held) has(base history.Record, id int64) bool {
	return h.ids[entry{source{base.Repository, base.Kind}, id}]
}

// since is where a run reads base's source from: Lookback before its newest
// stored deployment, but never before FirstRun ago.
func (h held) since(base history.Record, now time.Time) time.Time {
	from := h.newest[source{base.Repository, base.Kind}].Add(-Lookback)
	return later(from, now.Add(-FirstRun))
}

func later(a, b time.Time) time.Time {
	if a.After(b) {
		return a
	}
	return b
}
