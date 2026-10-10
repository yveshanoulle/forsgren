package history

import "time"

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

// LoadIssueEvents reads the issue events at path, in file order, with Load's
// errors.
func LoadIssueEvents(path string) ([]IssueEvent, error) {
	return nil, nil
}

// AppendIssueEvents stores the events that the file at path does not hold
// yet, and returns how many it stored, by Append's rules. The new lines are
// in time order (at, repository, issue number, event).
func AppendIssueEvents(path string, events []IssueEvent) (int, error) {
	return 0, nil
}
