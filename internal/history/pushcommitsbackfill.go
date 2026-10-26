package history

import (
	"slices"
	"strings"
)

// PushTip is the identity of a push by its tip: its repository, lower-case,
// and its after SHA. Several pushes can share one, and their lines are the
// same.
type PushTip struct{ repository, after string }

// Tip is the tip of the push c belongs to.
func (c PushCommit) Tip() PushTip { return PushTip{strings.ToLower(c.Repository), c.After} }

// BackfillPushCommits replaces the lines of the stored merge pushes in the
// push commits file at path by known, the lines of the same pushes as a
// compare gives them now (forsgren#470): a push is replaced when known has
// lines of it and the file has a line of it with unknown parents
// (ParentsUnknown, a line stored before the format v2). All the push's old
// lines go and the known ones, oldest first, take the place of its first old
// line; every other line and the order of the pushes stay as they are. It
// returns how many pushes it replaced. A missing file is nothing to fill.
// Nothing is written when no push was replaced, unless the file is of an
// older version, which is then written once in the current one; a write is
// the whole file through replaceWhole, so an interrupted run leaves the old
// file. A known line that cannot be stored is refused before anything is
// written (ErrInvalidRecord).
func BackfillPushCommits(path string, known []PushCommit) (int, error) {
	return backfillFile(pushCommits, path, known, replacedUnknown)
}

// replacedUnknown is held with the lines of each push that has a line of
// unknown parents replaced by the known lines of that push, and how many
// pushes that replaced; held is not changed.
func replacedUnknown(held, known []PushCommit) ([]PushCommit, int) {
	byPush, unknown := linesByPush(known), TipsWithUnknownParents(held)
	var out []PushCommit
	done := map[PushTip]bool{}
	for _, c := range held {
		lines, given := byPush[c.Tip()]
		switch {
		case !given || !unknown[c.Tip()]:
			out = append(out, c)
		case !done[c.Tip()]:
			done[c.Tip()] = true
			out = append(out, lines...)
		}
	}
	return out, len(done)
}

// linesByPush is lines by their push, each push's lines oldest first.
func linesByPush(lines []PushCommit) map[PushTip][]PushCommit {
	byPush := map[PushTip][]PushCommit{}
	for _, l := range slices.SortedStableFunc(slices.Values(lines), comparePushCommits) {
		byPush[l.Tip()] = append(byPush[l.Tip()], l)
	}
	return byPush
}

// TipsWithUnknownParents is the tips of the pushes that have a line of
// unknown parents among lines.
func TipsWithUnknownParents(lines []PushCommit) map[PushTip]bool {
	unknown := map[PushTip]bool{}
	for _, c := range lines {
		unknown[c.Tip()] = unknown[c.Tip()] || c.Parents == ParentsUnknown
	}
	return unknown
}
