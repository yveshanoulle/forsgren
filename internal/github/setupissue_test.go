package github

import (
	"context"
	"net/url"
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
