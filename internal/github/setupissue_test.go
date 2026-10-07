package github

import (
	"context"
	"encoding/json"
	"errors"
	"net/url"
	"reflect"
	"strconv"
	"strings"
	"testing"
)

const setupMarker = "<!-- forsgren:setup-issue -->"

// setupItem is one item of a page of issues: numbered number, in state,
// with body, a pull request when pull is set; all carry the setup label.
func setupItem(number int, state, body string, pull bool) string {
	item := `{"id": 7000, "number": ` + strconv.Itoa(number) + `, "state": "` + state + `", ` +
		`"title": "Set up forsgren", "labels": [{"name": "forsgren-setup"}], ` +
		`"created_at": "2026-09-24T10:00:00Z", "closed_at": null, "body": "` + body + `"`
	if pull {
		item += `, "pull_request": {"url": "https://api.github.com/repos/acme/app/pulls/` + strconv.Itoa(number) + `"}`
	}
	return item + "}"
}

// TestFindIssueByMarkerPicksTheMarkedLabelledIssue (forsgren#73): the
// issues labelled forsgren-setup, open and closed, the one whose body holds
// the marker; no marker, no touch; a pull request is not an issue; the
// lowest number of several.
func TestFindIssueByMarkerPicksTheMarkedLabelledIssue(t *testing.T) {
	marked := "Hello\\n" + setupMarker
	for name, c := range map[string]struct {
		items []string
		want  SetupIssue
		found bool
	}{
		"no labelled issue":  {nil, SetupIssue{}, false},
		"no marker":          {[]string{setupItem(5, "open", "Hello", false)}, SetupIssue{}, false},
		"open with marker":   {[]string{setupItem(5, "open", marked, false)}, wantSetup(5, "open"), true},
		"closed with marker": {[]string{setupItem(6, "closed", marked, false)}, wantSetup(6, "closed"), true},
		"pull request":       {[]string{setupItem(7, "open", marked, true)}, SetupIssue{}, false},
		"two marked": {
			[]string{setupItem(9, "open", marked, false), setupItem(4, "closed", marked, false)},
			wantSetup(4, "closed"), true,
		},
	} {
		t.Run(name, func(t *testing.T) {
			assertFindsSetup(t, c.items, c.want, c.found)
		})
	}
}

// assertFindsSetup serves items as the one page of issues and fails unless
// FindIssueByMarker answers want and found, asking with setupQuery.
func assertFindsSetup(t *testing.T, items []string, want SetupIssue, found bool) {
	t.Helper()
	f := newFake(t)
	f.on(issuesPath, reply{body: "[" + strings.Join(items, ",") + "]"})
	got, ok, err := f.client(t, DefaultMaxPages).FindIssueByMarker(
		context.Background(), "acme/app", "forsgren-setup", setupMarker)
	if err != nil || ok != found || got != want {
		t.Errorf("want %+v found=%v, got %+v found=%v, %v", want, found, got, ok, err)
	}
	if found {
		wantQuery(t, f, setupQuery())
	}
	for _, r := range f.seen() {
		assertQuery(t, r.URL.Query(), setupQuery())
	}
}

// wantSetup is the SetupIssue the fixtures give: the body as decoded.
func wantSetup(number int64, state string) SetupIssue {
	return SetupIssue{Number: number, State: state, Title: "Set up forsgren", Body: "Hello\n" + setupMarker}
}

// setupQuery is the query FindIssueByMarker asks with.
func setupQuery() url.Values {
	return url.Values{"labels": {"forsgren-setup"}, "state": {"all"}, "per_page": {"100"}}
}

// assertQuery fails unless got has every parameter of want.
func assertQuery(t *testing.T, got, want url.Values) {
	t.Helper()
	for name := range want {
		if got.Get(name) != want.Get(name) {
			t.Errorf("want query %s=%q, got %q", name, want.Get(name), got.Get(name))
		}
	}
}

// TestFindIssueByMarkerPassesOnItsErrors (forsgren#73): an error comes back
// as it is, with nothing found: a repository name that is not owner/name
// (ErrRepositoryName), a body that is not JSON (the decoder's
// *json.SyntaxError) and an HTTP error status (ErrStatus).
func TestFindIssueByMarkerPassesOnItsErrors(t *testing.T) {
	for name, c := range map[string]struct {
		repo  string
		reply reply
		is    func(error) bool
	}{
		"invalid repository name": {"acme", reply{body: "[]"}, isError(ErrRepositoryName)},
		"malformed body":          {"acme/app", reply{body: "{not json"}, isSyntaxError},
		"http error status":       {"acme/app", reply{status: 500, body: "[]"}, isError(ErrStatus)},
	} {
		t.Run(name, func(t *testing.T) {
			f := newFake(t)
			f.on(issuesPath, c.reply)
			got, ok, err := f.client(t, DefaultMaxPages).FindIssueByMarker(
				context.Background(), c.repo, "forsgren-setup", setupMarker)
			if ok || got != (SetupIssue{}) || err == nil || !c.is(err) {
				t.Errorf("want nothing found and the error's reason, got %+v found=%v, %v", got, ok, err)
			}
		})
	}
}

