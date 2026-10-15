package collect

import "testing"

// TestTheCatchUpRereadsFailuresOfTheDoraWindow (forsgren#155, #178): of the
// stored failures preCatchUp leaves, 43 was opened two months before the run,
// so it can still count only with a window of 90 days: the default window
// asks for 42 and 44 alone, dora_days 90 for 43 as well, and 180 as well.
func TestTheCatchUpRereadsFailuresOfTheDoraWindow(t *testing.T) {
	for days, want := range map[int]int{0: 2, 30: 2, 90: 3, 180: 3} {
		g := issuesOnly(t)
		path := preCatchUp(t, g)
		g.bodies[singleIssuePath(42)] = listed{number: 42, state: "open", created: "2026-09-20T08:00:00Z"}.json()
		g.bodies[singleIssuePath(43)] = labelledFailure(
			listed{43, "closed", "2026-08-01T08:00:00Z", "2026-08-02T08:00:00Z", ""})
		g.bodies[singleIssuePath(44)] = closed44("")
		cfg := shop(production)
		cfg.DoraDays = days
		if r := g.collect(t, cfg, path, 1); r.err != nil {
			t.Fatalf("dora_days %d: want the run to succeed, got %v (stderr %q)", days, r.err, r.stderr)
		}
		if asked := g.seen(issuesPath + "/"); len(asked) != want {
			t.Errorf("dora_days %d: want %d single-issue requests, got %v", days, want, asked)
		}
	}
}
