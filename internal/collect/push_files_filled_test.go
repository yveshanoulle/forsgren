package collect

import (
	"errors"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// The push files filled mark (forsgren#589, step 3): data/push_files_filled.csv
// is the twentieth of the mark files, loaded before GitHub is asked and kept
// as it was when nothing moves it.

const pushFilesFilledNow = "# forsgren push files filled v1\nrepository,filled_at\nacme/app,2026-10-01T00:00:00Z\n"

// TestAPushFilesFilledFileThatCannotBeReadRefusesTheRun: a
// push_files_filled.csv not in the format is an error naming it, before
// GitHub is asked anything.
func TestAPushFilesFilledFileThatCannotBeReadRefusesTheRun(t *testing.T) {
	g := issuesOnly(t)
	path := historyPath(t)
	dataOf(path).write(t, "push_files_filled.csv", "nope\n")
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if !errors.Is(r.err, history.ErrMalformed) || !strings.Contains(r.err.Error(), "push_files_filled.csv") {
		t.Errorf("want ErrMalformed naming push_files_filled.csv, got %v", r.err)
	}
	if got := g.seen("/"); len(got) != 0 {
		t.Errorf("want GitHub asked nothing, got %v", got)
	}
}

// TestAPushFilesFilledMarkIsKeptAsItWas: a run that does not move the mark
// leaves its line as it was.
func TestAPushFilesFilledMarkIsKeptAsItWas(t *testing.T) {
	g := issuesOnly(t)
	path := historyPath(t)
	dataOf(path).write(t, PushFilesFilledFile, pushFilesFilledNow)
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	dataOf(path).want(t, PushFilesFilledFile, pushFilesFilledNow)
}
