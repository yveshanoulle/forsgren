package history

// readAtFile is the format of data/failures_read.csv, the failures read
// format v1 (forsgren#67): the rows of the reach format, with a version line
// and a column that say what the time is, when the failure issues of the
// repository were last read.
var readAtFile = func() format[reachRow, string] {
	f := reachFile
	f.versionLine = "# forsgren failures read v1"
	f.columnLine = "repository,read_at"
	return f
}()

// LoadReadAt reads data/failures_read.csv at path: per repository, when its
// failure issues were last read. Missing is empty, like LoadReach.
func LoadReadAt(path string) (Reach, error) { return loadReach(path, readAtFile) }

// SaveReadAt writes r to path whole, in the failures read format v1, like
// SaveReach.
func SaveReadAt(path string, r Reach) error { return saveReach(path, r, readAtFile) }
