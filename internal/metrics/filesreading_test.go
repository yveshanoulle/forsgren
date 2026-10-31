package metrics

import (
	"reflect"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// The commit files reads still going, per project (forsgren#594, step 2), for
// the Data page: by project, never by repository, the site being public.

// readingProjects are Konenki with two repositories, Acme with one, and Quiet,
// whose repository has no read going.
func readingProjects() []config.Project {
	repos := func(names ...string) []config.Repository {
		r := make([]config.Repository, len(names))
		for i, n := range names {
			r[i] = config.Repository{Name: n}
		}
		return r
	}
	return []config.Project{
		{Name: "Konenki", Repositories: repos("acme/Konenki-App", "acme/konenki-api")},
		{Name: "Quiet", Repositories: repos("acme/quiet")},
		{Name: "Acme", Repositories: repos("acme/shop")},
	}
}

// TestFilesReadingsSumAProjectsRepositoriesInConfigOrder: a project's read and
// left are the sums over its repositories, matched ignoring case; a project
// with no read going and a repository in no project have no line; the runs
// left are rounded up at the run's cap.
func TestFilesReadingsSumAProjectsRepositoriesInConfigOrder(t *testing.T) {
	progress := history.CommitFilesProgress{
		"acme/konenki-app": {Read: 3000, Left: 2925},
		"ACME/konenki-api": {Read: 1199, Left: 1000},
		"acme/shop":        {Read: 1000, Left: 1},
		"acme/elsewhere":   {Read: 5, Left: 5},
	}
	got := FilesReadingsOf(readingProjects(), progress, 1000)
	want := []FilesReading{
		{Project: "Konenki", FilesProgress: history.FilesProgress{Read: 4199, Left: 3925}, Runs: 4},
		{Project: "Acme", FilesProgress: history.FilesProgress{Read: 1000, Left: 1}, Runs: 1},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("FilesReadingsOf = %+v, want %+v", got, want)
	}
}

// TestFilesReadingsAreNoneWithoutAReadGoing: no progress, no line.
func TestFilesReadingsAreNoneWithoutAReadGoing(t *testing.T) {
	if got := FilesReadingsOf(readingProjects(), history.CommitFilesProgress{}, 1000); len(got) != 0 {
		t.Errorf("FilesReadingsOf = %+v, want none", got)
	}
}

// TestFilesReadingWordsSayHowFarAndWhatIsLeft: the words after the project's
// name, counts grouped as every count of the page, one run singular.
func TestFilesReadingWordsSayHowFarAndWhatIsLeft(t *testing.T) {
	cases := map[FilesReading]string{
		{Project: "Konenki", FilesProgress: history.FilesProgress{Read: 4199, Left: 3925}, Runs: 4}: "the files of " +
			GroupDigits(4199) + " of " + GroupDigits(8124) + " commits are read, " +
			GroupDigits(3925) + " left (about 4 more runs)",
		{Project: "Acme", FilesProgress: history.FilesProgress{Read: 10, Left: 1}, Runs: 1}: "the files of " +
			"10 of 11 commits are read, 1 left (about 1 more run)",
	}
	for r, want := range cases {
		if got := r.Words(); got != want {
			t.Errorf("%s: Words() = %q, want %q", r.Project, got, want)
		}
	}
}
