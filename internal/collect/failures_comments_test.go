package collect

import (
	"errors"
	"io/fs"
	"net/http"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/github"
)

// commentsPath43 is the comments of acme/app's issue 43.
const commentsPath43 = issuesPath + "/43/comments"

// commentJSON is one comment of an issue as GitHub lists it; body is JSON.
func commentJSON(id int, body string) string {
	return `{"id": ` + strconv.Itoa(id) + `, "created_at": "2026-09-22T09:00:00Z", "body": ` + body + `}`
}

// blockAt is a comment body with a record block starting at 09:12 Brussels
// on 2026-09-day.
func blockAt(day string) string {
	return `"failure-start: 2026-09-` + day + `T09:12+02:00\r\nfailed-build: 12.345"`
}

// TestACommentGivesTheRecordBlockWhenTheBodyHasNone (forsgren#37, decision
// option 1): the body has no failure-start, so the issue's comments are read,
// once, oldest first; the first comment with a block wins, a later one does
// not, and fragments of different comments are never combined.
func TestACommentGivesTheRecordBlockWhenTheBodyHasNone(t *testing.T) {
	g := issuesOnly(t, issueJSON(43, "2026-09-22T08:00:00Z", "", "null"))
	g.bodies[commentsPath43] = list(
		commentJSON(1, `"Looking into it."`),
		commentJSON(2, `"fixed-build: 12.346"`),
		commentJSON(3, blockAt("20")),
		commentJSON(4, blockAt("21")),
	)
	path := historyPath(t)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if r.err != nil || r.stderr != "" {
		t.Fatalf("want a quiet run, got %v, %q", r.err, r.stderr)
	}
	wantFailures(t, path, failure(43, at(22, 8, 0), time.Time{}, at(20, 7, 12)))
	if asked := g.seen(commentsPath43); len(asked) != 1 {
		t.Errorf("want the comments of issue 43 asked once, got %v", asked)
	}
}

// TestTheBodyWinsAndItsCommentsAreNotRead: a body with a record block is
// the block, a newer one in a comment does not override it, and the
// comments are not even requested.
func TestTheBodyWinsAndItsCommentsAreNotRead(t *testing.T) {
	g := issuesOnly(t, issueJSON(43, "2026-09-22T08:00:00Z", "", recordBlock))
	g.bodies[commentsPath43] = list(commentJSON(1, blockAt("25")))
	path := historyPath(t)
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	wantFailures(t, path, failure(43, at(22, 8, 0), time.Time{}, at(20, 7, 12)))
	if asked := g.seen(commentsPath43); len(asked) != 0 {
		t.Errorf("want no request for the comments of an issue whose body has the block, got %v", asked)
	}
}

// TestNoBlockAnywhereLeavesTheStartEmptyAndNamesTheIssue: neither the body nor
// a comment has one, so failure_start stays empty and stderr says both were
// looked at.
func TestNoBlockAnywhereLeavesTheStartEmptyAndNamesTheIssue(t *testing.T) {
	g := issuesOnly(t, issueJSON(43, "2026-09-22T08:00:00Z", "", "null"))
	g.bodies[commentsPath43] = list(commentJSON(1, `"No block here."`))
	path := historyPath(t)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	want := "collect: acme/app: failure issue #43 has no failure-start line forsgren can read " +
		"in its body or its comments\n"
	if r.err != nil || r.stderr != want {
		t.Errorf("want stderr %q, got %q, %v", want, r.stderr, r.err)
	}
	wantFailures(t, path, failure(43, at(22, 8, 0), time.Time{}, time.Time{}))
}

// TestARefusedCommentsReadFailsTheRepositoryWhole: like the other reads, a
// refused read of the comments fails the repository (nothing of it stored),
// never an empty failure_start.
func TestARefusedCommentsReadFailsTheRepositoryWhole(t *testing.T) {
	g := issuesOnly(t, issueJSON(43, "2026-09-22T08:00:00Z", "", "null"))
	g.bodies[commentsPath43] = `{"message": "Resource not accessible by personal access token"}`
	g.status[commentsPath43] = http.StatusForbidden
	path := historyPath(t)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) || !strings.Contains(r.stderr, "acme/app") {
		t.Errorf("want the repository failed, got %v, %q", r.err, r.stderr)
	}
	if _, err := os.Stat(path); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want no history written, got %v", err)
	}
}

// TestACutCommentsListIsReported: when the comments of an issue run past the
// page limit, the first pages are used and stderr says the rest was not read.
func TestACutCommentsListIsReported(t *testing.T) {
	g := issuesOnly(t, issueJSON(43, "2026-09-22T08:00:00Z", "", "null"))
	g.bodies[commentsPath43] = list(commentJSON(1, blockAt("20")))
	g.paged[commentsPath43] = true
	path := historyPath(t)
	r := g.collect(t, shop(production), path, 1)
	want := "collect: acme/app: read the first 1 page(s) of the comments of failure issue #43 only\n"
	if r.err != nil || r.stderr != want {
		t.Errorf("want stderr %q, got %q, %v", want, r.stderr, r.err)
	}
	wantFailures(t, path, failure(43, at(22, 8, 0), time.Time{}, at(20, 7, 12)))
}
