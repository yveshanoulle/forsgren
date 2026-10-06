package collect

import (
	"errors"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// readFile is the content of failures_read.csv holding acme/app at when.
func readFile(when string) string {
	return "# forsgren failures read v1\nrepository,read_at\nacme/app," + when + "\n"
}

// TestTheFailureIssuesAreReadFromWhereTheLastReadEnded (forsgren#67): data/
// failures_read.csv holds, per repository, when its failure issues were last
// read. A run asks from that time less a day, or from history_days back when
// there is none, and moves it to Now only when the read succeeded.
func TestTheFailureIssuesAreReadFromWhereTheLastReadEnded(t *testing.T) {
	stored := readFile("2026-09-20T08:00:00Z")
	for _, c := range []struct {
		name   string
		stored string // the file before the run, empty for none
		code   int    // status of the issues read, 0 for 200
		since  string
		want   string // the file after the run
	}{
		{"no file", "", 0, "2025-10-01T00:00:00Z", readFile("2026-10-01T00:00:00Z")},
		{"a stored time", stored, 0, "2026-09-19T08:00:00Z", readFile("2026-10-01T00:00:00Z")},
		{"a failed read", stored, http.StatusInternalServerError, "2026-09-19T08:00:00Z", stored},
	} {
		t.Run(c.name, func(t *testing.T) {
			since, file := collectFailuresRead(t, c.stored, c.code)
			if since != c.since {
				t.Errorf("want since=%s, got %s", c.since, since)
			}
			raw, _ := os.ReadFile(filepath.Clean(file))
			if string(raw) != c.want {
				t.Errorf("want failures_read.csv\n%q\ngot\n%q", c.want, raw)
			}
		})
	}
}

// TestFailuresReadIsReadBack: SaveReadAt and LoadReadAt round-trip.
func TestFailuresReadIsReadBack(t *testing.T) {
	file := filepath.Join(t.TempDir(), "failures_read.csv")
	at := time.Date(2026, 9, 20, 8, 0, 0, 0, time.UTC)
	if err := history.SaveReadAt(file, history.Reach{"acme/app": at}); err != nil {
		t.Fatal(err)
	}
	if got, err := history.LoadReadAt(file); err != nil || !got["acme/app"].Equal(at) {
		t.Errorf("want acme/app at %v, got %v, %v", at, got, err)
	}
}

// collectFailuresRead runs collect on acme/app with failures_read.csv holding
// stored (none when empty) and the issues read answering code (0 for 200); it
// returns the since of the one issues request and the file's path.
func collectFailuresRead(t *testing.T, stored string, code int) (string, string) {
	t.Helper()
	g := issuesOnly(t)
	g.status[issuesPath] = code
	path := historyPath(t)
	file := filepath.Join(filepath.Dir(path), "failures_read.csv")
	if stored != "" {
		if err := os.MkdirAll(filepath.Dir(file), 0o750); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(file, []byte(stored), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	g.collect(t, shop(production), path, github.DefaultMaxPages)
	asked := g.seen(issuesPath + "?")
	if len(asked) == 0 {
		t.Fatal("want the failure issues asked, got no request")
	}
	q, _ := url.ParseQuery(asked[0][len(issuesPath)+1:])
	return q.Get("since"), file
}

// TestAFailuresReadFileThatCannotBeReadRefusesTheRun (forsgren#67): a
// failures_read.csv not in the format is an error naming it, before GitHub is
// asked anything.
func TestAFailuresReadFileThatCannotBeReadRefusesTheRun(t *testing.T) {
	g := issuesOnly(t)
	path := historyPath(t)
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(filepath.Dir(path), "failures_read.csv"), []byte("nope\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if !errors.Is(r.err, history.ErrMalformed) || !strings.Contains(r.err.Error(), "failures_read.csv") {
		t.Errorf("want ErrMalformed naming failures_read.csv, got %v", r.err)
	}
	if got := g.seen("/"); len(got) != 0 {
		t.Errorf("want GitHub asked nothing, got %v", got)
	}
}

// TestAFailuresReadThatCannotBeSavedFailsTheRun (forsgren#67): the run's
// error names failures_read.csv.
func TestAFailuresReadThatCannotBeSavedFailsTheRun(t *testing.T) {
	path := historyPath(t)
	if err := os.MkdirAll(filepath.Join(filepath.Dir(path), "failures_read.csv.tmp"), 0o750); err != nil {
		t.Fatal(err)
	}
	r := issuesOnly(t).collect(t, shop(production), path, github.DefaultMaxPages)
	if r.err == nil || !strings.Contains(r.err.Error(), "failures_read.csv") {
		t.Errorf("want an error naming failures_read.csv, got %v", r.err)
	}
}
