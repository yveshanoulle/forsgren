package metrics

// The paths of a service (forsgren#496, step 4, decision #497 A): a
// deployment of a service with paths counts only the commits that touch one
// of them.
//
//   - a path ending in / is a folder and matches every file below it; any
//     other path is a file and matches that file alone, both compared exactly;
//   - a file the commit changes counts by its new name and, for a rename, by
//     its previous name too (collect stores both); the marker line of a commit
//     that changes no file has an empty path and matches nothing;
//   - a commit with no stored file line has not been read yet: it touches
//     nothing, it is left out of the service's figures, and the row says the
//     files are still being read;
//   - the commits left out still count in the total and label rows, which
//     have no scope.

import (
	"slices"
	"strings"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// pathScope says which commits belong to a service: those that change one of
// its paths. The nil scope is every commit's.
type pathScope struct {
	paths []string
	files map[string][]string // by commitKey; an empty path is the marker of a read commit
}

// scopeOf is the scope of paths over the commit files of data; nil for no
// paths.
func scopeOf(paths []string, files []history.CommitFile) *pathScope {
	if len(paths) == 0 {
		return nil
	}
	s := &pathScope{paths: paths, files: map[string][]string{}}
	for _, f := range files {
		key := commitKey(f.Repository, f.SHA)
		s.files[key] = append(s.files[key], f.Path)
	}
	return s
}

// touches says whether c belongs to the scope; the nil scope holds every
// commit.
func (s *pathScope) touches(c history.Commit) bool {
	if s == nil {
		return true
	}
	for _, file := range s.files[commitKey(c.Repository, c.SHA)] {
		if s.holds(file) {
			return true
		}
	}
	return false
}

// unread says whether no file of c is stored yet.
func (s *pathScope) unread(c history.Commit) bool {
	if s == nil {
		return false
	}
	_, read := s.files[commitKey(c.Repository, c.SHA)]
	return !read
}

// holds says whether file is one of the paths, or below one.
func (s *pathScope) holds(file string) bool {
	return file != "" && slices.ContainsFunc(s.paths, func(p string) bool { return matches(p, file) })
}

// matches says whether file is below the folder p (ending in /), or is the
// file p.
func matches(p, file string) bool {
	if strings.HasSuffix(p, "/") {
		return strings.HasPrefix(file, p)
	}
	return file == p
}
