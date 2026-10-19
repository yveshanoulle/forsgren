// Package collect is `forsgren collect` (forsgren#12, step 5): it reads each
// configured repository's deployments from GitHub by the repository's rule
// and appends the final ones to the history (internal/history).
//
// The rules (config v1, forsgren#6):
//
//   - environment=<name>: the GitHub Deployments to that environment. A
//     deployment is a success when any of its statuses was success (GitHub
//     marks a superseded deployment inactive, so the latest status says
//     nothing), a failure when none was and its newest status other than
//     inactive is failure or error, and not final otherwise: still running,
//     or retried after a failure. The task, the sha and the deployment's
//     created_at are stored.
//   - workflow=<file>: the runs of that workflow on the default branch,
//     from the repository itself (not a fork). The conclusions success and
//     failure are stored as they are, any other conclusion (cancelled,
//     skipped, timed_out, ...) as other; a run not completed is not final.
//     The run ID, head_sha and run_started_at are stored. A re-run keeps
//     its run ID, so a run stored when its first attempt failed keeps that
//     outcome: the history's key is the run ID (forsgren#12, step 8).
//   - release: the published releases, not drafts and not prereleases, as
//     successes, at their published_at, with their tag's commit and the tag
//     as the task.
//
// How far back it reads: a repository with nothing stored for its rule is
// read history_days back (365 by default, forsgren#57); after that, from 7
// days (Lookback) before the newest deployment stored for it, so a
// deployment that was not final at the last run is still found, but never
// more than history_days back. A
// deployment still not final more than 7 days before the newest stored one
// is therefore never stored. Each list is cut at the client's page limit,
// newest first, and stderr says so. A repository's names in the config and
// the history are compared ignoring case.
//
// The commits of each deployment (forsgren#16, step 3), for lead time, go to
// data/commits.csv next to the history (CommitsFile). Each success this run
// stores is compared with the previous success of its stream (the same
// repository, ignoring case, rule, environment or workflow, and task; a
// release's task is its tag, so a repository's releases are one stream),
// from the history or from this run, by created_at, then ID. The first
// success of a stream gets no commits; a failure or another final state is
// never a previous and gets none, so its commits roll on to the next
// success. Only the deployments this run stores are compared, so a
// deployment is compared once: a skipped one is not tried again. A list
// GitHub cut, a previous that is not an ancestor and a commit GitHub does
// not have store no commits for that deployment, with a warning on stderr;
// any other error of a comparison fails the repository. A success that
// finished between two successes of its stream stored by earlier runs is
// not compared and stores no commits either, with a warning: the newer one
// was compared with the success before both, so its commits already hold
// this one's (forsgren#16, step 7). A success older than the oldest stored
// one is backfilled and compared with the success before it; the oldest
// stored success waits for a previous, and is compared on the run that
// reads one (backfill.go, forsgren#66).
//
// A repository is stored whole or not at all: its records are appended once
// all of them are read and compared, the commits first, then the
// deployments, so a deployment is never stored without its commits. When a
// write fails, the next run reads and compares those deployments again, and
// the commits already stored are skipped by their key. A failure in one
// repository is printed and the others are still collected; Run then fails.
//
// The request budget (forsgren#64): once GitHub's answers say fewer requests
// are left than the client's margin, a repository is cut short, not failed:
// it stores nothing and moves no read mark, stderr names it with the reset
// time, the repositories already done keep what they stored, and Run does
// not fail for it. The next run reads it again.
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
	// Lookback is how far before its newest stored deployment a repository
	// is read again.
	Lookback = 7 * 24 * time.Hour
)

// ErrFailed: at least one repository could not be collected.
var ErrFailed = errors.New("repositories failed")

// Options is what one collect run works with.
type Options struct {
	Client *github.Client
	// History is the path of data/deployments.csv; the commits, the failure
	// issues and the issue events go next to it.
	History string
	Now     time.Time
	Stdout  io.Writer
	Stderr  io.Writer
	// Report, when set, is filled with what the run left incomplete or failed
	// (report.go, forsgren#64).
	Report *Report

	// earliest is the most any run reads back: history_days before Now; and
	// chunk is history_chunk_days, how much a run reads of a repository's
	// history at once. Both are set by Run (forsgren#57).
	earliest time.Time
	chunk    time.Duration
	// counting is how far back a closed failure issue was opened to be re-read
	// by the catch-up: the DORA window, dora_days (forsgren#178). Set by Run.
	counting time.Duration
}

