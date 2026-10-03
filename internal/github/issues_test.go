package github

import (
	"context"
	"net/url"
	"slices"
	"strconv"
	"testing"
)

const issuesPath = "/repos/acme/app/issues"

// issueItem is one item of a page of issues: an issue numbered number,
// created at created, with body, a pull request when pull is set.
func issueItem(number int, created, body string, pull bool) string {
	item := `{"id": 7000, "number": ` + strconv.Itoa(number) + `, "state": "open", ` +
		`"labels": [{"name": "failure"}], "created_at": "` + created + `", "closed_at": null, ` +
		`"body": ` + body
	if pull {
		item += `, "pull_request": {"url": "https://api.github.com/repos/acme/app/pulls/` + strconv.Itoa(number) + `"}`
	}
	return item + "}"
}

// failureIssues runs FailureIssues on acme/app since the tests' since.
func failureIssues(c *Client) ([]Issue, bool, error) {
	return c.FailureIssues(context.Background(), "acme/app", since)
}

// TestFailureIssuesReadsTheLabelledIssuesWithoutPullRequests (forsgren#18,
// step 2): GET /repos/{o}/{r}/issues with labels=failure, state=all and
// since, 100 per page; a pull request (it has the pull_request field) is
// not an issue. Each issue's number, created_at, closed_at (zero while
// open) and the record block of its body.
func TestFailureIssuesReadsTheLabelledIssuesWithoutPullRequests(t *testing.T) {
	f := newFake(t)
	f.on(issuesPath, reply{body: fixture(t, "issues.json")})
	got, truncated, err := failureIssues(f.client(t, DefaultMaxPages))
	if err != nil || truncated {
		t.Fatalf("want the issues, got truncated=%v, %v", truncated, err)
	}
	want := []Issue{
		{Number: 42, CreatedAt: at(20, 8, 0, 0), ClosedAt: at(21, 9, 30, 0), Record: FailureRecord{
			FailureStart: at(20, 7, 12, 0), FailedBuild: "12.345", FixedBuild: "12.346",
		}},
		{Number: 41, CreatedAt: at(15, 7, 45, 10)},
	}
	if !slices.Equal(got, want) {
		t.Errorf("want %+v,\n got %+v", want, got)
	}
	wantQuery(t, f, url.Values{
		"labels": {"failure"}, "state": {"all"}, "since": {"2026-08-01T00:00:00Z"}, "per_page": {"100"},
	})
}

// TestFailureIssuesFollowsTheLinkNext: every page is read, a page of pull
// requests only included, since GitHub's since filter (by update time) is
// the only cut.
func TestFailureIssuesFollowsTheLinkNext(t *testing.T) {
	f := newFake(t)
	f.on(issuesPath, reply{header: next(issuesPath, "2"),
		body: "[" + issueItem(45, "2026-09-25T10:00:00Z", "null", true) + "]"})
	f.onPage(issuesPath, "2", reply{header: next(issuesPath, "3"),
		body: "[" + issueItem(44, "2026-09-24T10:00:00Z", "null", false) + "]"})
	f.onPage(issuesPath, "3", reply{body: "[" + issueItem(12, "2026-06-01T10:00:00Z", `""`, false) + "]"})
	wantNumbers(t, f.client(t, DefaultMaxPages), false, 44, 12)
}

// TestFailureIssuesStopsAtThePageLimit and says so.
func TestFailureIssuesStopsAtThePageLimit(t *testing.T) {
	f := newFake(t)
	f.on(issuesPath, reply{header: next(issuesPath, "2"),
		body: "[" + issueItem(44, "2026-09-24T10:00:00Z", "null", false) + "]"})
	wantNumbers(t, f.client(t, 1), true, 44)
}

// wantNumbers fails unless FailureIssues with c succeeds with the issues
// numbered want, in order, cut or not as cut says.
func wantNumbers(t *testing.T, c *Client, cut bool, want ...int64) {
	t.Helper()
	got, truncated, err := failureIssues(c)
	if err != nil {
		t.Fatalf("want the issues, got %v", err)
	}
	numbers := make([]int64, 0, len(got))
	for _, i := range got {
		numbers = append(numbers, i.Number)
	}
	if !slices.Equal(numbers, want) {
		t.Errorf("want the issues %v, got %v", want, numbers)
	}
	if truncated != cut {
		t.Errorf("want truncated=%v, got %v", cut, truncated)
	}
}

// TestFailureIssuesRefusesAnIssueItCannotStore: an issue needs a number and
// a creation time; the error names the repository and the path.
func TestFailureIssuesRefusesAnIssueItCannotStore(t *testing.T) {
	for name, body := range map[string]string{
		"no number":     `[{"id": 1, "created_at": "2026-09-24T10:00:00Z", "body": null}]`,
		"no created_at": `[{"id": 1, "number": 44, "created_at": null, "body": null}]`,
		"not a list":    `{"message": "Moved"}`,
		"bad closed_at": `[{"id": 1, "number": 44, "created_at": "2026-09-24T10:00:00Z", "closed_at": "soon"}]`,
	} {
		t.Run(name, func(t *testing.T) {
			f := newFake(t)
			f.on(issuesPath, reply{body: body})
			_, _, err := failureIssues(f.client(t, DefaultMaxPages))
			wantError(t, err, ErrAnswer, "acme/app: ", issuesPath)
		})
	}
}

// TestTheFailureRecordBlock: the lines `failure-start:`, `failed-build:` and
// `fixed-build:` of an issue's body, each alone on its line, surrounding
// spaces and a carriage return ignored, the first of a repeated line
// winning. failure-start is ISO 8601 with an offset, to the minute (as the
// record block is written) or to the second, kept in UTC; a time forsgren
// cannot read is no time. A missing line is empty.
func TestTheFailureRecordBlock(t *testing.T) {
	brussels := FailureRecord{FailureStart: at(20, 7, 12, 0)}
	builds := FailureRecord{FailedBuild: "12.345", FixedBuild: "12.346"}
	for name, c := range map[string]struct {
		body string
		want FailureRecord
	}{
		"empty body":          {"", FailureRecord{}},
		"minute and offset":   {"failure-start: 2026-09-20T09:12+02:00", brussels},
		"seconds and offset":  {"failure-start: 2026-09-20T09:12:00+02:00", brussels},
		"seconds in UTC":      {"failure-start: 2026-09-20T07:12:00Z", brussels},
		"minute in UTC":       {"failure-start: 2026-09-20T07:12Z", brussels},
		"spaces and CRLF":     {"Crash.\r\n   failure-start:   2026-09-20T09:12+02:00  \r\n", brussels},
		"first one wins":      {"failure-start: 2026-09-20T09:12+02:00\nfailure-start: 2026-09-21T09:12+02:00", brussels},
		"no offset":           {"failure-start: 2026-09-20T09:12", FailureRecord{}},
		"a date only":         {"failure-start: 2026-09-20", FailureRecord{}},
		"inside a sentence":   {"We set failure-start: 2026-09-20T09:12+02:00 later", FailureRecord{}},
		"other case":          {"Failure-Start: 2026-09-20T09:12+02:00", FailureRecord{}},
		"the builds":          {"failed-build: 12.345\nfixed-build:  12.346 ", builds},
		"fractional second":   {"failure-start: 2026-09-20T09:12:00.700+02:00", brussels},
		"fixed build pending": {"failed-build: 12.345\nfixed-build:", FailureRecord{FailedBuild: "12.345"}},
	} {
		t.Run(name, func(t *testing.T) {
			if got := parseRecord(c.body); got != c.want {
				t.Errorf("want %+v, got %+v", c.want, got)
			}
		})
	}
}
