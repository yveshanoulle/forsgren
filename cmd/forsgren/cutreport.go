package main

import (
	"errors"
	"io/fs"
	"os"

	"github.com/yveshanoulle/forsgren/internal/collect"
)

// The --cut-report file (forsgren#64, step 3b), collect's side: the report
// of what the run left incomplete (collect.Report, whose text is its one
// shape), for run-summary to say that a green run collected less than all.

// removeCutReport removes the report of an earlier run at path, the first
// thing collect does: a run that fails before it ends leaves no file, which
// the job summary reads as unknown, never as an old run's report. No path, or
// no file, is nothing to do.
func removeCutReport(path string) error {
	if path == "" {
		return nil
	}
	if err := os.Remove(path); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	return nil
}

// writeCutReport writes report to path, whole or not at all (a temporary file
// renamed over path), when the run got to its end: runErr is nil or the
// failed repositories (collect.ErrFailed). A refused run (an unreadable
// history) writes none, for it collected nothing and must not read as
// complete. No path is nothing to do.
func writeCutReport(path string, report collect.Report, runErr error) error {
	if path == "" || (runErr != nil && !errors.Is(runErr, collect.ErrFailed)) {
		return nil
	}
	temp := path + ".tmp"
	err := os.WriteFile(temp, []byte(report.Render()), 0o600)
	if err == nil {
		err = os.Rename(temp, path)
	}
	if err != nil {
		_ = os.Remove(temp)
	}
	return err
}
