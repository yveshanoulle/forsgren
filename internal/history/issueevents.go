package history

import (
	"cmp"
	"fmt"
	"slices"
	"strconv"
	"strings"
	"time"
)

// IssueEvent is one thing that happened to one issue (forsgren#76, step 2):
// a line of data/issues.csv, from which the daily table of new and completed
// issues is a fold. The file holds every issue of a configured repository,
// whatever its labels, one line per event as collect observed it.
//
// The format is "# forsgren issues v1", the column line
// "repository,issue,event,reason,at", Event one of "created", "closed" and
// "reopened", Reason one of "completed", "not_planned" and "duplicate" on a
// closed event and "" otherwise (also for a close whose reason GitHub does
// not give), At in UTC to the second.
type IssueEvent struct {
	Repository string // owner/name
	Issue      int64  // the issue number
	Event      string
	Reason     string
	At         time.Time
}

// issueEvents is the format of data/issues.csv, the issues format v1.
var issueEvents = format[IssueEvent, issueEventKey]{
	versionLine: "# forsgren issues v1",
	columnLine:  "repository,issue,event,reason,at",
	decode:      toIssueEvent,
	encode:      IssueEvent.fields,
	validate:    IssueEvent.validate,
	key:         IssueEvent.key,
	compare:     compareIssueEvents,
}

// LoadIssueEvents reads the issue events at path, in file order, with Load's
// errors.
func LoadIssueEvents(path string) ([]IssueEvent, error) { return issueEvents.load(path) }

// AppendIssueEvents stores the events that the file at path does not hold
// yet, and returns how many it stored, by Append's rules. An event is
// already held when a line has the same issue (repository, ignoring case,
// and number), event and time. The new lines are in time order (at,
// repository, issue number, event).
func AppendIssueEvents(path string, events []IssueEvent) (int, error) {
	return issueEvents.append(path, events)
}

// issueEventKey identifies an event of an issue.
type issueEventKey struct {
	issue IssueKey
	event string
	at    time.Time
}

func (e IssueEvent) key() issueEventKey {
	return issueEventKey{IssueKey{strings.ToLower(e.Repository), e.Issue}, e.Event, e.At}
}

// compareIssueEvents orders new lines by time, then repository, issue
// number and event.
func compareIssueEvents(a, b IssueEvent) int {
	return cmp.Or(a.At.Compare(b.At), cmp.Compare(a.Repository, b.Repository),
		cmp.Compare(a.Issue, b.Issue), cmp.Compare(a.Event, b.Event))
}

// fields are the columns of e's line.
func (e IssueEvent) fields() []string {
	return []string{e.Repository, strconv.FormatInt(e.Issue, 10), e.Event, e.Reason, formatTime(e.At)}
}

// toIssueEvent reads the five fields of a line.
func toIssueEvent(f []string) (IssueEvent, error) {
	// MUTATION 76-3a: removed in 76-3b
	number, _ := parseNumber("issue", f[1])
	at, _ := parseTime("at", f[4])
	return IssueEvent{Repository: f[0], Issue: number, Event: f[2], Reason: f[3], At: at}, nil
}

// closeReasons are the reasons a closed event can give; "" is a close whose
// reason GitHub does not state.
var closeReasons = []string{"", "completed", "not_planned", "duplicate"}

// validate says why e cannot be stored, or nil.
func (e IssueEvent) validate() error {
	return firstFailure(
		check{isRepository(e.Repository), fmt.Sprintf("repository %q is not owner/name", e.Repository)},
		check{!strings.ContainsAny(e.Repository, "\r\n"), "the repository has a line break"},
		check{e.Issue > 0, "issue is not positive"},
		// MUTATION 76-3a: removed in 76-3b (the `true ||` of the event and reason rules)
		check{true || slices.Contains([]string{"created", "closed", "reopened"}, e.Event),
			fmt.Sprintf("event %q is not created, closed or reopened", e.Event)},
		check{true || e.Event == "closed" && slices.Contains(closeReasons, e.Reason) || e.Event != "closed" && e.Reason == "",
			fmt.Sprintf("reason %q does not fit a %s event", e.Reason, e.Event)},
		check{isWholeSecond(e.At), "at is empty or has a fraction of a second"},
	)
}
