package history

// bugsCutFile is the format of data/issue_bugs_cut.csv, the bugs cut format v1
// (forsgren#140): the rows of the reach format, with a version line and a
// column that say what the time is, when the read of a repository's bug
// issues last stopped at its page cap. A repository in it has bug flags that
// may be incomplete, so the Open bugs it adds to are not shown as a number.
var bugsCutFile = markFormat("# forsgren bugs cut v1", "repository,cut_at")

// LoadBugsCut reads data/issue_bugs_cut.csv at path: per repository, when its
// bug read last stopped at the page cap. Missing is empty, like LoadReach.
func LoadBugsCut(path string) (Reach, error) { return loadReach(path, bugsCutFile) }

// SaveBugsCut writes r to path whole, in the bugs cut format v1, like
// SaveReach.
func SaveBugsCut(path string, r Reach) error { return saveReach(path, r, bugsCutFile) }
