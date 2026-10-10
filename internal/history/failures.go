package history

import (
	"cmp"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// Failure is one state of one failure issue (forsgren#18, step 1): an issue
// labelled `failure` in a configured repository (forsgren#6), a line of
// data/failures.csv, for change fail rate.
//
// The file only grows, yet an issue changes: it is closed, or reopened. So
// a line is one state of an issue as collect saw it, and an issue gets a new
// line whenever what it says changes; the newest line of an issue is the
// issue (LoadFailures).
type Failure struct {
	Repository string // owner/name
	Issue      int64  // the issue number
	OpenedAt   time.Time
	// ClosedAt is zero while the issue is open.
	ClosedAt time.Time
	// FailureStart is the issue's `failure-start:` line, when users were
	// first hit; zero when its body gives none that forsgren can read.
	FailureStart time.Time
}

// failures is the format of data/failures.csv, the failures format v1.
var failures = format[Failure, IssueKey]{
	versionLine: "# forsgren failures v1",
	columnLine:  "repository,issue,opened_at,closed_at,failure_start",
	decode:      toFailure,
	encode:      Failure.fields,
	validate:    Failure.validate,
	key:         Failure.Key,
	compare:     compareFailures,
	revises:     Failure.Revises,
}

// LoadFailures reads the failure issues at path, with Load's errors: one
// Failure per issue, as its newest line says, in the order the issues first
// appear in the file.
func LoadFailures(path string) ([]Failure, error) {
	lines, err := failures.load(path)
	if err != nil {
		return nil, err
	}
	return newestLines(lines), nil
}

// AppendFailures stores the states of failure issues that the file at path
// does not end on yet, and returns how many lines it wrote, by Append's
// rules but one: an issue (its repository, ignoring case, and its number)
// already held gets a new line when it differs from its newest line, so a
// closed or reopened issue is written again, and an unchanged one is not.
// The new lines are in opening order (opened at, repository, issue number);
// two states of one issue in one call keep their order, the later one last.
func AppendFailures(path string, records []Failure) (int, error) {
	return failures.append(path, records)
}

// IssueKey identifies an issue: its repository, lower-case, as GitHub's
// names ignore case, and its number. collect keys the issues it holds by it
// too, so the two never tell issues apart differently.
type IssueKey struct {
	Repository string
	Number     int64
}

// IssueKeyOf is the key of issue number of repository: the one place the
// repository's case is dropped, for the failures file, the issues file and
// collect alike.
func IssueKeyOf(repository string, number int64) IssueKey {
	return IssueKey{strings.ToLower(repository), number}
}

// Key is f's issue.
func (f Failure) Key() IssueKey { return IssueKeyOf(f.Repository, f.Issue) }

// Revises says whether f says something else than held, the newest line of
// its issue: any time, whatever the repository's case. AppendFailures
// writes f as a new line exactly then.
func (f Failure) Revises(held Failure) bool {
	return !f.OpenedAt.Equal(held.OpenedAt) || !f.ClosedAt.Equal(held.ClosedAt) ||
		!f.FailureStart.Equal(held.FailureStart)
}

// newestLines is one Failure per issue, its newest line, in the order the
// issues first appear in lines.
func newestLines(lines []Failure) []Failure {
	place := map[IssueKey]int{}
	var out []Failure
	for _, f := range lines {
		if i, ok := place[f.Key()]; ok {
			out[i] = f
			continue
		}
		place[f.Key()] = len(out)
		out = append(out, f)
	}
	return out
}

// compareFailures orders new lines by opening time, then repository, then
// issue number.
func compareFailures(a, b Failure) int {
	return cmp.Or(a.OpenedAt.Compare(b.OpenedAt), cmp.Compare(a.Repository, b.Repository),
		cmp.Compare(a.Issue, b.Issue))
}

// fields are the columns of f's line; a zero time is an empty column.
func (f Failure) fields() []string {
	return []string{
		f.Repository, strconv.FormatInt(f.Issue, 10), formatTime(f.OpenedAt), formatTime(f.ClosedAt),
		formatTime(f.FailureStart),
	}
}

// formatTime is t as the files write it, or "" for the zero time.
func formatTime(t time.Time) string {
	if t.IsZero() {
		return ""
	}
	return t.UTC().Format(timeLayout)
}

// toFailure reads the five fields of a line.
func toFailure(f []string) (Failure, error) {
	number, err := parseNumber("issue", f[1])
	if err != nil {
		return Failure{}, err
	}
	opened, err := parseTime("opened_at", f[2])
	if err != nil {
		return Failure{}, err
	}
	closedAt, err := parseOptionalTime("closed_at", f[3])
	if err != nil {
		return Failure{}, err
	}
	start, err := parseOptionalTime("failure_start", f[4])
	if err != nil {
		return Failure{}, err
	}
	return Failure{Repository: f[0], Issue: number, OpenedAt: opened, ClosedAt: closedAt, FailureStart: start}, nil
}

// validate says why f cannot be stored, or nil.
func (f Failure) validate() error {
	return firstFailure(
		check{isRepository(f.Repository), fmt.Sprintf("repository %q is not owner/name", f.Repository)},
		check{!strings.ContainsAny(f.Repository, "\r\n"), "the repository has a line break"},
		check{f.Issue > 0, "issue is not positive"},
		check{isWholeSecond(f.OpenedAt), "opened_at is empty or has a fraction of a second"},
		check{isOptionalWholeSecond(f.ClosedAt), "closed_at has a fraction of a second"},
		check{isOptionalWholeSecond(f.FailureStart), "failure_start has a fraction of a second"},
	)
}

// isOptionalWholeSecond says whether t is zero or has no fraction of a
// second.
func isOptionalWholeSecond(t time.Time) bool { return t.IsZero() || isWholeSecond(t) }
