package history

import (
	"bytes"
	"cmp"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
)

// store is what Append found at the path.
type store struct {
	exists        bool
	records       []Record
	endsInNewline bool
}

// Append stores the records that the history at path does not hold yet, and
// returns how many it stored.
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
func Append(path string, records []Record) (int, error) {
	for i, r := range records {
		if err := r.validate(); err != nil {
			return 0, fmt.Errorf("%s: %w: record %d: %w", path, ErrInvalidRecord, i+1, err)
		}
	}
	st, err := read(path)
	if err != nil {
		return 0, err
	}
	fresh := newRecords(st.records, records)
	if st.exists && len(fresh) == 0 {
		return 0, nil
	}
	return len(fresh), write(path, st, fresh)
}

// read looks at the file at path: a missing file is the empty store.
func read(path string) (store, error) {
	data, err := os.ReadFile(filepath.Clean(path))
	if notExist(err) {
		return store{}, nil
	}
	if err != nil {
		return store{}, fmt.Errorf("%s: %w", path, err)
	}
	records, err := parse(path, data)
	return store{exists: true, records: records, endsInNewline: bytes.HasSuffix(data, []byte("\n"))}, err
}

// newRecords is the records that held does not have, once each, in created-at
// order, then ID (then repository and kind, so the order is total).
func newRecords(held, records []Record) []Record {
	seen := make(map[key]bool, len(held)+len(records))
	for _, r := range held {
		seen[r.key()] = true
	}
	sorted := slices.SortedStableFunc(slices.Values(records), func(a, b Record) int {
		return cmp.Or(a.CreatedAt.Compare(b.CreatedAt), cmp.Compare(a.ID, b.ID),
			cmp.Compare(a.Repository, b.Repository), cmp.Compare(a.Kind, b.Kind))
	})
	var fresh []Record
	for _, r := range sorted {
		if !seen[r.key()] {
			seen[r.key()] = true
			fresh = append(fresh, r)
		}
	}
	return fresh
}

// write puts the new lines at the end of the file, or creates it.
func write(path string, st store, fresh []Record) error {
	flags, err := prepare(path, st)
	if err != nil {
		return err
	}
	f, err := os.OpenFile(filepath.Clean(path), flags, 0o600)
	if err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	_, werr := f.Write(payload(st, fresh))
	if err := errors.Join(werr, f.Sync(), f.Close()); err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	return nil
}

// prepare says how to open the file: for appending when it exists; else
// after its directory is made, with O_EXCL, so a file that appeared after the
// look is never truncated.
func prepare(path string, st store) (int, error) {
	if st.exists {
		return os.O_WRONLY | os.O_APPEND, nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return 0, fmt.Errorf("%s: %w", path, err)
	}
	return os.O_WRONLY | os.O_CREATE | os.O_EXCL, nil
}

// payload is what is written, in one piece: the version and column lines of a
// new file, or the newline a last line lacks, then the lines of fresh.
func payload(st store, fresh []Record) []byte {
	var out []byte
	switch {
	case !st.exists:
		out = []byte(versionLine + "\n" + columnLine + "\n")
	case !st.endsInNewline:
		out = []byte("\n")
	}
	for _, r := range fresh {
		out = append(out, r.encode()...)
	}
	return out
}
