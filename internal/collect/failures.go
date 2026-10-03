package collect

// The failure issues of each repository (forsgren#18, step 3), for change
// fail rate: the issues labelled failure (forsgren#6), open or closed, go
// to data/failures.csv next to the history (FailuresFile).
//
// Each run reads the issues GitHub says were updated in the last 90 days
// (FirstRun), every page up to the client's limit, and stores each one that
// is new or that differs from its newest stored line: one closed or
// reopened since is written again, as a new line, since the file only
// grows, and the newest line of an issue is the issue
// (history.AppendFailures). An issue updated more than 90 days ago is not
// read again, so a change older than that is never seen. An issue stored
// without a failure-start its body gives is named on stderr, once, when it
// is stored: it counts all the same, as change fail rate needs only its
// opening time.

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

// FailuresFile is the name of the failures file, kept next to the history:
// data/failures.csv beside data/deployments.csv.
const FailuresFile = "failures.csv"

// failuresFile is the path of the failures file next to o's history.
func (o Options) failuresFile() string { return filepath.Join(filepath.Dir(o.History), FailuresFile) }

// issueKey identifies an issue: its repository, lower-case, and number.
type issueKey struct {
	repository string
	number     int64
}

func keyOf(f history.Failure) issueKey { return issueKey{strings.ToLower(f.Repository), f.Issue} }

// loadFailures reads the failures file at path, each issue as its newest
// line says; a missing one holds nothing, and is created by the first
// append.
func loadFailures(path string) (map[issueKey]history.Failure, error) {
	stored, err := history.LoadFailures(path)
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return nil, err
	}
	out := make(map[issueKey]history.Failure, len(stored))
	for _, f := range stored {
		out[keyOf(f)] = f
	}
	return out, nil
}

// failureIssues reads repo's failure issues updated in the last 90 days and
// returns those to store: new, or changed since their newest stored line.
func (o Options) failureIssues(ctx context.Context, h held, repo string) ([]history.Failure, error) {
	issues, truncated, err := o.Client.FailureIssues(ctx, repo, o.Now.Add(-FirstRun))
	if err != nil {
		return nil, err
	}
	if truncated {
		o.warn("collect: %s: read the newest %d page(s) of failure issues only; older ones were not read\n",
			repo, o.Client.MaxPages())
	}
	return o.freshFailures(h, repo, issues), nil
}

// freshFailures is the issues of repo to store: new, or changed since their
// newest stored line; each without a failure-start is named on stderr.
func (o Options) freshFailures(h held, repo string, issues []github.Issue) []history.Failure {
	var fresh []history.Failure
	for _, i := range issues {
		f := failureOf(repo, i)
		if stored, ok := h.failures[keyOf(f)]; ok && !f.Revises(stored) {
			continue
		}
		if f.FailureStart.IsZero() {
			o.warn("collect: %s: failure issue #%d has no failure-start line forsgren can read in its body\n",
				repo, i.Number)
		}
		fresh = append(fresh, f)
	}
	return fresh
}

// failureOf is the stored form of one issue of repo: times in UTC, whole
// seconds.
func failureOf(repo string, i github.Issue) history.Failure {
	return history.Failure{
		Repository: repo, Issue: i.Number, OpenedAt: i.CreatedAt.UTC().Truncate(time.Second),
		ClosedAt: i.ClosedAt.UTC().Truncate(time.Second), FailureStart: i.Record.FailureStart,
	}
}
