package history

// pullsReadFile is the format of data/pulls_read.csv, the pulls read format
// v1 (forsgren#255, step 4): the rows of the reach format, with a version line
// and a column that say what the time is, when the closed pull requests of
// the repository were last read whole.
var pullsReadFile = markFormat("# forsgren pulls read v1", "repository,read_at")

// LoadPullsRead reads data/pulls_read.csv at path: per repository, when its
// closed pull requests were last read. Missing is empty, like LoadReach.
func LoadPullsRead(path string) (Reach, error) { return loadReach(path, pullsReadFile) }

// SavePullsRead writes r to path whole, in the pulls read format v1, like
// SaveReach.
func SavePullsRead(path string, r Reach) error { return saveReach(path, r, pullsReadFile) }
