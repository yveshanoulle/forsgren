package config

import "errors"

// RED STUBS for forsgren#12 step 2: they compile and do nothing, so the
// tests fail at runtime. The green patch replaces this file.

// Starter is the starter config text.
var Starter string

// ErrWrite and ErrNotAFile are the refusals of Init.
var (
	ErrWrite    = errors.New("cannot write the starter config")
	ErrNotAFile = errors.New("exists but is not a regular file")
)

// Init is a stub.
func Init(path string) (bool, error) {
	return install(path, func() {})
}

func install(_ string, _ func()) (bool, error) {
	return false, nil
}
