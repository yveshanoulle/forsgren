package history

import (
	"cmp"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// PushCommit is one commit a push brought to the main branch's first-parent
// chain (forsgren#397, step 3): a line of data/push_commits.csv, for time to
// main per push and the shares of the commits. It holds the author's GitHub
// login, never a name or an email address.
//
// The format is "# forsgren push commits v2", the column line
// "repository,after,sha,author,authored_at,first_parent,parents", After the
// push's after SHA (the key of its line in data/pushes.csv), Author the
// login, empty when GitHub links the commit to no account, AuthoredAt the git
// author date in UTC to the second, first_parent "true" or "false", parents
// the parent count as a decimal, empty when unknown (a root commit has 0).
// The two columns are there for the Mainline Lead Time of every commit, the
// branch commits too (forsgren#463, step 3). A line of the format v1 is read
// as first_parent true with parents unknown, and the first append rewrites
// the file as v2; the empty parents of a line is what later tells data from
// before the change.
type PushCommit struct {
	Repository string // owner/name
	After      string // the after SHA of the push
	SHA        string // the commit, lower-case hex
	Author     string
	AuthoredAt time.Time
	// FirstParent says the commit is on the first-parent chain of its push.
	FirstParent bool
	// Parents is the commit's parent count, ParentsUnknown when not known.
	Parents int
}

// ParentsUnknown is the Parents of a commit whose parent count is not known:
// an empty column. A root commit has 0 parents, so 0 is not unknown.
const ParentsUnknown = -1

// pushCommits is the format of data/push_commits.csv, the push commits
// format v2; v1, without the first_parent and parents columns, is still read.
var pushCommits = format[PushCommit, pushCommitKey]{
	versionLine: "# forsgren push commits v2",
	columnLine:  pushCommitsV1.columnLine + ",first_parent,parents",
	decode:      toPushCommit,
	encode:      PushCommit.fields,
	validate:    PushCommit.validate,
	key:         PushCommit.key,
	compare:     comparePushCommits,
	legacy:      []legacyFormat{pushCommitsV1},
}

// pushCommitsV1 is the push commits format v1, before the first_parent and
// parents columns: every commit it holds is on the chain, its parents unknown.
var pushCommitsV1 = legacyFormat{
	versionLine: "# forsgren push commits v1",
	columnLine:  "repository,after,sha,author,authored_at",
	lift:        func(fields []string) []string { return append(fields, "true", "") },
}

// LoadPushCommits reads the push commits at path, in file order, with Load's
// errors.
func LoadPushCommits(path string) ([]PushCommit, error) { return pushCommits.load(path) }

// AppendPushCommits stores the push commits that the file at path does not
// hold yet, and returns how many it stored, by Append's rules. A commit is
// already held when a line has the same repository (ignoring case), push
// (after SHA) and commit SHA, whatever else it says. The new lines are in
// push order (repository, after), oldest commit first (author date, SHA).
func AppendPushCommits(path string, records []PushCommit) (int, error) {
	return pushCommits.append(path, records)
}

// pushCommitKey identifies a commit of a push.
type pushCommitKey struct{ repository, after, sha string }

// key is c's repository (lower-case), push and commit.
func (c PushCommit) key() pushCommitKey {
	return pushCommitKey{strings.ToLower(c.Repository), c.After, c.SHA}
}

// comparePushCommits orders new lines by repository, push, author date, SHA.
func comparePushCommits(a, b PushCommit) int {
	return cmp.Or(cmp.Compare(a.Repository, b.Repository), cmp.Compare(a.After, b.After),
		a.AuthoredAt.Compare(b.AuthoredAt), cmp.Compare(a.SHA, b.SHA))
}

// fields are the columns of c's line.
func (c PushCommit) fields() []string {
	return []string{c.Repository, c.After, c.SHA, c.Author, formatTime(c.AuthoredAt),
		strconv.FormatBool(c.FirstParent), parentsField(c.Parents)}
}

// parentsField is n as a decimal, an empty column for ParentsUnknown.
func parentsField(n int) string {
	if n == ParentsUnknown {
		return ""
	}
	return strconv.Itoa(n)
}

// parseParents reads the parents column: a decimal of 0 or more, or empty.
func parseParents(s string) (int, error) {
	if s == "" {
		return ParentsUnknown, nil
	}
	n, err := parseNumber("parents", s)
	if err != nil || n < 0 {
		return 0, fmt.Errorf("parents %q is not a whole number of 0 or more, or empty", s)
	}
	return int(n), nil
}

// toPushCommit reads the seven fields of a line.
func toPushCommit(f []string) (PushCommit, error) {
	authored, err := parseTime("authored_at", f[4])
	if err != nil {
		return PushCommit{}, err
	}
	firstParent, err := parseFlag("first_parent", f[5])
	if err != nil {
		return PushCommit{}, err
	}
	parents, err := parseParents(f[6])
	if err != nil {
		return PushCommit{}, err
	}
	return PushCommit{Repository: f[0], After: f[1], SHA: f[2], Author: f[3], AuthoredAt: authored,
		FirstParent: firstParent, Parents: parents}, nil
}

// validate says why c cannot be stored, or nil.
func (c PushCommit) validate() error {
	return firstFailure(
		check{isRepository(c.Repository), fmt.Sprintf("repository %q is not owner/name", c.Repository)},
		check{!strings.ContainsAny(c.Repository, "\r\n"), "repository has a line break"},
		check{isSHA(c.After), fmt.Sprintf("after %q is not 40 or 64 lower-case hex digits", c.After)},
		check{isSHA(c.SHA), fmt.Sprintf("sha %q is not 40 or 64 lower-case hex digits", c.SHA)},
		check{c.Author == "" || IsLogin(c.Author), fmt.Sprintf("author %q is not a GitHub login", c.Author)},
		check{isWholeSecond(c.AuthoredAt), "authored_at is empty or has a fraction of a second"},
		check{c.Parents >= ParentsUnknown, fmt.Sprintf("parents %d is negative", c.Parents)},
	)
}
