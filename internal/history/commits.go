package history

import (
	"cmp"
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// Commit is one commit of one successful deployment (forsgren#16, step 1):
// a line of data/commits.csv. Its lead time runs from AuthoredAt to
// DeployedAt.
//
// Repository, Kind and DeploymentID are the deployment's key in
// data/deployments.csv. DeployedAt is that deployment's created_at, copied
// so lead time needs no join. The project and the task are not stored: the
// metrics find a repository's project in the config, so a renamed project
// keeps its commits, and the task only picks the previous deployment when
// the commits are collected; both stay in the deployment's own line.
type Commit struct {
	Repository   string // owner/name
	Kind         Kind
	DeploymentID int64
	SHA          string    // lower-case hex
	AuthoredAt   time.Time // the commit's author date, UTC, whole seconds
	DeployedAt   time.Time // the deployment's created_at, UTC, whole seconds
	// Author is the GitHub login of the commit's author (the account GitHub
	// links the commit to: forsgren#273, decision 274), empty when GitHub
	// links it to none or the commit was stored before this column. Never an
	// email address and never a name.
	Author string
}

// commits is the format of data/commits.csv, the commits format v2 (the
// author column, forsgren#273); v1, without it, is still read, every author
// empty, and rewritten as v2 by the first append.
var commits = format[Commit, commitKey]{
	versionLine: "# forsgren commits v2",
	columnLine:  "repository,kind,deployment_id,commit,authored_at,deployed_at,author",
	decode:      toCommit,
	encode:      Commit.fields,
	validate:    Commit.validate,
	key:         Commit.key,
	compare:     compareCommits,
	legacy:      []legacyFormat{commitsV1},
}

// commitsV1 is the commits format v1, before the author column: its six
// columns are the first six of v2, the author empty.
var commitsV1 = legacyFormat{
	versionLine: "# forsgren commits v1",
	columnLine:  "repository,kind,deployment_id,commit,authored_at,deployed_at",
	lift:        func(fields []string) []string { return append(fields, "") },
}

// LoadCommits reads the commits at path, in file order, with Load's errors.
func LoadCommits(path string) ([]Commit, error) { return commits.load(path) }

// AppendCommits stores the commits that the file at path does not hold yet,
// and returns how many it stored, by Append's rules. A commit is already
// held when a line has the same deployment (repository, ignoring case, kind
// and deployment ID) and the same SHA; one commit can be in several
// deployments, once each. The new lines are in deployment order (deployed
// at, repository, kind, ID), then by author date, then SHA.
func AppendCommits(path string, records []Commit) (int, error) { return commits.append(path, records) }

// commitKey identifies a commit of a deployment.
type commitKey struct {
	deployment key
	sha        string
}

func (c Commit) key() commitKey {
	return commitKey{key{strings.ToLower(c.Repository), c.Kind, c.DeploymentID}, c.SHA}
}

// compareCommits orders new lines by deployment, then author date, then SHA.
func compareCommits(a, b Commit) int {
	return cmp.Or(a.DeployedAt.Compare(b.DeployedAt), cmp.Compare(a.Repository, b.Repository),
		cmp.Compare(a.Kind, b.Kind), cmp.Compare(a.DeploymentID, b.DeploymentID),
		a.AuthoredAt.Compare(b.AuthoredAt), cmp.Compare(a.SHA, b.SHA))
}

// fields are the columns of c's line.
func (c Commit) fields() []string {
	return []string{
		c.Repository, string(c.Kind), strconv.FormatInt(c.DeploymentID, 10), c.SHA,
		c.AuthoredAt.UTC().Format(timeLayout), c.DeployedAt.UTC().Format(timeLayout), c.Author,
	}
}

// toCommit reads the seven fields of a line.
func toCommit(f []string) (Commit, error) {
	id, err := parseNumber("deployment_id", f[2])
	if err != nil {
		return Commit{}, err
	}
	authored, err := parseTime("authored_at", f[4])
	if err != nil {
		return Commit{}, err
	}
	deployed, err := parseTime("deployed_at", f[5])
	if err != nil {
		return Commit{}, err
	}
	return Commit{
		Repository: f[0], Kind: Kind(f[1]), DeploymentID: id, SHA: f[3],
		AuthoredAt: authored, DeployedAt: deployed, Author: f[6],
	}, nil
}

// validate says why c cannot be stored, or nil.
func (c Commit) validate() error {
	return firstFailure(
		check{isRepository(c.Repository), fmt.Sprintf("repository %q is not owner/name", c.Repository)},
		check{!strings.ContainsAny(c.Repository, "\r\n"), "the repository has a line break"},
		check{isKind(c.Kind), fmt.Sprintf("kind %q is not environment, workflow or release", c.Kind)},
		check{c.DeploymentID > 0, "deployment_id is not positive"},
		check{isSHA(c.SHA), fmt.Sprintf("commit %q is not 40 or 64 lower-case hex digits", c.SHA)},
		check{isWholeSecond(c.AuthoredAt), "authored_at is empty or has a fraction of a second"},
		check{isWholeSecond(c.DeployedAt), "deployed_at is empty or has a fraction of a second"},
		check{c.Author == "" || isLogin(c.Author), fmt.Sprintf("author %q is not a GitHub login", c.Author)},
	)
}

// loginShape is a GitHub login: letters, digits, hyphens and underscores (the
// underscore for Enterprise Managed Users), starting with a letter or digit,
// and for a bot account the suffix [bot]. An email address or a name has
// characters that are not allowed, so neither can be stored as an author.
var loginShape = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9_-]*(\[bot\])?$`)

// isLogin says whether s is the shape of a GitHub login.
func isLogin(s string) bool { return loginShape.MatchString(s) }
