// Package install holds the README an installation (a data repository) gets
// from forsgren (forsgren#110). The file is README.md here, embedded, so it
// changes in the same commits as the features and is frozen by each release
// tag; the daily run writes it into the installation at the version it runs.
package install

import (
	_ "embed" // readme is embedded.
	"errors"
	"fmt"
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

// Created is what Write reports, and the command prints before the path, when
// it put the README where none was.
const Created = "created"

// ErrWrite is what every error Write returns wraps, after the path.
var ErrWrite = errors.New("cannot write the README")

// Write puts the README for version at path and says what it did: Created
// when no file was there. A file that is there, and a directory of path that
// is missing, are errors. The file is written whole or the error says why not.
func Write(path, version string) (string, error) {
	f, err := os.OpenFile(filepath.Clean(path), os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err == nil {
		_, werr := f.WriteString(Text(version))
		err = errors.Join(werr, f.Close())
	}
	if err != nil {
		return "", fmt.Errorf("%s: %w: %w", path, ErrWrite, err)
	}
	return Created, nil
}
