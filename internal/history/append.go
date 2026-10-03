package history

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
)

// store is what an append found at the path.
type store[R any] struct {
	exists        bool
	records       []R
	endsInNewline bool
}

// Append stores the deployments that the history at path does not hold yet,
// and returns how many it stored.
//
//   - A missing path is created, directory included, with the version and
//     column lines, also when there is nothing to store.
//   - A record is already held when a line has the same repository (ignoring
//     case, as GitHub does), kind and deployment ID, whatever else it says:
//     lines are never rewritten, so the first one stays. Duplicates inside
//     records count once.
//   - The new lines are in created-at order, then ID, and go after the last
//     line in one write that is synced before Append returns. A file whose
//     last line has no newline gets one first.
//   - A file with an unknown version, or with a line that is not in the
//     format, is refused before anything is written: its bytes and
//     modification time stay as they were. So is a record that cannot be
//     stored (ErrInvalidRecord).
func Append(path string, records []Record) (int, error) { return deployments.append(path, records) }

// Validate is Append's first check, alone: the ErrInvalidRecord Append
// would return for records, or nil. It neither reads nor writes path, which
// only names the file in the error, so a caller can learn that Append will
// take the records before it writes anything else.
func Validate(path string, records []Record) error { return deployments.validateAll(path, records) }

// append stores the records the file at path does not hold yet: Append's
// rules, by the format's key and order.
func (f format[R, K]) append(path string, records []R) (int, error) {
	if err := f.validateAll(path, records); err != nil {
		return 0, err
	}
	st, err := f.read(path)
	if err != nil {
		return 0, err
	}
	fresh := f.newRecords(st.records, records)
	if st.exists && len(fresh) == 0 {
		return 0, nil
	}
	return len(fresh), f.write(path, st, fresh)
}

// validateAll refuses the first record that cannot be stored, naming path
// and the record's place in records.
func (f format[R, K]) validateAll(path string, records []R) error {
	for i, r := range records {
		if err := f.validate(r); err != nil {
			return fmt.Errorf("%s: %w: record %d: %w", path, ErrInvalidRecord, i+1, err)
		}
	}
	return nil
}

// read looks at the file at path: a missing file is the empty store.
func (f format[R, K]) read(path string) (store[R], error) {
	data, err := os.ReadFile(filepath.Clean(path))
	if notExist(err) {
		return store[R]{}, nil
	}
	if err != nil {
		return store[R]{}, fmt.Errorf("%s: %w", path, err)
	}
	records, err := f.parse(path, data)
	return store[R]{exists: true, records: records, endsInNewline: bytes.HasSuffix(data, []byte("\n"))}, err
}

// newRecords is the records that held does not have, once each, in the
// format's order.
func (f format[R, K]) newRecords(held, records []R) []R {
	seen := make(map[K]bool, len(held)+len(records))
	for _, r := range held {
		seen[f.key(r)] = true
	}
	var fresh []R
	for _, r := range slices.SortedStableFunc(slices.Values(records), f.compare) {
		if k := f.key(r); !seen[k] {
			seen[k] = true
			fresh = append(fresh, r)
		}
	}
	return fresh
}

// write puts the new lines at the end of the file, or creates it.
func (f format[R, K]) write(path string, st store[R], fresh []R) error {
	flags, err := prepare(path, st.exists)
	if err != nil {
		return err
	}
	file, err := os.OpenFile(filepath.Clean(path), flags, 0o600)
	if err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	_, werr := file.Write(f.payload(st, fresh))
	if err := errors.Join(werr, file.Sync(), file.Close()); err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	return nil
}

// prepare says how to open the file: for appending when it exists; else
// after its directory is made, with O_EXCL, so a file that appeared after the
// look is never truncated.
func prepare(path string, exists bool) (int, error) {
	if exists {
		return os.O_WRONLY | os.O_APPEND, nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return 0, fmt.Errorf("%s: %w", path, err)
	}
	return os.O_WRONLY | os.O_CREATE | os.O_EXCL, nil
}

// payload is what is written, in one piece: the version and column lines of a
// new file, or the newline a last line lacks, then the lines of fresh.
func (f format[R, K]) payload(st store[R], fresh []R) []byte {
	var out []byte
	switch {
	case !st.exists:
		out = []byte(f.versionLine + "\n" + f.columnLine + "\n")
	case !st.endsInNewline:
		out = []byte("\n")
	}
	for _, r := range fresh {
		out = append(out, f.encodeLine(r)...)
	}
	return out
}
