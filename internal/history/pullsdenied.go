package history

import (
	"cmp"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"time"
)

// Denial is one refused pull request read: when GitHub last refused it, and
// the name of the token it refused (FORSGREN_TOKEN, GITHUB_TOKEN), never the
// token's value; empty when the line is of the pulls denied format v1, which
// did not note it.
type Denial struct {
	At    time.Time
	Token string
}

// PullsDenied is data/pulls_denied.csv: per repository, its last refused read.
type PullsDenied map[string]Denial

// deniedRow is one line of data/pulls_denied.csv.
type deniedRow struct {
	Repository string // owner/name
	Denial
}

// pullsDeniedFile is the format of data/pulls_denied.csv, the pulls denied
// format v2 (forsgren#321, step 1): the rows of the reach format (forsgren#337,
// decision #332: a repository and when GitHub last refused the read of its
// pull requests, a 403, the token without pull-requests: read) and a token
// column, the name of the token that was refused. The v1, without the column,
// is still read, every token name empty, and written again as v2 by the next
// save. It holds names and times only.
var pullsDeniedFile = format[deniedRow, string]{
	versionLine: "# forsgren pulls denied v2",
	columnLine:  "repository,denied_at,token",
	decode:      toDeniedRow,
	encode:      deniedRow.fields,
	validate:    deniedRow.validate,
	key:         func(r deniedRow) string { return r.Repository },
	compare:     func(a, b deniedRow) int { return cmp.Compare(a.Repository, b.Repository) },
	legacy:      []legacyFormat{pullsDeniedV1},
}

// pullsDeniedV1 is the pulls denied format v1, before the token column: no
// token name is known.
var pullsDeniedV1 = legacyFormat{
	versionLine: "# forsgren pulls denied v1",
	columnLine:  "repository,denied_at",
	lift:        func(fields []string) []string { return append(fields, "") },
}

// tokenName is the shape of an environment variable name that holds a token:
// upper case, digits and underscores. A token's value (ghp_..., github_pat_...)
// has lower case and never fits.
var tokenName = regexp.MustCompile(`^[A-Z][A-Z0-9_]{0,63}$`)

// toDeniedRow reads the three fields of a line.
func toDeniedRow(f []string) (deniedRow, error) {
	at, err := parseTime("denied_at", f[1])
	return deniedRow{Repository: f[0], Denial: Denial{At: at, Token: f[2]}}, err
}

// fields are the columns of r's line.
func (r deniedRow) fields() []string {
	return []string{r.Repository, r.At.UTC().Format(timeLayout), r.Token}
}

// validate says why r cannot be stored, or nil. It never quotes the token
// column: what is wrong with it may be a token's value.
func (r deniedRow) validate() error {
	return firstFailure(
		check{isRepository(r.Repository), fmt.Sprintf("repository %q is not owner/name", r.Repository)},
		check{isWholeSecond(r.At), "denied_at is empty or has a fraction of a second"},
		check{r.Token == "" || tokenName.MatchString(r.Token), "token is not the name of a token"},
	)
}

// Times is the time of each denial, as the mark files keep it.
func (d PullsDenied) Times() Reach {
	times := make(Reach, len(d))
	for repository, denial := range d {
		times[repository] = denial.At
	}
	return times
}

// Tokens is the token name of each denial.
func (d PullsDenied) Tokens() map[string]string {
	tokens := make(map[string]string, len(d))
	for repository, denial := range d {
		tokens[repository] = denial.Token
	}
	return tokens
}

// DeniedOf is the denials of times, each with its token name in tokens, empty
// for a repository tokens does not name.
func DeniedOf(times Reach, tokens map[string]string) PullsDenied {
	denied := make(PullsDenied, len(times))
	for repository, at := range times {
		denied[repository] = Denial{At: at, Token: tokens[repository]}
	}
	return denied
}

// LoadPullsDenied reads data/pulls_denied.csv at path. A missing file is
// empty, like LoadReach; a first line stating another version is
// ErrUnknownVersion; a line that is not in the format is a *MalformedError.
func LoadPullsDenied(path string) (PullsDenied, error) {
	rows, err := pullsDeniedFile.load(path)
	if notExist(err) {
		return PullsDenied{}, nil
	}
	if err != nil {
		return nil, err
	}
	denied := make(PullsDenied, len(rows))
	for _, row := range rows {
		denied[row.Repository] = row.Denial
	}
	return denied, nil
}

// SavePullsDenied writes d to path whole, in the pulls denied format v2,
// sorted by repository, like SaveReach. A denial the format cannot store is
// refused before anything is written.
func SavePullsDenied(path string, d PullsDenied) error {
	rows := make([]deniedRow, 0, len(d))
	for repository, denial := range d {
		row := deniedRow{repository, denial}
		if err := row.validate(); err != nil {
			return fmt.Errorf("%s: %w", path, err)
		}
		rows = append(rows, row)
	}
	slices.SortFunc(rows, pullsDeniedFile.compare)
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	return replaceWhole(path, pullsDeniedFile.payload(store[deniedRow]{}, rows))
}
