package history

// data/pushes_fill.csv (forsgren#583, step 2), the pushes fill format v1:
// per repository whose push read stopped at the page cap, where its fill of
// the older pushes goes on: when the fill last moved, and GitHub's after
// cursor of the next page of the activity list to read. The cursor is
// GitHub's own, kept as it came (it holds its place across runs); only its
// shape is checked, the letters, digits and signs of base64.

import (
	"cmp"
	"fmt"
	"regexp"
	"time"
)

// FillCursor is where a repository's push fill goes on: when it last moved
// and the after cursor of the next page to read.
type FillCursor struct {
	At     time.Time
	Cursor string
}

// PushesFill is data/pushes_fill.csv: per repository, its fill cursor.
type PushesFill map[string]FillCursor

// fillRow is one line of data/pushes_fill.csv.
type fillRow struct {
	Repository string // owner/name
	FillCursor
}

// cursorShape is the shape of an after cursor: base64, at most 512 signs.
var cursorShape = regexp.MustCompile(`^[A-Za-z0-9+/=_-]{1,512}$`)

// pushesFillFile is the format of data/pushes_fill.csv.
var pushesFillFile = format[fillRow, string]{
	versionLine: "# forsgren pushes fill v1",
	columnLine:  "repository,filled_at,cursor",
	decode:      toFillRow,
	encode:      fillRow.fields,
	validate:    fillRow.validate,
	compare:     func(a, b fillRow) int { return cmp.Compare(a.Repository, b.Repository) },
}

// toFillRow reads the three fields of a line.
func toFillRow(f []string) (fillRow, error) {
	at, err := parseTime("filled_at", f[1])
	return fillRow{Repository: f[0], FillCursor: FillCursor{At: at, Cursor: f[2]}}, err
}

// fields are the columns of r's line.
func (r fillRow) fields() []string {
	return []string{r.Repository, r.At.UTC().Format(timeLayout), r.Cursor}
}

// validate says why r cannot be stored, or nil.
func (r fillRow) validate() error {
	return firstFailure(
		check{isRepository(r.Repository), fmt.Sprintf("repository %q is not owner/name", r.Repository)},
		check{isWholeSecond(r.At), "filled_at is empty or has a fraction of a second"},
		check{cursorShape.MatchString(r.Cursor), "cursor is not an after cursor"},
	)
}

// LoadPushesFill reads data/pushes_fill.csv at path. A missing file is
// empty, like LoadReach; a first line stating another version is
// ErrUnknownVersion; a line that is not in the format is a *MalformedError.
func LoadPushesFill(path string) (PushesFill, error) {
	rows, err := pushesFillFile.load(path)
	if notExist(err) {
		return PushesFill{}, nil
	}
	if err != nil {
		return nil, err
	}
	fill := make(PushesFill, len(rows))
	for _, row := range rows {
		fill[row.Repository] = row.FillCursor
	}
	return fill, nil
}

// SavePushesFill writes f to path whole, sorted by repository, like
// SaveReach. A line the format cannot store is refused before anything is
// written.
func SavePushesFill(path string, f PushesFill) error {
	rows := make([]fillRow, 0, len(f))
	for repository, cursor := range f {
		rows = append(rows, fillRow{repository, cursor})
	}
	return saveRows(path, rows, pushesFillFile)
}

// Times is the time of each cursor, as the mark files keep it.
func (f PushesFill) Times() Reach {
	times := make(Reach, len(f))
	for repository, c := range f {
		times[repository] = c.At
	}
	return times
}

// Cursors is the cursor of each repository.
func (f PushesFill) Cursors() map[string]string {
	cursors := make(map[string]string, len(f))
	for repository, c := range f {
		cursors[repository] = c.Cursor
	}
	return cursors
}

// PushesFillOf is the fill cursors of times, each with its cursor in cursors.
func PushesFillOf(times Reach, cursors map[string]string) PushesFill {
	fill := make(PushesFill, len(times))
	for repository, at := range times {
		fill[repository] = FillCursor{At: at, Cursor: cursors[repository]}
	}
	return fill
}
