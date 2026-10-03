package collect

import (
	"testing"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// TestTheNewestStatusDecidesAfterAFailure: a deployment whose newest status
// is in_progress, queued or pending after a failure or an error is being
// retried, so it is not final yet (forsgren#12, step 8): stored as a failure
// then, it would stay one even when the retry succeeds. The statuses are
// judged by their time (by their ID within one second), in whatever order
// GitHub lists them: a failure
// after an in_progress is final, a success after a failure is a success,
// and an inactive (GitHub's mark on a deployment a newer one replaced) says
// nothing, so the newest other status decides.
func TestTheNewestStatusDecidesAfterAFailure(t *testing.T) {
	for name, c := range map[string]struct {
		statuses string
		stdout   string
		state    history.State // empty: nothing stored
	}{
		"in_progress after a failure": {list(status(3, "failure", "2026-09-20T10:05:00Z"),
			status(4, "in_progress", "2026-09-20T10:10:00Z")), "acme/app: 0 new, 1 skipped (not final), 0 commits\n", ""},
		"queued after an error": {list(status(5, "queued", "2026-09-20T10:10:00Z"),
			status(4, "error", "2026-09-20T10:05:00Z"), status(3, "in_progress", "2026-09-20T10:01:00Z")),
			"acme/app: 0 new, 1 skipped (not final), 0 commits\n", ""},
		"in_progress in the same second as the failure, the later ID": {list(
			status(3, "failure", "2026-09-20T10:05:00Z"), status(4, "in_progress", "2026-09-20T10:05:00Z")),
			"acme/app: 0 new, 1 skipped (not final), 0 commits\n", ""},
		"a failure after in_progress, oldest first": {list(status(3, "in_progress", "2026-09-20T10:01:00Z"),
			status(4, "failure", "2026-09-20T10:05:00Z")), "acme/app: 1 new, 0 skipped (not final), 0 commits\n",
			history.StateFailure},
		"a success after a retry": {list(status(5, "success", "2026-09-20T10:20:00Z"),
			status(4, "in_progress", "2026-09-20T10:10:00Z"), status(3, "failure", "2026-09-20T10:05:00Z")),
			"acme/app: 1 new, 0 skipped (not final), 0 commits\n", history.StateSuccess},
		"inactive after a failure": {list(status(5, "inactive", "2026-09-21T09:00:00Z"),
			status(4, "failure", "2026-09-20T10:05:00Z")), "acme/app: 1 new, 0 skipped (not final), 0 commits\n",
			history.StateFailure},
	} {
		t.Run(name, func(t *testing.T) {
			g := newGitHub(t)
			g.bodies[deploymentsPath] = list(deployment(1001, shaA, "deploy", "2026-09-20T10:00:00Z"))
			g.bodies[statusesPath("1001")] = c.statuses
			path := historyPath(t)
			wantStdout(t, g.collect(t, shop(production), path, github.DefaultMaxPages), c.stdout)
			var want []history.Record
			if c.state != "" {
				want = append(want, record(history.KindEnvironment, "production", 1001, shaA, at(20, 10, 0), c.state,
					"deploy"))
			}
			wantRecords(t, path, want...)
		})
	}
}
