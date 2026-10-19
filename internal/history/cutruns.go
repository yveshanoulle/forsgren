package history

// cutRunsFile is the format of data/cut_runs.csv, the cut runs format v1
// (forsgren#64, step 3b): the rows of the reach format, with a version line
// and a column that say what the time is: when a repository's first run
// began that was cut short at the request budget without keeping a day. A
// repository in it was cut short that way on the run before the latest one;
// cut short again without progress it is reported as not progressing.
var cutRunsFile = markFormat("# forsgren cut runs v1", "repository,first_cut_at")

// LoadCutRuns reads data/cut_runs.csv at path: per repository, when its run
// of cuts without progress began. Missing is empty, like LoadReach.
func LoadCutRuns(path string) (Reach, error) { return loadReach(path, cutRunsFile) }

// SaveCutRuns writes r to path whole, in the cut runs format v1, like
// SaveReach.
func SaveCutRuns(path string, r Reach) error { return saveReach(path, r, cutRunsFile) }
