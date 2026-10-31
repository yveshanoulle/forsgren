package metrics

import (
	"strings"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// FilesReading is how far the commit files read of a project's repositories
// is (forsgren#594, step 2): the sums over its repositories with a read still
// going, and about how many runs the rest takes. By project, never by
// repository: the Data page is public.
type FilesReading struct {
	Project string
	history.FilesProgress
	Runs int
}

// FilesReadingsOf are the projects, in config order, with a commit files read
// still going in progress (data/commit_files_progress.csv), the runs left at
// perRun commits a run. A repository in no project is left out.
func FilesReadingsOf(projects []config.Project, progress history.CommitFilesProgress, perRun int) []FilesReading {
	var readings []FilesReading
	for _, p := range projects {
		sum := progressOf(repositoriesOf(p), progress)
		if sum.Left > 0 {
			readings = append(readings, FilesReading{Project: p.Name, FilesProgress: sum, Runs: sum.Runs(perRun)})
		}
	}
	return readings
}

// progressOf is the sum of the progress of the repositories in, compared
// ignoring case.
func progressOf(in map[string]bool, progress history.CommitFilesProgress) history.FilesProgress {
	var sum history.FilesProgress
	for repository, p := range progress {
		if in[strings.ToLower(repository)] {
			sum.Read, sum.Left = sum.Read+p.Read, sum.Left+p.Left
		}
	}
	return sum
}

// Words say how far r's read is and what is left, after the project's name.
func (r FilesReading) Words() string {
	return "the files of " + GroupDigits(r.Read) + " of " + plural(r.Read+r.Left, "commit") + " are read, " +
		GroupDigits(r.Left) + " left (about " + plural(r.Runs, "more run") + ")"
}
