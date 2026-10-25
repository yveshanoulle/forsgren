package collect

import "github.com/yveshanoulle/forsgren/internal/history"

// A denied mark is a markFile with a second column (forsgren#321, and
// forsgren#414 for the pushes): the time of each refusal is the mark, held in
// h.denied or h.pushesDenied, and the name of the token that was refused is
// held beside it in h.deniedBy or h.pushesDeniedBy.

// deniedFile is the markFile of the denied file at path, whose times are kept
// in mark and whose token names are kept in by; load and save are the
// history's for that file.
func deniedFile(mark *history.Reach, by *map[string]string, path string,
	load func(string) (history.Denied, error), save func(string, history.Denied) error) markFile {
	return markFile{
		held: mark,
		path: path,
		load: func(path string) (history.Reach, error) {
			denied, err := load(path)
			*by = denied.Tokens()
			return denied.Times(), err
		},
		save: func(path string, times history.Reach) error {
			return save(path, history.DeniedOf(times, *by))
		},
	}
}
