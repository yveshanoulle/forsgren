package history

import (
	"cmp"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// PullCommit is one commit of a merged pull request's commit list
// (forsgren#463, step 5): a line of data/pull_commits.csv, for the Mainline
// Lead Time of a squash merge, where the originals' own author dates stand in
// for the squash commit's (decisions #465 and #466). It holds the author's
// GitHub login, never a name or an email address.
//
// The format is "# forsgren pull commits v1", the column line
// "repository,number,sha,author,authored_at", Number the pull request's
// number, Author the login, empty when GitHub links the commit to no account,
// AuthoredAt the git author date in UTC to the second.
type PullCommit struct {
	Repository string // owner/name
	Number     int64  // the pull request number
	SHA        string // the commit, lower-case hex
	Author     string
	AuthoredAt time.Time
}

// pullCommits is the format of data/pull_commits.csv, the pull commits
// format v1.
var pullCommits = format[PullCommit, pullCommitKey]{
	versionLine: "# forsgren pull commits v1",
	columnLine:  "repository,number,sha,author,authored_at",
	decode:      toPullCommit,
	encode:      PullCommit.fields,
	validate:    PullCommit.validate,
	key:         PullCommit.key,
	compare:     comparePullCommits,
}

// LoadPullCommits reads the pull commits at path, in file order, with Load's
// errors.
func LoadPullCommits(path string) ([]PullCommit, error) { return pullCommits.load(path) }

// AppendPullCommits stores the pull commits that the file at path does not
// hold yet, and returns how many it stored, by Append's rules. A commit is
// already held when a line has the same repository (ignoring case), pull
// request number and commit SHA, whatever else it says. The new lines are in
// pull request order (repository, number), oldest commit first (author date,
// SHA).
func AppendPullCommits(path string, records []PullCommit) (int, error) {
	return pullCommits.append(path, records)
}

// pullCommitKey identifies a commit of a pull request.
type pullCommitKey struct {
	repository string
	number     int64
	sha        string
}

// key is c's repository (lower-case), pull request and commit.
func (c PullCommit) key() pullCommitKey {
	return pullCommitKey{strings.ToLower(c.Repository), c.Number, c.SHA}
}

// comparePullCommits orders new lines by repository, number, author date,
// SHA.
func comparePullCommits(a, b PullCommit) int {
	return cmp.Or(cmp.Compare(a.Repository, b.Repository), cmp.Compare(a.Number, b.Number),
		a.AuthoredAt.Compare(b.AuthoredAt), cmp.Compare(a.SHA, b.SHA))
}

// fields are the columns of c's line.
func (c PullCommit) fields() []string {
	return []string{c.Repository, strconv.FormatInt(c.Number, 10), c.SHA, c.Author, formatTime(c.AuthoredAt)}
}

// toPullCommit reads the five fields of a line.
func toPullCommit(f []string) (PullCommit, error) {
	number, err := parseNumber("number", f[1])
	if err != nil {
		return PullCommit{}, err
	}
	authored, err := parseTime("authored_at", f[4])
	if err != nil {
		return PullCommit{}, err
	}
	return PullCommit{Repository: f[0], Number: number, SHA: f[2], Author: f[3], AuthoredAt: authored}, nil
}

// validate says why c cannot be stored, or nil.
func (c PullCommit) validate() error {
	return firstFailure(
		check{isRepository(c.Repository), fmt.Sprintf("repository %q is not owner/name", c.Repository)},
		check{!strings.ContainsAny(c.Repository, "\r\n"), "repository has a line break"},
		check{c.Number > 0, "number is not positive"},
		check{isSHA(c.SHA), fmt.Sprintf("sha %q is not 40 or 64 lower-case hex digits", c.SHA)},
		check{c.Author == "" || IsLogin(c.Author), fmt.Sprintf("author %q is not a GitHub login", c.Author)},
		check{isWholeSecond(c.AuthoredAt), "authored_at is empty or has a fraction of a second"},
	)
}
