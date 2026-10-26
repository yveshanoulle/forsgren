package collect

// What a run holds of the history while it collects: the sources and
// deployments stored, the marks and the files' contents (held), and the
// default branch of each repository asked this run.

import (
	"context"
	"errors"
	"io/fs"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

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
	ids            map[entry]bool
	newest         map[source]time.Time
	oldest         map[source]time.Time // the oldest stored deployment of each source
	successes      map[history.Stream][]history.Record
	failures       map[history.IssueKey]history.Failure
	lastEvents     map[history.IssueKey]history.IssueEvent
	withdrawn      map[history.IssueKey]bool // the failure issues their newest withdrawal line withdraws
	catchUp        *catchUp                  // nil, or the catch-up of a run that found no withdrawn file
	reach          history.Reach             // see chunk.go
	read           history.Reach             // see failuresread.go
	full           history.Reach             // see issueevents.go
	cut            history.Reach             // see bugflags.go
	cutRuns        history.Reach             // see report.go
	checked        history.Reach             // see startscatchup.go
	pullsRead      history.Reach             // see pulls.go
	denied         history.Reach             // see pulls.go: the refused pull request reads
	deniedBy       map[string]string         // see pulls.go: the token name of each, with denied
	pushesRead     history.Reach             // see pushes.go
	pushesDenied   history.Reach             // see pushes.go: the refused push reads
	pushesDeniedBy map[string]string         // see pushes.go: the token name of each, with pushesDenied
	backfilled     history.Reach             // see legacybackfill.go
	pullsFilled    history.Reach             // see pullsfill.go
	pulls          map[history.IssueKey]bool // the pull requests pulls.csv holds
	storedPulls    []history.PullRequest     // the same, in the order of the file, for the fill (pullsfill.go)
	commitsListed  map[history.IssueKey]bool // the pull requests pull_commits.csv holds lines of
	branches       map[string]string         // the default branch of each repository asked this run, by lower-case name
	pushes         map[history.PushKey]bool  // the pushes pushes.csv holds
	startsDone     map[string]bool           // the repositories caught up in this run
	filledDone     map[string]bool           // the repositories whose legacy commits were backfilled in this run
	partial        map[string]bool
}

// loadHeld reads the history at path; a missing file holds nothing.
func loadHeld(path string) (held, error) {
	records, err := history.Load(path)
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return held{}, err
	}
	h := held{ids: map[entry]bool{}, newest: map[source]time.Time{}, oldest: map[source]time.Time{},
		successes: map[history.Stream][]history.Record{}, partial: map[string]bool{}, startsDone: map[string]bool{},
		filledDone: map[string]bool{}, branches: map[string]string{}}
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

// defaultBranch is repo's default branch, asked of GitHub once per run for
// the workflow rule and the push read alike.
func (o Options) defaultBranch(ctx context.Context, h held, repo string) (string, error) {
	key := strings.ToLower(repo)
	if branch, ok := h.branches[key]; ok {
		return branch, nil
	}
	branch, err := o.Client.DefaultBranch(ctx, repo)
	if err == nil {
		h.branches[key] = branch
	}
	return branch, err
}