// Run collects every repository of cfg: one line per repository on stdout,
// `<repo>: <n> new, <m> skipped (not final), <c> commits`, followed by
// `, <f> failure issues` when it stored any, and an error on stderr for
// each that failed. A history, a commits file, a failures file or an issues
// file that cannot be read is refused before GitHub is asked anything.
func Run(ctx context.Context, cfg config.Config, o Options) error {
	o = o.windowOf(cfg)
	o.Client.WithBudgetMargin()
	h, err := loadHeld(o.History)
	if err != nil {
		return err
	}
	if err := checkCommits(o.commitsFile()); err != nil {
		return err
	}
	if h, err = o.loadIssueFiles(h); err != nil {
		return err
	}
	if h, err = o.loadMarks(h); err != nil {
		return err
	}
	before := o.marks(h)
	var done tally
	for _, p := range cfg.Projects {
		done = done.plus(o.collectProject(ctx, h, p))
	}
	o.closeReport()
	return o.finish(h, before, done, cfg.RepositoryCount())
}

// tally is how a run's repositories ended besides done: failed, or cut short
// at the request budget's margin (forsgren#64).
type tally struct{ failed, cut int }

// plus is t and u added up.
func (t tally) plus(u tally) tally { return tally{t.failed + u.failed, t.cut + u.cut} }

// collectProject collects the repositories of p and returns how many failed
// and how many were cut short. A repository cut short stores nothing and
// moves no read mark, the next run reads it again, and it is no failure: the
// request budget's margin was reached (github.ErrBudget), and stderr says
// when it resets.
func (o Options) collectProject(ctx context.Context, h held, p config.Project) tally {
	var t tally
	for _, r := range p.Repositories {
		err := o.collectRepository(ctx, h, p.Name, r)
		switch {
		case errors.Is(err, github.ErrBudget):
			_, _ = fmt.Fprintf(o.Stderr, "collect: cut short: %v\n", err)
			t.cut++
			o.reportCut(err)
		case err != nil:
			_, _ = fmt.Fprintf(o.Stderr, "collect: %v\n", err)
			t.failed++
			o.reportFailed(r.Name, err)
		}
	}
	return t
}

// collectRepository reads one repository and appends its final deployments,
// the commits of the new successes, its new or changed failure issues and
// the new events of its issues.
func (o Options) collectRepository(ctx context.Context, h held, project string, r config.Repository) error {
	d, err := o.deploymentsOf(ctx, h, project, r)
	if err != nil {
		return o.keepWhole(h, r.Name, d, err)
	}
	lines, err := o.readIssues(ctx, h, r.Name)
	if err != nil {
		d.recent = RecentRead
		return o.keepWhole(h, r.Name, d, err)
	}
	stored, err := o.store(batch{d.records, d.commits, lines.failures, lines.withdrawals, lines.events, lines.bugs})
	if err != nil {
		return fmt.Errorf("%s: %w", r.Name, err)
	}
	h.noteReach(r.Name, d.reach)
	h.noteCutDone(r.Name)
	h.noteRead(r.Name, o.Now)
	h.noteFull(r.Name, o.Now)
	h.noteBugsCut(r.Name, lines.bugsCut, o.Now)
	o.report(r.Name, d.found, stored)
	return nil
}

// issueLines is what one repository's issues give to store: its failure
// issues, the events of all its issues and their bug flags.
type issueLines struct {
	failures    []history.Failure
	withdrawals []history.Withdrawal
	events      []history.IssueEvent
	bugs        []history.IssueBug
	// bugsCut is whether the bug read stopped at the page cap (forsgren#140).
	bugsCut bool
}

// readIssues reads repo's failure issues, the events of its issues and their
// bug flags.
func (o Options) readIssues(ctx context.Context, h held, repo string) (issueLines, error) {
	var l issueLines
	var err error
	if l.failures, err = o.failureIssues(ctx, h, repo); err != nil {
		return l, err
	}
	var daily []github.RepoIssue
	if l.events, daily, err = o.issueEvents(ctx, h, repo); err != nil {
		return l, err
	}
	if l.withdrawals, err = o.withdrawalsOf(ctx, h, repo, daily); err != nil {
		return l, err
	}
	l.bugs, l.bugsCut, err = o.bugFlags(ctx, repo)
	return l, err
}

// report prints what one repository stored on stdout, after a warning on
// stderr when its deployments were cut at the page limit.
func (o Options) report(repo string, f found, stored counts) {
	if f.truncated {
		o.warn("collect: %s: read the newest %d page(s) only; older deployments were not read\n",
			repo, o.Client.MaxPages())
	}
	line := fmt.Sprintf("%s: %d new, %d skipped (not final), %d commits", repo, stored.deployments, f.notFinal,
		stored.commits)
	if stored.failures > 0 {
		line += fmt.Sprintf(", %d failure issues", stored.failures)
	}
	_, _ = fmt.Fprintln(o.Stdout, line)
}

