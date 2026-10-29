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

// Denied is data/pulls_denied.csv: per repository, its last refused read.
type Denied map[string]Denial

// deniedRow is one line of data/pulls_denied.csv.
type deniedRow struct {
	Repository string // owner/name
	Denial
}

// deniedFormat is the format of the denied file of the read named kind
// (pulls, pushes), the denied format v2 (forsgren#321, step 1, and
// forsgren#414 for the pushes): the rows of the reach format (forsgren#337,
// decision #332: a repository and when GitHub last refused the read of its
// pull requests, a 403, the token without pull-requests: read) and a token
// column, the name of the token that was refused. The v1, without the column,
// is still read, every token name empty, and written again as v2 by the next
// save. It holds names and times only.
func deniedFormat(kind string) format[deniedRow, string] {
	return format[deniedRow, string]{
		versionLine: "# forsgren " + kind + " denied v2",
		columnLine:  "repository,denied_at,token",
		decode:      toDeniedRow,
		encode:      deniedRow.fields,
		validate:    deniedRow.validate,
		compare:     func(a, b deniedRow) int { return cmp.Compare(a.Repository, b.Repository) },
		legacy:      []legacyFormat{deniedV1(kind)},
	}
}

// pullsDeniedFile and pushesDeniedFile are the formats of data/pulls_denied.csv
// and data/pushes_denied.csv.
var (
	pullsDeniedFile  = deniedFormat("pulls")
	pushesDeniedFile = deniedFormat("pushes")
)

// deniedV1 is the denied format v1 of the read named kind, before the token
// column: no token name is known.
func deniedV1(kind string) legacyFormat {
	return legacyFormat{
		versionLine: "# forsgren " + kind + " denied v1",
		columnLine:  "repository,denied_at",
		lift:        func(fields []string) []string { return append(fields, "") },
	}
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
func (d Denied) Times() Reach {
	times := make(Reach, len(d))
	for repository, denial := range d {
		times[repository] = denial.At
	}
	return times
}

// Tokens is the token name of each denial.
func (d Denied) Tokens() map[string]string {
	tokens := make(map[string]string, len(d))
	for repository, denial := range d {
		tokens[repository] = denial.Token
	}
	return tokens
}

// DeniedOf is the denials of times, each with its token name in tokens, empty
// for a repository tokens does not name.
func DeniedOf(times Reach, tokens map[string]string) Denied {
	denied := make(Denied, len(times))
	for repository, at := range times {
		denied[repository] = Denial{At: at, Token: tokens[repository]}
	}
	return denied
}

// LoadPullsDenied reads data/pulls_denied.csv at path. A missing file is
// empty, like LoadReach; a first line stating another version is
// ErrUnknownVersion; a line that is not in the format is a *MalformedError.
func LoadPullsDenied(path string) (Denied, error) { return loadDenied(path, pullsDeniedFile) }

// LoadPushesDenied reads data/pushes_denied.csv at path, like LoadPullsDenied.
func LoadPushesDenied(path string) (Denied, error) { return loadDenied(path, pushesDeniedFile) }

// loadDenied reads the denied file at path in the format f.
func loadDenied(path string, f format[deniedRow, string]) (Denied, error) {
	rows, err := f.load(path)
	if notExist(err) {
		return Denied{}, nil
	}
	if err != nil {
		return nil, err
	}
	denied := make(Denied, len(rows))
	for _, row := range rows {
		denied[row.Repository] = row.Denial
	}
	return denied, nil
}

// SavePullsDenied writes d to path whole, in the pulls denied format v2,
// sorted by repository, like SaveReach. A denial the format cannot store is
// refused before anything is written.
func SavePullsDenied(path string, d Denied) error { return saveDenied(path, d, pullsDeniedFile) }

// SavePushesDenied writes d to data/pushes_denied.csv at path, like
// SavePullsDenied.
func SavePushesDenied(path string, d Denied) error { return saveDenied(path, d, pushesDeniedFile) }

// saveDenied writes d to path in the format f.
func saveDenied(path string, d Denied, f format[deniedRow, string]) error {
	rows := make([]deniedRow, 0, len(d))
	for repository, denial := range d {
		rows = append(rows, deniedRow{repository, denial})
	}
	return saveRows(path, rows, f)
}

// saveRows writes rows to path whole in the format f, sorted by its compare,
// like SaveReach; a row the format cannot store is refused before anything
// is written.
func saveRows[R any](path string, rows []R, f format[R, string]) error {
	for _, row := range rows {
		if err := f.validate(row); err != nil {
			return fmt.Errorf("%s: %w", path, err)
		}
	}
	slices.SortFunc(rows, f.compare)
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	return replaceWhole(path, f.payload(store[R]{}, rows))
}
