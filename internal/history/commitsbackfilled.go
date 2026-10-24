package history

// commitsBackfilledFile is the format of data/commits_backfilled.csv, the
// commits backfilled format v1 (forsgren#385): the rows of the reach format,
// with a version line and a column that say what the time is, when the
// one-time backfill of the author, parents and committer date of the
// repository's legacy commits was done. A repository in it is not backfilled
// again.
var commitsBackfilledFile = markFormat("# forsgren commits backfilled v1", "repository,backfilled_at")

// LoadCommitsBackfilled reads data/commits_backfilled.csv at path: per
// repository, when its backfill was done. Missing is empty, like LoadReach.
func LoadCommitsBackfilled(path string) (Reach, error) { return loadReach(path, commitsBackfilledFile) }

// SaveCommitsBackfilled writes r to path whole, in the commits backfilled
// format v1, like SaveReach.
func SaveCommitsBackfilled(path string, r Reach) error {
	return saveReach(path, r, commitsBackfilledFile)
}