// batch is what one repository stores.
type batch struct {
	records     []history.Record
	commits     []history.Commit
	failures    []history.Failure
	withdrawals []history.Withdrawal
	events      []history.IssueEvent
	bugs        []history.IssueBug
}

// counts is how many lines of each file a batch stored.
type counts struct{ deployments, commits, failures int }

// store appends one repository's commits, then its failure issues, then its
// issue events, then their bug flags, then its deployments, and says how many
// commits, failure issues and deployments it stored. Deployments the history
// refuses write nothing. The commits go first: when any write fails, the
// deployments are not stored, so the next run reads them again and
// compares them again, and the commits, failure issues and issue events
// already stored are skipped. A deployment is never stored without its commits.
func (o Options) store(b batch) (counts, error) {
	var c counts
	if err := history.Validate(o.History, b.records); err != nil {
		return c, err
	}
	var err error
	if c.commits, err = history.AppendCommits(o.commitsFile(), b.commits); err != nil {
		return c, err
	}
	if c.failures, err = history.AppendFailures(o.failuresFile(), b.failures); err != nil {
		return c, err
	}
	if err = o.appendIssueLines(b); err != nil {
		return c, err
	}
	c.deployments, err = history.Append(o.History, b.records)
	return c, err
}

// appendIssueLines appends a batch's withdrawals, none writing nothing (a
// catch-up holds them until finishCatchUp), then its events, then its bug flags.
func (o Options) appendIssueLines(b batch) error {
	if len(b.withdrawals) > 0 {
		if _, err := history.AppendWithdrawals(o.withdrawnFile(), b.withdrawals); err != nil {
			return err
		}
	}
	if _, err := history.AppendIssueEvents(o.issuesFile(), b.events); err != nil {
		return err
	}
	_, err := history.AppendIssueBugs(o.bugsFile(), b.bugs)
	return err
}

// found is what one repository's rule found.
type found struct {
	records   []history.Record
	notFinal  int
	truncated bool
	// successes is how many of records are successes, each owed a comparison.
	successes int
	// win is the windows the repository was read in (cutshort.go), and recent
	// what became of its recent read when a budget cut ended it (Recent*).
	win    windows
	recent string
	// oldest is the creation time of the oldest item read, and reach where
	// the repository's reach moves to (zero: it stays), see chunk.go.
	oldest, reach time.Time
}

// add counts a deployment that is not final, or keeps the record of one
// that is.
func (f *found) add(r history.Record, final bool) {
	if !final {
		f.notFinal++
		return
	}
	f.records = append(f.records, r)
	if r.State == history.StateSuccess {
		f.successes++
	}
}

// with is base with one deployment's fields; the time in UTC, whole seconds.
func with(base history.Record, id int64, commit string, at time.Time, state history.State,
	task string,
) history.Record {
	base.ID, base.Commit, base.CreatedAt, base.State, base.Task = id, commit, at.UTC().Truncate(time.Second), state, task
	return base
}

// fetch reads one repository by its rule, the part of its list in span; base
// holds the project, the repository, the kind and the environment or
// workflow name.
func (o Options) fetch(ctx context.Context, h held, base history.Record, span github.Span, owed int) (found, error) {
	switch base.Kind {
	case history.KindWorkflow:
		return o.workflow(ctx, h, base, span)
	case history.KindRelease:
		return o.releases(ctx, h, base, span, owed)
	default:
		return o.environment(ctx, h, base, span, owed)
	}
}

// environment reads the deployments to one environment and judges each one
// not stored yet by its statuses.
func (o Options) environment(ctx context.Context, h held, base history.Record, span github.Span,
	owed int,
) (found, error) {
	deployments, truncated, err := o.Client.Deployments(ctx, base.Repository, base.Name, span)
	if err != nil {
		return found{}, cutAt(err, time.Time{})
	}
	f := found{truncated: truncated}
	for _, d := range deployments {
		f.see(d.CreatedAt)
		if h.has(base, d.ID) {
			continue
		}
		statuses, err := o.statusesOf(ctx, base.Repository, d.ID, owed+f.successes)
		if err != nil {
			return f, cutAt(err, d.CreatedAt)
		}
		state, final := outcome(statuses)
		f.add(with(base, d.ID, d.SHA, d.CreatedAt, state, d.Task), final)
	}
	return f, nil
}

