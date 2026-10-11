package history

// fullAtFile is the format of data/issues_full.csv, the issues full format v1
// (forsgren#76, decision #109): the rows of the reach format, with a version
// line and a column that say what the time is, when the one full read of the
// repository's issues was done. A repository in it is not read in full again.
var fullAtFile = func() format[reachRow, string] {
	f := reachFile
	f.versionLine = "# forsgren issues full v1"
	f.columnLine = "repository,full_at"
	return f
}()

// LoadFullAt reads data/issues_full.csv at path: per repository, when the one
// full read of its issues was done. Missing is empty, like LoadReach.
func LoadFullAt(path string) (Reach, error) { return loadReach(path, fullAtFile) }
