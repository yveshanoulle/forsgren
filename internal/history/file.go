package history

import (
	"bytes"
	"encoding/csv"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// format is one append-only CSV file of the history, with R its record and
// K the key that tells two records apart: its version and column lines, and
// how a record is read from its fields, written as fields, judged, keyed and
// ordered. The deployments, the commits and the failure issues are the
// three formats; everything else about reading and appending a file is
// theirs in common.
type format[R any, K comparable] struct {
	versionLine string // "# forsgren <name> v<number>"
	columnLine  string
	decode      func(fields []string) (R, error)
	encode      func(R) []string
	validate    func(R) error
	key         func(R) K
	compare     func(a, b R) int
	// revises, when set, says whether a record says something else than
	// held, the newest line of its key, so it is appended as a new line of
	// that key; nil means a key, once written, is never written again.
	revises func(r, held R) bool
	// legacy are the older versions of the file this format still reads
	// (forsgren#273): each is lifted to the current columns, and an append
	// to such a file rewrites it once in the current version.
	legacy []legacyFormat
}

// legacyFormat is an older version of a file: its version and column lines,
// and how a line's fields become the fields of the current version.
type legacyFormat struct {
	versionLine string
	columnLine  string
	lift        func(fields []string) []string
}

// load reads the file at path, in file order.
func (f format[R, K]) load(path string) ([]R, error) {
	data, err := os.ReadFile(filepath.Clean(path))
	if err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	return f.parse(path, data)
}

// parse reads the content of a file.
func (f format[R, K]) parse(path string, data []byte) ([]R, error) {
	records, _, err := f.parseAs(path, data)
	return records, err
}

// parseAs is parse, and whether the file is of a legacy version.
func (f format[R, K]) parseAs(path string, data []byte) ([]R, bool, error) {
	lines := strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
	lg, err := f.checkHeader(path, lines)
	if err != nil {
		return nil, false, err
	}
	records := make([]R, 0, len(lines)-2)
	for i, line := range lines[2:] {
		rec, err := f.decodeLine(line, lg)
		if err != nil {
			return nil, false, &MalformedError{Path: path, Line: i + 3, Reason: err.Error()}
		}
		records = append(records, rec)
	}
	return records, lg != nil, nil
}

// checkHeader judges the version line, then the column line, and returns the
// legacy version the file is of, nil for the current one.
func (f format[R, K]) checkHeader(path string, lines []string) (*legacyFormat, error) {
	versionLine, columnLine := f.versionLine, f.columnLine
	lg := f.legacyOf(lines[0])
	if lg != nil {
		versionLine, columnLine = lg.versionLine, lg.columnLine
	}
	switch {
	case lines[0] == versionLine:
	case f.isVersionLine(lines[0]):
		return nil, fmt.Errorf("%s: %w: %q, this forsgren reads %q", path, ErrUnknownVersion, lines[0], f.versionLine)
	default:
		return nil, &MalformedError{Path: path, Line: 1, Reason: fmt.Sprintf("want the version line %q", f.versionLine)}
	}
	if len(lines) < 2 || lines[1] != columnLine {
		return nil, &MalformedError{Path: path, Line: 2, Reason: fmt.Sprintf("want the column line %q", columnLine)}
	}
	return lg, nil
}

// legacyOf is the legacy version whose version line is line, nil for none.
func (f format[R, K]) legacyOf(line string) *legacyFormat {
	for i := range f.legacy {
		if line == f.legacy[i].versionLine {
			return &f.legacy[i]
		}
	}
	return nil
}

// isVersionLine says whether s states a version of this format, any number,
// so another version is told from a stranger.
func (f format[R, K]) isVersionLine(s string) bool {
	number, ok := strings.CutPrefix(s, strings.TrimRight(f.versionLine, "0123456789"))
	return ok && number != "" && strings.Trim(number, "0123456789") == ""
}

// decodeLine reads one line of records, without its newline, and judges the
// record.
func (f format[R, K]) decodeLine(line string, lg *legacyFormat) (R, error) {
	var zero R
	if line == "" {
		return zero, errors.New("the line is empty")
	}
	columnLine := f.columnLine
	if lg != nil {
		columnLine = lg.columnLine
	}
	columns := strings.Count(columnLine, ",") + 1
	r := csv.NewReader(strings.NewReader(line))
	r.FieldsPerRecord = columns
	fields, err := r.Read()
	if err != nil {
		return zero, fmt.Errorf("want %d comma-separated fields: %w", columns, err)
	}
	if lg != nil {
		fields = lg.lift(fields)
	}
	rec, err := f.decode(fields)
	if err != nil {
		return zero, err
	}
	return rec, f.validate(rec)
}

// encodeLine is the line of r, with its newline.
func (f format[R, K]) encodeLine(r R) []byte {
	var buf bytes.Buffer
	w := csv.NewWriter(&buf)
	// A csv.Writer on a bytes.Buffer cannot fail.
	_ = w.Write(f.encode(r))
	w.Flush()
	return buf.Bytes()
}

// notExist says whether err is a missing file.
func notExist(err error) bool { return errors.Is(err, fs.ErrNotExist) }

// parseNumber reads the number column named column, a deployment_id or an
// issue: a whole number, written as Go writes it.
func parseNumber(column, s string) (int64, error) {
	n, err := strconv.ParseInt(s, 10, 64)
	if err != nil || strconv.FormatInt(n, 10) != s {
		return 0, fmt.Errorf("%s %q is not a whole number", column, s)
	}
	return n, nil
}

// parseTime reads the time column named column.
func parseTime(column, s string) (time.Time, error) {
	at, err := time.Parse(timeLayout, s)
	if err != nil {
		return time.Time{}, fmt.Errorf("%s %q is not RFC 3339 UTC like 2026-09-01T10:00:00Z", column, s)
	}
	return at, nil
}

// parseOptionalTime reads a time column that may be empty, the zero time.
func parseOptionalTime(column, s string) (time.Time, error) {
	if s == "" {
		return time.Time{}, nil
	}
	return parseTime(column, s)
}