// outcome is a deployment's final state from all its statuses, in any
// order: success when any was success (an inactive after it is GitHub
// marking it superseded); else failure when the newest status that is not
// inactive is failure or error; else not final, also when that newest
// status is a retry (in_progress, queued, pending) after a failure.
func outcome(statuses []github.DeploymentStatus) (history.State, bool) {
	var newest github.DeploymentStatus
	for _, s := range statuses {
		switch {
		case s.State == "success":
			return history.StateSuccess, true
		case s.State != "inactive" && newer(s, newest):
			newest = s
		}
	}
	switch newest.State {
	case "failure", "error":
		return history.StateFailure, true
	}
	return "", false
}

// newer says whether status a came after b: by its time, and by its ID
// when two share a second.
func newer(a, b github.DeploymentStatus) bool {
	if a.CreatedAt.Equal(b.CreatedAt) {
		return a.ID > b.ID
	}
	return a.CreatedAt.After(b.CreatedAt)
}

// workflow reads the runs of one workflow on the default branch.
func (o Options) workflow(ctx context.Context, h held, base history.Record, span github.Span) (found, error) {
	branch, err := o.Client.DefaultBranch(ctx, base.Repository)
	if err != nil {
		return found{}, cutAt(err, time.Time{})
	}
	runs, truncated, err := o.Client.Runs(ctx, base.Repository, base.Name, branch, span)
	if err != nil {
		return found{}, cutAt(err, time.Time{})
	}
	f := found{truncated: truncated}
	for _, r := range runs {
		f.see(r.CreatedAt)
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
func (o Options) releases(ctx context.Context, h held, base history.Record, span github.Span,
	owed int,
) (found, error) {
	releases, truncated, err := o.Client.Releases(ctx, base.Repository, span)
	if err != nil {
		return found{}, cutAt(err, time.Time{})
	}
	f := found{truncated: truncated}
	for _, r := range releases {
		f.see(r.PublishedAt)
		if !published(r) || h.has(base, r.ID) {
			continue
		}
		commit, err := o.tagCommitOf(ctx, base.Repository, r.TagName, owed+f.successes)
		if err != nil {
			return f, cutAt(err, r.PublishedAt)
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

// source is one repository read by one rule. The repository is lower-case:
// GitHub's repository names ignore case, and so do the config and the
// history's key, so a line of Acme/App is acme/app's.
type source struct {
	repository string
	kind       history.Kind
}

// sourceOf is the source of r's repository and kind.
func sourceOf(r history.Record) source {
	return source{strings.ToLower(r.Repository), r.Kind}
}

// entry is one deployment in the history.
type entry struct {
	source
	id int64
}

// held is what the history holds: every deployment, the newest created_at
// of each source, and the successes of each stream; each failure issue
// stored, as its newest line says; the last stored event of each issue (see
// issueevents.go); and the repositories whose full read stopped at its page
// cap this run (partial).
type held struct {
	ids        map[entry]bool
	newest     map[source]time.Time
	oldest     map[source]time.Time // the oldest stored deployment of each source
	successes  map[history.Stream][]history.Record
	failures   map[history.IssueKey]history.Failure
	lastEvents map[history.IssueKey]history.IssueEvent
	withdrawn  map[history.IssueKey]bool // the failure issues their newest withdrawal line withdraws
	catchUp    *catchUp                  // nil, or the catch-up of a run that found no withdrawn file
	reach      history.Reach             // see chunk.go
	read       history.Reach             // see failuresread.go
	full       history.Reach             // see issueevents.go
	cut        history.Reach             // see bugflags.go
	cutRuns    history.Reach             // see report.go
	partial    map[string]bool
}

// loadHeld reads the history at path; a missing file holds nothing.
func loadHeld(path string) (held, error) {
	records, err := history.Load(path)
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return held{}, err
	}
	h := held{ids: map[entry]bool{}, newest: map[source]time.Time{}, oldest: map[source]time.Time{},
		successes: map[history.Stream][]history.Record{}, partial: map[string]bool{}}
	for _, r := range records {
		h.hold(r)
	}
	return h, nil
}

// hold notes one stored deployment.
func (h held) hold(r history.Record) {
	s := sourceOf(r)
	h.ids[entry{s, r.ID}] = true
	if r.CreatedAt.After(h.newest[s]) {
		h.newest[s] = r.CreatedAt
	}
	if old, ok := h.oldest[s]; !ok || r.CreatedAt.Before(old) {
		h.oldest[s] = r.CreatedAt
	}
	if r.State == history.StateSuccess {
		h.successes[r.Stream()] = append(h.successes[r.Stream()], r)
	}
}

// has says whether the deployment id of base's source is stored.
func (h held) has(base history.Record, id int64) bool {
	return h.ids[entry{sourceOf(base), id}]
}

// later is the later of a and b.
func later(a, b time.Time) time.Time {
	if a.After(b) {
		return a
	}
	return b
}
