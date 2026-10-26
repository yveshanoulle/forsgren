package history

// pushCommitsFilledFile is the format of data/push_commits_filled.csv, the
// push commits filled format v1 (forsgren#470): the rows of the reach format,
// with a version line and a column that say what the time is, when the
// one-time fill of the lines of the repository's stored merge pushes was
// done. A repository in it is not filled again.
var pushCommitsFilledFile = markFormat("# forsgren push commits filled v1", "repository,filled_at")

// LoadPushCommitsFilled reads data/push_commits_filled.csv at path: per
// repository, when its fill was done. Missing is empty, like LoadReach.
func LoadPushCommitsFilled(path string) (Reach, error) { return loadReach(path, pushCommitsFilledFile) }

// SavePushCommitsFilled writes r to path whole, in the push commits filled
// format v1, like SaveReach.
func SavePushCommitsFilled(path string, r Reach) error {
	return saveReach(path, r, pushCommitsFilledFile)
}
