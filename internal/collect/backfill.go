package collect

import "github.com/yveshanoulle/forsgren/internal/history"

// A backfilled chunk holds older deployments than the history does
// (forsgren#66). After every run, each stored success of a stream but its
// oldest was compared with the success before it, so only that oldest one
// can be waiting for a previous that was not read yet. When a run brings an
// older success of the stream, the waiting one is compared with it, and the
// new oldest waits in its turn.

// waiting is the oldest stored success of each stream that fresh holds a
// success of: the stored successes a fresh one may give a previous to.
func (h held) waiting(fresh []history.Record) []history.Record {
	var out []history.Record
	seen := map[history.Stream]bool{}
	for _, r := range fresh {
		s := r.Stream()
		if r.State != history.StateSuccess || seen[s] {
			continue
		}
		seen[s] = true
		if oldest, ok := oldestOf(h.successes[s]); ok {
			out = append(out, oldest)
		}
	}
	return out
}

// oldestOf is the oldest of records, by created_at, then ID.
func oldestOf(records []history.Record) (history.Record, bool) {
	var oldest history.Record
	for i, r := range records {
		if i == 0 || history.Chronological(r, oldest) < 0 {
			oldest = r
		}
	}
	return oldest, len(records) > 0
}