// isError is the check that an error is target, by errors.Is.
func isError(target error) func(error) bool {
	return func(err error) bool { return errors.Is(err, target) }
}

// isSyntaxError says whether err is the JSON decoder's syntax error.
func isSyntaxError(err error) bool {
	var syntax *json.SyntaxError
	return errors.As(err, &syntax)
}

// TestCreateIssuePostsTheIssueAndReturnsItsNumber (forsgren#73, step 9): one
// POST to the repository's issues with the title, the body and the labels as
// JSON, and the number of the issue GitHub answers with.
func TestCreateIssuePostsTheIssueAndReturnsItsNumber(t *testing.T) {
	f := newFake(t)
	f.on(issuesPath, reply{status: 201, body: `{"number": 7}`})
	got, err := f.client(t, DefaultMaxPages).CreateIssue(
		context.Background(), "acme/app", "Set up forsgren", "Hello", []string{"forsgren-setup"})
	if err != nil || got != 7 {
		t.Errorf("want number 7, got %d, %v", got, err)
	}
	want := map[string]any{"title": "Set up forsgren", "body": "Hello", "labels": []any{"forsgren-setup"}}
	if sent := bodyOfRequest(t, f, "POST", issuesPath); !reflect.DeepEqual(sent, want) {
		t.Errorf("want the body %v, got %v", want, sent)
	}
}

// TestCreateIssuePassesOnItsErrors (forsgren#73): an error comes back as it
// is, with number 0: a repository name that is not owner/name
// (ErrRepositoryName), an HTTP error status (ErrStatus) and an answer that
// is not JSON (the decoder's *json.SyntaxError).
func TestCreateIssuePassesOnItsErrors(t *testing.T) {
	for name, c := range map[string]struct {
		repo  string
		reply reply
		is    func(error) bool
	}{
		"invalid repository name": {"acme", reply{status: 201, body: `{"number": 7}`}, isError(ErrRepositoryName)},
		"http error status":       {"acme/app", reply{status: 500, body: `{"number": 7}`}, isError(ErrStatus)},
		"malformed body":          {"acme/app", reply{status: 201, body: "{not json"}, isSyntaxError},
	} {
		t.Run(name, func(t *testing.T) {
			f := newFake(t)
			f.on(issuesPath, c.reply)
			got, err := f.client(t, DefaultMaxPages).CreateIssue(
				context.Background(), c.repo, "Set up forsgren", "Hello", []string{"forsgren-setup"})
			if got != 0 || err == nil || !c.is(err) {
				t.Errorf("want number 0 and the error's reason, got %d, %v", got, err)
			}
		})
	}
}

// patchCall is one of the two calls that PATCH an issue's title and body:
// UpdateIssue (no state) and ReopenIssue (state open), on repo, issue 7,
// with the title "Set up forsgren again" and the body "Hello again".
type patchCall func(c *Client, repo string) error

var patchCalls = map[string]patchCall{
	"UpdateIssue": func(c *Client, repo string) error {
		return c.UpdateIssue(context.Background(), repo, 7, "Set up forsgren again", "Hello again")
	},
	"ReopenIssue": func(c *Client, repo string) error {
		return c.ReopenIssue(context.Background(), repo, 7, "Set up forsgren again", "Hello again")
	},
}

// TestPatchIssueSendsTitleAndBody (forsgren#73, steps 10 and 11): one PATCH
// to the issue's own path with the title and the body as JSON; UpdateIssue
// sends no state (reopening is not its job), ReopenIssue sends state open, so
// the one setup issue is reopened and updated together.
func TestPatchIssueSendsTitleAndBody(t *testing.T) {
	for name, want := range map[string]map[string]any{
		"UpdateIssue": {"title": "Set up forsgren again", "body": "Hello again"},
		"ReopenIssue": {"title": "Set up forsgren again", "body": "Hello again", "state": "open"},
	} {
		t.Run(name, func(t *testing.T) {
			f := newFake(t)
			f.on(issuesPath+"/7", reply{body: `{"number": 7}`})
			if err := patchCalls[name](f.client(t, DefaultMaxPages), "acme/app"); err != nil {
				t.Errorf("want no error, got %v", err)
			}
			if sent := bodyOfRequest(t, f, "PATCH", issuesPath+"/7"); !reflect.DeepEqual(sent, want) {
				t.Errorf("want the body %v, got %v", want, sent)
			}
		})
	}
}

