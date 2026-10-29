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

// pushesCutFile is the format of data/pushes_cut.csv, the pushes cut format
// v1 (forsgren#583, step 1): per repository whose push read stopped at the
// page cap, the oldest push time that read reached, so the stored pushes
// start there only because older ones are not read yet.
var pushesCutFile = markFormat("# forsgren pushes cut v1", "repository,cut_at")

// LoadPushesCut reads data/pushes_cut.csv at path: per repository, where its
// push read stopped at the page cap. Missing is empty, like LoadReach.
func LoadPushesCut(path string) (Reach, error) { return loadReach(path, pushesCutFile) }

// SavePushesCut writes r to path whole, in the pushes cut format v1, like
// SaveReach.
func SavePushesCut(path string, r Reach) error { return saveReach(path, r, pushesCutFile) }

// pushesCheckedFile is the format of data/pushes_checked.csv, the pushes
// checked format v1 (forsgren#583, step 1): per repository, when the one-time
// check of how far back GitHub's activity list reaches ran, so a push read
// cut before data/pushes_cut.csv existed is found once.
var pushesCheckedFile = markFormat("# forsgren pushes checked v1", "repository,checked_at")

// LoadPushesChecked reads data/pushes_checked.csv at path: per repository,
// when its reach was checked. Missing is empty, like LoadReach.
func LoadPushesChecked(path string) (Reach, error) { return loadReach(path, pushesCheckedFile) }

// SavePushesChecked writes r to path whole, in the pushes checked format v1,
// like SaveReach.
func SavePushesChecked(path string, r Reach) error { return saveReach(path, r, pushesCheckedFile) }

// data/pushes_denied.csv (forsgren#397, step 2; the token column since
// forsgren#414) is the denied format of pullsdenied.go: when GitHub last
// refused the read of the repository's pushes (a 403, the token without
// contents: read), and the name of the token that was refused.
