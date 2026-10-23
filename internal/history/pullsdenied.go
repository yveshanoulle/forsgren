package history

// pullsDeniedFile is the format of data/pulls_denied.csv, the pulls denied
// format v1 (forsgren#337, decision #332): the rows of the reach format, with
// a version line and a column that say what the time is, when GitHub last
// refused the read of the repository's pull requests (a 403, the token
// without pull-requests: read). It holds a repository name and a time only.
var pullsDeniedFile = markFormat("# forsgren pulls denied v1", "repository,denied_at")

// LoadPullsDenied reads data/pulls_denied.csv at path: per repository, when
// its pull request read was last refused. Missing is empty, like LoadReach.
func LoadPullsDenied(path string) (Reach, error) { return loadReach(path, pullsDeniedFile) }

// SavePullsDenied writes r to path whole, in the pulls denied format v1, like
// SaveReach.
func SavePullsDenied(path string, r Reach) error { return saveReach(path, r, pullsDeniedFile) }
