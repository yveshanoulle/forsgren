package history

// pullsBotFilledFile is the format of data/pulls_bot_filled.csv, the pulls
// bot filled format v1 (forsgren#500): the rows of the reach format, with a
// version line and a column that say what the time is, when the one-time
// fill of the bot status of the repository's stored merged pull requests was
// done. A repository in it is not filled again.
var pullsBotFilledFile = markFormat("# forsgren pulls bot filled v1", "repository,filled_at")

// LoadPullsBotFilled reads data/pulls_bot_filled.csv at path: per repository,
// when its fill was done. Missing is empty, like LoadReach.
func LoadPullsBotFilled(path string) (Reach, error) { return loadReach(path, pullsBotFilledFile) }

// SavePullsBotFilled writes r to path whole, in the pulls bot filled format
// v1, like SaveReach.
func SavePullsBotFilled(path string, r Reach) error {
	return saveReach(path, r, pullsBotFilledFile)
}
