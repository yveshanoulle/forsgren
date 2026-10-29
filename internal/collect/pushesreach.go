package collect

// The one-time reach check of the pushes (forsgren#583, step 1). A push read
// cut at the page cap notes the repository in data/pushes_cut.csv, but a read
// cut before that file existed left no line, and the daily reads after it are
// no longer cut. So each repository with stored pushes, no cut line and no
// line in data/pushes_checked.csv is checked once: one request of its
// activity list oldest first (Client.OldestActivity, inside Client.Reserve).
// A push there older than the oldest stored one, while that stored one is
// later than history_days back (a day of slack), means the stored pushes do
// not reach back: the cut line is the oldest stored push time. Either way the
// repository is noted as checked. A first read that ended by itself is
// checked without a request, and a cut read notes its cut. A refused or
// failing request, or the budget, writes nothing and leaves the check to the
// next run; it never fails the repository.

import (
	"context"
	"path/filepath"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// pushesCheckedFile is the path of the pushes checked file next to o's history.
func (o Options) pushesCheckedFile() string {
	return filepath.Join(filepath.Dir(o.History), PushesCheckedFile)
}

// oldestPushes is the oldest stored push time per repository, in lower case.
func oldestPushes(stored []history.Push) map[string]time.Time {
	oldest := map[string]time.Time{}
	for _, p := range stored {
		key := strings.ToLower(p.Repository)
		if at, seen := oldest[key]; !seen || p.PushedAt.Before(at) {
			oldest[key] = p.PushedAt
		}
	}
	return oldest
}

// readEnd is how a push read that ended without an error ended: cut at the
// page cap, the repository's first read, and the oldest push the list gave.
type readEnd struct {
	truncated, first bool
	oldest           time.Time
}

// checkReach notes how far repo's stored pushes reach after a read that ended
// as end says: a cut read its cut, a first read that ended its check, and any
// other read the one-time check, when it is due.
func (o Options) checkReach(ctx context.Context, h held, repo string, end readEnd) {
	switch {
	case end.truncated:
		o.notePushesCut(h, repo, end.oldest)
	case end.first:
		h.pushesChecked[strings.ToLower(repo)] = wholeSecond(o.Now)
	default:
		o.probeReach(ctx, h, repo)
	}
}

// probeReach is the one-time check of repo, when it has stored pushes, no
// cut line and no check yet.
func (o Options) probeReach(ctx context.Context, h held, repo string) {
	key := strings.ToLower(repo)
	stored, due := h.reachDue(key)
	if !due {
		return
	}
	oldest, err := o.oldestActivity(ctx, h, repo)
	if err != nil {
		o.warn("collect: %s: the check of how far the stored pushes reach was not made: %v; "+
			"the next run makes it\n", repo, err)
		return
	}
	if o.reachesFurther(oldest, stored) {
		h.pushesCut[key] = stored
	}
	h.pushesChecked[key] = wholeSecond(o.Now)
}

// reachDue is the oldest stored push of the repository key, and whether its
// check is due: it has stored pushes, no cut line and no check yet.
func (h held) reachDue(key string) (time.Time, bool) {
	stored, has := h.oldestPush[key]
	_, cut := h.pushesCut[key]
	_, checked := h.pushesChecked[key]
	return stored, has && !cut && !checked
}

// reachesFurther says GitHub's oldest push is older than the oldest stored
// one, and that one is more than a day after history_days back.
func (o Options) reachesFurther(oldest, stored time.Time) bool {
	return !oldest.IsZero() && oldest.Before(stored) && stored.After(o.earliest.Add(failuresReadOverlap))
}

// oldestActivity is the oldest push GitHub lists for repo's default branch,
// one request inside the budget.
func (o Options) oldestActivity(ctx context.Context, h held, repo string) (time.Time, error) {
	branch, err := o.defaultBranch(ctx, h, repo)
	if err != nil {
		return time.Time{}, err
	}
	if err := o.Client.Reserve(repo, 1); err != nil {
		return time.Time{}, err
	}
	return o.Client.OldestActivity(ctx, repo, branch)
}
