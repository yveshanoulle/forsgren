package history

import "slices"

// Legacy says whether c was stored before the commits format v3: it has
// neither parents nor a committer date (forsgren#254). Its author may be
// known (v2) or not (v1).
func (c Commit) Legacy() bool { return len(c.Parents) == 0 && c.CommittedAt.IsZero() }

// filledFrom is c with the columns it lacks taken from known, the same
// commit as GitHub gives it now (forsgren#385): the author when c has none,
// the parents when c has none, the committer date when c has none. What c
// already says is kept, and nothing is invented: an empty column of known
// leaves it empty.
func (c Commit) filledFrom(known Commit) Commit {
	if c.Author == "" {
		c.Author = known.Author
	}
	if len(c.Parents) == 0 {
		c.Parents = known.Parents
	}
	if c.CommittedAt.IsZero() {
		c.CommittedAt = known.CommittedAt
	}
	return c
}

// BackfillCommits fills the legacy lines of the commits file at path from
// known, the commits as GitHub gives them now (forsgren#385), and returns
// how many lines it changed. A line is legacy when Commit.Legacy says so; it
// is matched to a known commit by the commit's key (deployment and SHA), and
// only its empty author, parents and committer date are filled. Every other
// line, the order of the lines and the file's other columns stay as they
// are. A missing file is nothing to fill. Nothing is written when no line
// changed, unless the file is of an older version, which is then written once
// in the current one; a write is the whole file through replaceWhole, like
// the upgrade, so an interrupted run leaves the old file. A known commit that
// cannot be stored is refused before anything is written (ErrInvalidRecord).
func BackfillCommits(path string, known []Commit) (int, error) {
	return backfillFile(commits, path, known, filledLegacy)
}

// backfillFile is the body of the fills of a file (BackfillCommits,
// BackfillPushCommits): known is refused before anything is written when a
// record cannot be stored, a missing file is nothing to fill, fill gives the
// records the file should hold and how many it changed, and a write is the
// whole file through replaceWhole, only when something changed or the file is
// of an older version.
func backfillFile[R any, K comparable](f format[R, K], path string, known []R,
	fill func(held, known []R) ([]R, int),
) (int, error) {
	if err := f.validateAll(path, known); err != nil {
		return 0, err
	}
	st, err := f.read(path)
	if err != nil || !st.exists {
		return 0, err
	}
	records, changed := fill(st.records, known)
	if changed == 0 && !st.legacy {
		return 0, nil
	}
	return changed, replaceWhole(path, f.payload(store[R]{}, records))
}

// filledLegacy is held with each legacy line filled from the known commit of
// its key, and how many lines that changed; held is not changed.
func filledLegacy(held, known []Commit) ([]Commit, int) {
	byKey := make(map[commitKey]Commit, len(known))
	for _, k := range known {
		byKey[k.key()] = k
	}
	out, changed := slices.Clone(held), 0
	for i, c := range out {
		k, ok := byKey[c.key()]
		if !ok || !c.Legacy() {
			continue
		}
		if filled := c.filledFrom(k); !slices.Equal(filled.fields(), c.fields()) {
			out[i], changed = filled, changed+1
		}
	}
	return out, changed
}
