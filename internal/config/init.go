package config

import (
	_ "embed" // Starter is embedded.
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
)

// Starter is the starter config Init writes: a commented guide and example,
// then `version: 1` and `projects: []`, so check-config accepts it as is
// (forsgren#12). It is the one text of the starter: starter.yml, embedded.
//
//go:embed starter.yml
var Starter string

// The refusals Init names; each error it returns wraps one of them, after
// the path.
var (
	ErrWrite    = errors.New("cannot create the config file")
	ErrNotAFile = errors.New("exists but is not a regular file")
)

// Init writes the starter config to path when no file is there, and reports
// whether it did. A file that is there, whatever it holds, is kept as it is:
// not read, not rewritten, its modification time untouched. The directory of
// path must exist; Init never creates it, so a mistyped directory is an error.
func Init(path string) (created bool, err error) {
	return install(path, func() {})
}

// install is Init with a hook that runs after the starter is written to a
// temporary file and before it is put at path: a test makes a file appear
// there, as another process could.
//
// The starter reaches path by os.Link from a temporary file in the same
// directory: linking is atomic and fails when path exists, so a file that
// appears after the look at path is never replaced (rename would replace it,
// O_EXCL would leave a partial file visible, truncating would destroy it).
// The file is whole from its first moment at path.
func install(path string, beforeLink func()) (bool, error) {
	if kept, err := existing(path); kept || err != nil {
		return false, err
	}
	tmp, err := writeTemp(path)
	defer func() { _ = os.Remove(tmp) }()
	if err != nil {
		return false, err
	}
	beforeLink()
	err = os.Link(tmp, path)
	if errors.Is(err, fs.ErrExist) {
		return false, taken(path)
	}
	if err != nil {
		return false, fmt.Errorf("%s: %w: %w", path, ErrWrite, err)
	}
	return true, nil
}

// existing says whether a regular file is at path (a link to one counts), and
// refuses whatever else is there, a directory for one.
func existing(path string) (bool, error) {
	info, err := os.Stat(path)
	if errors.Is(err, fs.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("%s: %w: %w", path, ErrWrite, err)
	}
	if !info.Mode().IsRegular() {
		return false, fmt.Errorf("%s: %w", path, ErrNotAFile)
	}
	return true, nil
}

// taken judges a path that os.Link found taken: a regular file is kept; any
// other entry, a directory or a link to nothing, is refused.
func taken(path string) error {
	kept, err := existing(path)
	if err == nil && !kept {
		err = fmt.Errorf("%s: %w: it is a link to nothing", path, ErrNotAFile)
	}
	return err
}

// writeTemp writes the starter to a new temporary file next to path and
// returns its name, also when the write failed after the file was created, so
// the caller removes it; the name is empty when no file was created.
func writeTemp(path string) (string, error) {
	f, err := os.CreateTemp(filepath.Dir(path), ".forsgren.config-*.tmp")
	name := ""
	if err == nil {
		_, werr := f.WriteString(Starter)
		err = errors.Join(werr, f.Sync(), f.Close())
		name = f.Name()
	}
	if err != nil {
		return name, fmt.Errorf("%s: %w: %w", path, ErrWrite, err)
	}
	return name, nil
}
