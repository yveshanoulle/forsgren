package history

import (
	"cmp"
	"fmt"
	"strings"
	"time"
)

// PushCommit is one commit a push brought to the main branch's first-parent
// chain (forsgren#397, step 3): a line of data/push_commits.csv, for time to
// main per push and the shares of the commits. It holds the author's GitHub
// login, never a name or an email address.
//
// The format is "# forsgren push commits v1", the column line
// "repository,after,sha,author,authored_at", After the push's after SHA (the
// key of its line in data/pushes.csv), Author the login, empty when GitHub
// links the commit to no account, AuthoredAt the git author date in UTC to
// the second.
type PushCommit struct {
	Repository string // owner/name
	After      string // the after SHA of the push
	SHA        string // the commit, lower-case hex
	Author     string
	AuthoredAt time.Time
}

// pushCommits is the format of data/push_commits.csv, the push commits
// format v1.
var pushCommits = format[PushCommit, pushCommitKey]{
	versionLine: "# forsgren push commits v1",
	columnLine:  "repository,after,sha,author,authored_at",
	decode:      toPushCommit,
	encode:      PushCommit.fields,
	validate:    PushCommit.validate,
	key:         PushCommit.key,
	compare:     comparePushCommits,
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
	return []string{c.Repository, c.After, c.SHA, c.Author, formatTime(c.AuthoredAt)}
}

// toPushCommit reads the five fields of a line.
func toPushCommit(f []string) (PushCommit, error) {
	authored, err := parseTime("authored_at", f[4])
	if err != nil {
		return PushCommit{}, err
	}
	return PushCommit{Repository: f[0], After: f[1], SHA: f[2], Author: f[3], AuthoredAt: authored}, nil
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
	)
}
