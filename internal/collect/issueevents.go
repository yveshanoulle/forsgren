package collect

// The issue events of each repository (forsgren#76, step 4): every issue of
// a configured repository, whatever its labels, turned into the events
// data/issues.csv holds (history.IssueEvent), next to the history
// (IssuesFile).

import (
	"context"
	"path/filepath"
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
		events = append(events, eventsOf(repo, i)...)
	}
	return events, nil
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
