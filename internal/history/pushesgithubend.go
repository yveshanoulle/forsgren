package history

// pushesGitHubEndFile is the format of data/pushes_github_end.csv, the pushes
// github end format v1 (forsgren#583, step 3): per repository whose fill of
// its older pushes reached the end of GitHub's activity list without the
// creation of the branch, the oldest push GitHub keeps: older ones are gone
// from GitHub, not unread.
var pushesGitHubEndFile = markFormat("# forsgren pushes github end v1", "repository,oldest_at")

// LoadPushesGitHubEnd reads data/pushes_github_end.csv at path. Missing is
// empty, like LoadReach.
func LoadPushesGitHubEnd(path string) (Reach, error) { return loadReach(path, pushesGitHubEndFile) }

// SavePushesGitHubEnd writes r to path whole, in the pushes github end format
// v1, like SaveReach.
func SavePushesGitHubEnd(path string, r Reach) error { return saveReach(path, r, pushesGitHubEndFile) }
