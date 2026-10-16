// Package install holds the README an installation (a data repository) gets
// from forsgren (forsgren#110). The file is README.md here, embedded, so it
// changes in the same commits as the features and is frozen by each release
// tag; the daily run writes it into the installation at the version it runs.
package install

import (
	_ "embed" // readme is embedded.
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

// versionToken stands in README.md for the forsgren version the text is
// written for.
const versionToken = "{{version}}"

//go:embed README.md
var readme string

// Text is the installation README for forsgren version: README.md with
// versionToken replaced by version, so the text names the version it was
// written by and cannot drift from it.
func Text(version string) string {
	return strings.ReplaceAll(readme, versionToken, version)
}

// What Write reports, and the command prints before the path: Created when
// no file was there, Replaced when a different one was, Unchanged when the
// text was already there.
const (
	Created   = "created"
	Replaced  = "replaced"
	Unchanged = "unchanged"
)

// ErrWrite is what every error Write returns wraps, after the path.
var ErrWrite = errors.New("cannot write the README")

// Write puts the README for version at path and says what it did. A file
// that holds the text already is not touched, its modification time included;
// any other file is replaced, as forsgren's file (a hand edit is overwritten).
// The directory of path must exist. The file is whole from its first moment at
// path, or the error says why not.
func Write(path, version string) (string, error) {
	path = filepath.Clean(path)
	want := Text(version)
	outcome, err := judge(path, want)
	if err == nil && outcome != Unchanged {
		err = replace(path, want)
	}
	if err != nil {
		return "", fmt.Errorf("%s: %w: %w", path, ErrWrite, err)
	}
	return outcome, nil
}

// judge says what writing want to path would be: Created for no file,
// Unchanged for a file that holds want, Replaced for any other.
func judge(path, want string) (string, error) {
	have, err := os.ReadFile(filepath.Clean(path))
	switch {
	case errors.Is(err, fs.ErrNotExist):
		return Created, nil
	case err != nil:
		return "", err
	case string(have) == want:
		return Unchanged, nil
	}
	return Replaced, nil
}

// replace puts text at path through a temporary file in the same directory
// and a rename, so a reader sees the old file or the new one, never half.
func replace(path, text string) error {
	f, err := os.CreateTemp(filepath.Dir(path), ".README-*.tmp")
	if err != nil {
		return err
	}
	defer func() { _ = os.Remove(f.Name()) }()
	_, err = f.WriteString(text)
	err = errors.Join(err, f.Close())
	if err == nil {
		err = os.Rename(f.Name(), path)
	}
	return err
}
