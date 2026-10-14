package history

import (
	"cmp"
	"fmt"
	"slices"
	"strconv"
	"strings"
	"time"
)

// ReasonLabelRemoved is the reason of a withdrawal of an issue listed without
// the failure label; ReasonNotPlanned (issueevents.go) is the other, an issue
// closed as not planned.
const ReasonLabelRemoved = "label_removed"

// ReasonIssueGone is the reason of a withdrawal of an issue GitHub no longer
// has: deleted or transferred (forsgren#155).
const ReasonIssueGone = "issue_gone"

// withdrawalReasons are the reasons a line may give, "" for a reinstatement
// first.
var withdrawalReasons = []string{"", ReasonLabelRemoved, ReasonNotPlanned, ReasonIssueGone}

// Withdrawal says whether one failure issue was taken back (forsgren#155): a
// line of data/failures_withdrawn.csv, beside data/failures.csv, for change
// fail rate. An issue that lost its failure label, or was closed as not
// planned, gets a line with Withdrawn true and no longer counts; the file
// only grows, so a later line with Withdrawn false reinstates it. The newest
// line of an issue is the issue (LoadWithdrawals).
//
// The format is "# forsgren failures withdrawn v1", the column line
// "repository,issue,withdrawn,reason,at", Withdrawn "true" or "false".
type Withdrawal struct {
	Repository string // owner/name
	Issue      int64  // the issue number
	Withdrawn  bool
	// Reason is ReasonLabelRemoved, ReasonNotPlanned or ReasonIssueGone while Withdrawn, else "".
	Reason string
	// At is when collect saw it, UTC, whole seconds: the audit trail.
	At time.Time
}

// withdrawals is the format of data/failures_withdrawn.csv, the failures
// withdrawn format v1.
var withdrawals = format[Withdrawal, IssueKey]{
	versionLine: "# forsgren failures withdrawn v1",
	columnLine:  "repository,issue,withdrawn,reason,at",
	decode:      toWithdrawal,
	encode:      Withdrawal.fields,
	validate:    Withdrawal.validate,
	key:         Withdrawal.Key,
	compare:     compareWithdrawals,
	revises:     func(w, held Withdrawal) bool { return w.Withdrawn != held.Withdrawn || w.Reason != held.Reason },
}

// LoadWithdrawals reads the withdrawals at path, with Load's errors: one
// Withdrawal per issue, as its newest line says, in the order the issues
// first appear.
func LoadWithdrawals(path string) ([]Withdrawal, error) {
	lines, err := withdrawals.load(path)
	if err != nil {
		return nil, err
	}
	return newestLines(lines), nil
}

// AppendWithdrawals stores the withdrawals that the file at path does not
// end on yet, and returns how many lines it wrote, by Append's rules but one:
// an issue already held gets a new line when its Withdrawn or Reason differs
// from its newest line, and an unchanged one is not written again.
func AppendWithdrawals(path string, records []Withdrawal) (int, error) {
	return withdrawals.append(path, records)
}

// Key is w's issue.
func (w Withdrawal) Key() IssueKey { return IssueKeyOf(w.Repository, w.Issue) }

// compareWithdrawals orders new lines by repository, then issue number.
func compareWithdrawals(a, b Withdrawal) int {
	return cmp.Or(cmp.Compare(a.Repository, b.Repository), cmp.Compare(a.Issue, b.Issue))
}

// fields are the columns of w's line.
func (w Withdrawal) fields() []string {
	return []string{w.Repository, strconv.FormatInt(w.Issue, 10), strconv.FormatBool(w.Withdrawn), w.Reason,
		formatTime(w.At)}
}

// toWithdrawal reads the five fields of a line; withdrawn is "true" or "false".
func toWithdrawal(f []string) (Withdrawal, error) {
	number, err := parseNumber("issue", f[1])
	if err != nil {
		return Withdrawal{}, err
	}
	if f[2] != "true" && f[2] != "false" {
		return Withdrawal{}, fmt.Errorf("withdrawn %q is not true or false", f[2])
	}
	at, err := parseTime("at", f[4])
	if err != nil {
		return Withdrawal{}, err
	}
	return Withdrawal{Repository: f[0], Issue: number, Withdrawn: f[2] == "true", Reason: f[3], At: at}, nil
}

// validate says why w cannot be stored, or nil.
func (w Withdrawal) validate() error {
	return firstFailure(
		check{isRepository(w.Repository), fmt.Sprintf("repository %q is not owner/name", w.Repository)},
		check{!strings.ContainsAny(w.Repository, "\r\n"), "the repository has a line break"},
		check{w.Issue > 0, "issue is not positive"},
		check{isWholeSecond(w.At), "at is empty or has a fraction of a second"},
		check{w.Withdrawn == (w.Reason != ""), "a withdrawal has a reason and a reinstatement has none"},
		check{slices.Contains(withdrawalReasons, w.Reason),
			fmt.Sprintf("reason %q is not one of %v", w.Reason, withdrawalReasons[1:])},
	)
}
