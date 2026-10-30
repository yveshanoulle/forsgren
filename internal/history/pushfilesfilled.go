package history

// pushFilesFilledFile is the format of data/push_files_filled.csv, the push
// files filled format v1 (forsgren#589, step 3): per repository, when a run
// of the commit files read reached its oldest stored pushed commit with no
// pushed commit left unread, so a service or rule row's first commit is no
// longer still being read. Unlike commit_files_filled.csv, which says the
// same of the deployed commits, the marker of the Data page reads this one.
var pushFilesFilledFile = markFormat("# forsgren push files filled v1", "repository,filled_at")

// LoadPushFilesFilled reads data/push_files_filled.csv at path: per
// repository, when the files of its pushed commits were all read. Missing is
// empty, like LoadReach.
func LoadPushFilesFilled(path string) (Reach, error) { return loadReach(path, pushFilesFilledFile) }

// SavePushFilesFilled writes r to path whole, in the push files filled format
// v1, like SaveReach.
func SavePushFilesFilled(path string, r Reach) error { return saveReach(path, r, pushFilesFilledFile) }
