package history

// pullCommitsFilledFile is the format of data/pull_commits_filled.csv, the
// pull commits filled format v1 (forsgren#470): the rows of the reach format,
// with a version line and a column that say what the time is, when the
// one-time fill of the commits of the repository's stored merged pull
// requests was done. A repository in it is not filled again.
var pullCommitsFilledFile = markFormat("# forsgren pull commits filled v1", "repository,filled_at")

// LoadPullCommitsFilled reads data/pull_commits_filled.csv at path: per
// repository, when its fill was done. Missing is empty, like LoadReach.
func LoadPullCommitsFilled(path string) (Reach, error) { return loadReach(path, pullCommitsFilledFile) }

// SavePullCommitsFilled writes r to path whole, in the pull commits filled
// format v1, like SaveReach.
func SavePullCommitsFilled(path string, r Reach) error {
	return saveReach(path, r, pullCommitsFilledFile)
}
