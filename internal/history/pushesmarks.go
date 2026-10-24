package history

// pushesReadFile is the format of data/pushes_read.csv, the pushes read
// format v1 (forsgren#397, step 2): the rows of the reach format, with a
// version line and a column that say what the time is, when the pushes to
// the repository's main branch were last read.
var pushesReadFile = markFormat("# forsgren pushes read v1", "repository,read_at")

// LoadPushesRead reads data/pushes_read.csv at path: per repository, when its
// pushes were last read. Missing is empty, like LoadReach.
func LoadPushesRead(path string) (Reach, error) { return loadReach(path, pushesReadFile) }

// SavePushesRead writes r to path whole, in the pushes read format v1, like
// SaveReach.
func SavePushesRead(path string, r Reach) error { return saveReach(path, r, pushesReadFile) }

// pushesDeniedFile is the format of data/pushes_denied.csv, the pushes denied
// format v1 (forsgren#397, step 2): the rows of the reach format, with a
// version line and a column that say what the time is, when GitHub last
// refused the read of the repository's pushes (a 403, the token without
// contents: read). It holds a repository name and a time only.
var pushesDeniedFile = markFormat("# forsgren pushes denied v1", "repository,denied_at")

// LoadPushesDenied reads data/pushes_denied.csv at path: per repository, when
// its push read was last refused. Missing is empty, like LoadReach.
func LoadPushesDenied(path string) (Reach, error) { return loadReach(path, pushesDeniedFile) }

// SavePushesDenied writes r to path whole, in the pushes denied format v1,
// like SaveReach.
func SavePushesDenied(path string, r Reach) error { return saveReach(path, r, pushesDeniedFile) }
