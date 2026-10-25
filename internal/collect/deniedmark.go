package collect

import "github.com/yveshanoulle/forsgren/internal/history"

// The pulls denied mark is a markFile with a second column (forsgren#321):
// the time of each refusal is the mark, held in h.denied, and the name of the
// token that was refused is held beside it in h.deniedBy.

// loadDenied is the load of the pulls denied mark.
func (h *held) loadDenied(path string) (history.Reach, error) {
	denied, err := history.LoadPullsDenied(path)
	h.deniedBy = denied.Tokens()
	return denied.Times(), err
}

// saveDenied is the save of the pulls denied mark: each time with its token
// name from h.deniedBy.
func (h *held) saveDenied(path string, times history.Reach) error {
	return history.SavePullsDenied(path, history.DeniedOf(times, h.deniedBy))
}
