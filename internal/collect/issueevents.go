package collect

// The issue events of each repository (forsgren#76, step 4): every issue of
// a configured repository, whatever its labels, turned into the events
// data/issues.csv holds (history.IssueEvent), next to the history
// (IssuesFile).

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

// IssuesFile is the name of the issue events file, kept next to the history:
// data/issues.csv beside data/deployments.csv.
const IssuesFile = "issues.csv"

// issuesFile is the path of the issue events file next to o's history.
func (o Options) issuesFile() string { return filepath.Join(filepath.Dir(o.History), IssuesFile) }

// issueEvents reads repo's issues updated since the repository's read mark
// (failuresSince) and returns the events to store.
func (o Options) issueEvents(ctx context.Context, h held, repo string) ([]history.IssueEvent, error) {
	issues, _, err := o.Client.Issues(ctx, repo, o.failuresSince(h, repo))
	if err != nil {
		return nil, err
	}
	var events []history.IssueEvent
	for _, i := range issues {
		// MUTATION 76-6a: removed in 76-6b
		if h.lastEvent(repo, i.Number) == "reopened" {
			events = append(events, eventsOf(repo, i)[0])
			continue
		}
		events = append(events, eventsOf(repo, i)...)
		if i.State == "open" && h.lastEvent(repo, i.Number) == "closed" {
			events = append(events, history.IssueEvent{
				Repository: repo, Issue: i.Number, Event: "reopened", At: wholeSecond(o.Now),
			})
		}
	}
	return events, nil
}

// lastEvent is the event, "created", "closed" or "reopened", that the last
// stored line of issue number of repo says; "" for an issue not stored.
func (h held) lastEvent(repo string, number int64) string {
	return h.events[history.IssueKey{Repository: strings.ToLower(repo), Number: number}]
}

// loadIssueFiles is h with what the failures file and the issues file hold:
// the failure issues as their newest lines say, and the last event of each
// issue. A missing file holds nothing; one that cannot be read refuses the
// run.
func (o Options) loadIssueFiles(h held) (held, error) {
	var err error
	if h.failures, err = loadFailures(o.failuresFile()); err != nil {
		return h, err
	}
	stored, err := history.LoadIssueEvents(o.issuesFile())
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return h, err
	}
	h.events = make(map[history.IssueKey]string, len(stored))
	for _, e := range stored {
		h.events[history.IssueKey{Repository: strings.ToLower(e.Repository), Number: e.Issue}] = e.Event
	}
	return h, nil
}

// eventsOf is the events one issue of repo shows: created at its creation
// and, when closed, closed at its closing with GitHub's reason.
func eventsOf(repo string, i github.RepoIssue) []history.IssueEvent {
	events := []history.IssueEvent{{Repository: repo, Issue: i.Number, Event: "created", At: wholeSecond(i.CreatedAt)}}
	if !i.ClosedAt.IsZero() {
		events = append(events, history.IssueEvent{
			Repository: repo, Issue: i.Number, Event: "closed", Reason: i.StateReason, At: wholeSecond(i.ClosedAt),
		})
	}
	return events
}

// wholeSecond is t in UTC, whole seconds.
func wholeSecond(t time.Time) time.Time { return t.UTC().Truncate(time.Second) }
