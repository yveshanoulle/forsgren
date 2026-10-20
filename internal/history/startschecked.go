package history

// startsCheckedFile is the format of data/starts_checked.csv, the starts
// checked format v1 (forsgren#245): the rows of the reach format, with a
// version line and a column that say what the time is: when the one-time
// catch-up of the failure_start of a repository's stored failure issues,
// from their comments, was done for it. A repository in it is not caught up
// again.
var startsCheckedFile = markFormat("# forsgren starts checked v1", "repository,checked_at")

// LoadStartsChecked reads data/starts_checked.csv at path: per repository,
// when its catch-up was done. Missing is empty, like LoadReach.
func LoadStartsChecked(path string) (Reach, error) { return loadReach(path, startsCheckedFile) }

// SaveStartsChecked writes r to path whole, in the starts checked format v1,
// like SaveReach.
func SaveStartsChecked(path string, r Reach) error { return saveReach(path, r, startsCheckedFile) }
