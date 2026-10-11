package collect

// The issue events of each repository (forsgren#76, step 4): every issue of
// a configured repository, whatever its labels, turned into the events
// data/issues.csv holds (history.IssueEvent), next to the history
// (IssuesFile).

import (
	"cmp"
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

// IssuesFullFile is the name, next to the history, of the file that notes
// when each repository's issues were read in full (decision #109).
const IssuesFullFile = "issues_full.csv"

// issuesFullFile is the path of the issues full file next to o's history.
func (o Options) issuesFullFile() string {
	return filepath.Join(filepath.Dir(o.History), IssuesFullFile)
}

// issueEvents returns the events of repo's issues to store (decision #100):
// first those of the full read, every issue ever, without a since (decision
// #109), then those of the daily read, the issues updated since the
// repository's read mark, the one the failure issues use (issuesSince,
// decision #101). A repository in the issues full file (h.full) was read in
// full before and is not again; until a run writes that mark, every run does
// the full read. What is already stored is skipped by
// history.AppendIssueEvents, so the two reads and every run add only what is
// new.
func (o Options) issueEvents(ctx context.Context, h held, repo string) ([]history.IssueEvent, error) {
	all, cut, err := o.fullRead(ctx, h, repo)
	if err != nil {
		return nil, err
	}
	if cut {
		o.warn("collect: %s: the full read stopped at %d page(s) of issues; "+
			"the daily collection continues, but older issues and so the historical total stay incomplete\n",
			repo, github.FullReadMaxPages)
	}
	daily, truncated, err := o.Client.Issues(ctx, repo, o.issuesSince(h, repo))
	if err != nil {
		return nil, err
	}
	if truncated {
		o.warn("collect: %s: read the newest %d page(s) of issues only; older ones were not read\n",
			repo, o.Client.MaxPages())
	}
	return append(o.eventsFrom(h, repo, all), o.eventsFrom(h, repo, daily)...), nil
}

// fullRead is every issue of repo, the one full read (decision #109), or none
// for a repository the issues full file already holds; it says whether the
// read stopped at its page cap.
func (o Options) fullRead(ctx context.Context, h held, repo string) ([]github.RepoIssue, bool, error) {
	if _, done := h.full[strings.ToLower(repo)]; done {
		return nil, false, nil
	}
	return o.Client.AllIssues(ctx, repo)
}

// noteFull notes that repo's issues were read in full at at, whole seconds,
// UTC, unless an earlier run did. It is called after the repository's events
// were stored, so a failed store leaves no mark. A full read cut at its page
// limit is noted all the same for now.
func (h held) noteFull(repo string, at time.Time) {
	if _, done := h.full[strings.ToLower(repo)]; !done {
		h.full[strings.ToLower(repo)] = wholeSecond(at)
	}
}

// eventsFrom is the events the snapshots of repo's issues show: each issue's
// created and closed events, and a reopened event at the run's time when the
// issue is open and its last stored event is a close.
func (o Options) eventsFrom(h held, repo string, issues []github.RepoIssue) []history.IssueEvent {
	var events []history.IssueEvent
	for _, i := range issues {
		events = append(events, eventsOf(repo, i)...)
		if i.State == "open" && h.lastEvent(repo, i.Number) == history.EventClosed {
			events = append(events, history.IssueEvent{
				Repository: repo, Issue: i.Number, Event: history.EventReopened, At: wholeSecond(o.Now),
			})
		}
	}
	return events
}

// lastEvent is the event, "created", "closed" or "reopened", that the newest
// stored line of issue number of repo says; "" for an issue not stored.
func (h held) lastEvent(repo string, number int64) string {
	return h.lastEvents[history.IssueKeyOf(repo, number)].Event
}

// loadIssueFiles is h with what the failures file and the issues file hold:
// the failure issues as their newest lines say, and the newest event of each
// issue by time, not by its place in the file, which a later append can put
// an older event after a newer one in. A missing file holds nothing; one that cannot be read refuses the
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
	h.lastEvents = newestEvents(stored)
	return h, nil
}

// newestEvents is the newest event of each issue of events: by time, and of
// two at the same second by the order of an issue's life, created, closed,
// reopened; of two the same in both, the one later in events.
func newestEvents(events []history.IssueEvent) map[history.IssueKey]history.IssueEvent {
	newest := make(map[history.IssueKey]history.IssueEvent, len(events))
	for _, e := range events {
		if last, ok := newest[e.IssueKey()]; !ok || !isOlder(e, last) {
			newest[e.IssueKey()] = e
		}
	}
	return newest
}

// isOlder says whether event a comes before b in an issue's life: earlier, or
// in the same second and earlier in created, closed, reopened.
func isOlder(a, b history.IssueEvent) bool {
	return cmp.Or(a.At.Compare(b.At), eventRank(a.Event)-eventRank(b.Event)) < 0
}

// eventRank is where an event comes in an issue's life: created, then closed,
// then reopened.
func eventRank(event string) int {
	switch event {
	case history.EventCreated:
		return 0
	case history.EventClosed:
		return 1
	}
	return 2
}

// eventsOf is the events one issue of repo shows: created at its creation
// and, when closed, closed at its closing with GitHub's reason.
func eventsOf(repo string, i github.RepoIssue) []history.IssueEvent {
	events := []history.IssueEvent{
		{Repository: repo, Issue: i.Number, Event: history.EventCreated, At: wholeSecond(i.CreatedAt)},
	}
	if !i.ClosedAt.IsZero() {
		events = append(events, history.IssueEvent{
			Repository: repo, Issue: i.Number, Event: history.EventClosed, Reason: i.StateReason, At: wholeSecond(i.ClosedAt),
		})
	}
	return events
}