// TestPatchIssuePassesOnItsErrors (forsgren#73): for UpdateIssue and
// ReopenIssue alike, an error comes back as it is: a repository name that is
// not owner/name (ErrRepositoryName) and an HTTP error status (ErrStatus).
func TestPatchIssuePassesOnItsErrors(t *testing.T) {
	for call, patch := range patchCalls {
		for name, c := range map[string]struct {
			repo  string
			reply reply
			is    func(error) bool
		}{
			"invalid repository name": {"acme", reply{body: `{"number": 7}`}, isError(ErrRepositoryName)},
			"http error status":       {"acme/app", reply{status: 500, body: `{"number": 7}`}, isError(ErrStatus)},
		} {
			t.Run(call+"/"+name, func(t *testing.T) {
				f := newFake(t)
				f.on(issuesPath+"/7", c.reply)
				if err := patch(f.client(t, DefaultMaxPages), c.repo); err == nil || !c.is(err) {
					t.Errorf("want the error's reason, got %v", err)
				}
			})
		}
	}
}

// TestCloseIssueCommentsThenCloses (forsgren#73, step 12): one POST of the
// comment to the issue's comments, then one PATCH of the issue with only the
// state closed, in that order: the reader sees why it was closed, and a
// failed comment leaves the issue open.
func TestCloseIssueCommentsThenCloses(t *testing.T) {
	f := newFake(t)
	f.on(issuesPath+"/7/comments", reply{status: 201, body: `{"id": 1}`})
	f.on(issuesPath+"/7", reply{body: `{"number": 7}`})
	comment := "All items are in place."
	err := f.client(t, DefaultMaxPages).CloseIssue(context.Background(), "acme/app", 7, comment)
	if err != nil {
		t.Errorf("want no error, got %v", err)
	}
	wantComment := map[string]any{"body": comment}
	if sent := bodyOfRequest(t, f, "POST", issuesPath+"/7/comments"); !reflect.DeepEqual(sent, wantComment) {
		t.Errorf("want the comment body %v, got %v", wantComment, sent)
	}
	wantClose := map[string]any{"state": "closed"}
	if sent := bodyOfRequest(t, f, "PATCH", issuesPath+"/7"); !reflect.DeepEqual(sent, wantClose) {
		t.Errorf("want the close body %v, got %v", wantClose, sent)
	}
	wantOrder := []string{"POST " + issuesPath + "/7/comments", "PATCH " + issuesPath + "/7"}
	if got := requestLines(f); !reflect.DeepEqual(got, wantOrder) {
		t.Errorf("want the requests in order %v, got %v", wantOrder, got)
	}
}

// TestCloseIssuePassesOnItsErrors (forsgren#73): CloseIssue's errors come
// back as they are, whichever call fails: an invalid repository name
// (ErrRepositoryName), an HTTP error on the comment POST (ErrStatus, and no
// PATCH is sent: the issue stays open) and an HTTP error on the PATCH after
// a comment that went through (ErrStatus, the comment POST sent first).
func TestCloseIssuePassesOnItsErrors(t *testing.T) {
	comments, patch := issuesPath+"/7/comments", issuesPath+"/7"
	ok, bad := reply{status: 201, body: `{"id": 1}`}, reply{status: 500, body: `{}`}
	for name, c := range map[string]struct {
		repo           string
		comment, issue reply
		is             func(error) bool
		wantRequests   []string
	}{
		"invalid repository name": {"acme", ok, ok, isError(ErrRepositoryName), nil},
		"comment http error": {
			"acme/app", bad, ok, isError(ErrStatus), []string{"POST " + comments},
		},
		"close http error": {
			"acme/app", ok, bad, isError(ErrStatus), []string{"POST " + comments, "PATCH " + patch},
		},
	} {
		t.Run(name, func(t *testing.T) {
			f := newFake(t)
			f.on(comments, c.comment)
			f.on(patch, c.issue)
			err := f.client(t, DefaultMaxPages).CloseIssue(context.Background(), c.repo, 7, "Done.")
			if err == nil || !c.is(err) {
				t.Errorf("want the error's reason, got %v", err)
			}
			if got := requestLines(f); !reflect.DeepEqual(got, c.wantRequests) {
				t.Errorf("want the requests %v, got %v", c.wantRequests, got)
			}
		})
	}
}

// requestLines is the requests the fake got, in order, as "METHOD path".
func requestLines(f *fakeGitHub) []string {
	var lines []string
	for _, r := range f.seen() {
		lines = append(lines, r.Method+" "+r.URL.Path)
	}
	return lines
}
