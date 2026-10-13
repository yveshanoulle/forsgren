package history

import (
	"cmp"
	"fmt"
	"strconv"
	"strings"
)

// IssueBug says whether one issue carries the bug label (forsgren#126): a
// line of data/issue_bugs.csv, beside data/issues.csv, from which the issues
// pages count the open bugs. The label is the one collect saw at its latest
// read, not the label at the time of each event.
//
// The format is "# forsgren issue bugs v1", the column line
// "repository,issue,bug", Bug "true" or "false". The file only grows, yet a
// label can be removed: an issue gets a new line when its Bug changes, and the
// newest line of an issue is the issue (LoadIssueBugs).
type IssueBug struct {
	Repository string // owner/name
	Issue      int64  // the issue number
	Bug        bool
}

// LoadIssueBugs reads the issue bugs at path, with Load's errors: one IssueBug
// per issue, as its newest line says, in the order the issues first appear.
func LoadIssueBugs(path string) ([]IssueBug, error) {
	lines, err := issueBugs.load(path)
	if err != nil {
		return nil, err
	}
	place := map[IssueKey]int{}
	var out []IssueBug
	for _, b := range lines {
		if i, ok := place[b.Key()]; ok {
			out[i] = b
			continue
		}
		place[b.Key()] = len(out)
		out = append(out, b)
	}
	return out, nil
}

// AppendIssueBugs stores the bug states that the file at path does not end on
// yet, and returns how many lines it wrote, by Append's rules but one: an
// issue already held gets a new line when its Bug differs from its newest
// line, and an unchanged one is not written again.
func AppendIssueBugs(path string, bugs []IssueBug) (int, error) {
	return issueBugs.append(path, bugs)
}

// issueBugs is the format of data/issue_bugs.csv, the issue bugs format v1.
var issueBugs = format[IssueBug, IssueKey]{
	versionLine: "# forsgren issue bugs v1",
	columnLine:  "repository,issue,bug",
	decode:      toIssueBug,
	encode:      IssueBug.fields,
	validate:    IssueBug.validate,
	key:         IssueBug.Key,
	compare:     compareIssueBugs,
	revises:     func(b, held IssueBug) bool { return b.Bug != held.Bug },
}

// Key is b's issue.
func (b IssueBug) Key() IssueKey { return IssueKeyOf(b.Repository, b.Issue) }

// compareIssueBugs orders new lines by repository, then issue number.
func compareIssueBugs(a, b IssueBug) int {
	return cmp.Or(cmp.Compare(a.Repository, b.Repository), cmp.Compare(a.Issue, b.Issue))
}

// fields are the columns of b's line.
func (b IssueBug) fields() []string {
	return []string{b.Repository, strconv.FormatInt(b.Issue, 10), strconv.FormatBool(b.Bug)}
}

// toIssueBug reads the three fields of a line; bug is "true" or "false".
func toIssueBug(f []string) (IssueBug, error) {
	number, err := parseNumber("issue", f[1])
	if err != nil {
		return IssueBug{}, err
	}
	if f[2] != "true" && f[2] != "false" {
		return IssueBug{}, fmt.Errorf("bug %q is not true or false", f[2])
	}
	return IssueBug{Repository: f[0], Issue: number, Bug: f[2] == "true"}, nil
}

// validate says why b cannot be stored, or nil.
func (b IssueBug) validate() error {
	return firstFailure(
		check{isRepository(b.Repository), fmt.Sprintf("repository %q is not owner/name", b.Repository)},
		check{!strings.ContainsAny(b.Repository, "\r\n"), "the repository has a line break"},
		check{b.Issue > 0, "issue is not positive"},
	)
}
