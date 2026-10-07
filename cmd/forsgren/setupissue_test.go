package main

import (
	"context"
	"errors"
	"fmt"
	"reflect"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/needs"
)

// recordingIssues records each call as one line and answers the lookup with
// the configured issue.
type recordingIssues struct {
	found github.SetupIssue
	ok    bool
	calls []string
	body  string
	err   error
}

func (r *recordingIssues) FindIssueByMarker(_ context.Context, _, _, _ string) (github.SetupIssue, bool, error) {
	return r.found, r.ok, r.err
}

func (r *recordingIssues) CreateIssue(
	_ context.Context, _ string, text github.IssueText, labels []string,
) (int64, error) {
	r.calls = append(r.calls, fmt.Sprintf("create %s %v", text.Title, labels))
	r.body = text.Body
	return 1, nil
}

func (r *recordingIssues) UpdateIssue(_ context.Context, _ string, n int64, text github.IssueText) error {
	r.calls = append(r.calls, fmt.Sprintf("update %d %s", n, text.Title))
	return nil
}

func (r *recordingIssues) ReopenIssue(_ context.Context, _ string, n int64, text github.IssueText) error {
	r.calls = append(r.calls, fmt.Sprintf("reopen %d %s", n, text.Title))
	return nil
}

func (r *recordingIssues) CloseIssue(_ context.Context, _ string, n int64, comment string) error {
	r.calls = append(r.calls, fmt.Sprintf("close %d %s", n, comment))
	return nil
}

// TestReportSetupMakesTheCallTheStateCallsFor (forsgren#73, step 13): the
// missing needs and the setup issue's state decide the one write of a run.
func TestReportSetupMakesTheCallTheStateCallsFor(t *testing.T) {
	const v = "0.4.0"
	title := needs.Title(v)
	missing := []needs.Need{{Steps: "grant the permission"}}
	open := github.SetupIssue{Number: 7, State: "open"}
	closed := github.SetupIssue{Number: 7, State: "closed"}
	cases := []struct {
		name    string
		missing []needs.Need
		found   github.SetupIssue
		ok      bool
		want    []string
	}{
		{"nothing missing, no issue", nil, github.SetupIssue{}, false, nil},
		{"missing, no issue", missing, github.SetupIssue{}, false,
			[]string{"create " + title + " [forsgren-setup]"}},
		{"missing, open issue", missing, open, true, []string{"update 7 " + title}},
		{"missing, closed issue", missing, closed, true, []string{"reopen 7 " + title}},
		{"nothing missing, open issue", nil, open, true,
			[]string{"close 7 All items are in place as of forsgren " + v + "."}},
		{"nothing missing, closed issue", nil, closed, true, nil},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			fake := &recordingIssues{found: c.found, ok: c.ok}
			report := setupReport{issues: fake, repo: "acme/app", version: v}
			if err := report.report(context.Background(), c.missing); err != nil {
				t.Fatalf("report: %v", err)
			}
			checkSetupCalls(t, fake, c.want)
		})
	}
}

// checkSetupCalls asserts the calls a run made, and that a created issue's
// body starts with the marker.
func checkSetupCalls(t *testing.T, fake *recordingIssues, want []string) {
	t.Helper()
	if !reflect.DeepEqual(fake.calls, want) {
		t.Fatalf("calls = %q, want %q", fake.calls, want)
	}
	if createsIssue(want) && !strings.HasPrefix(fake.body, needs.Marker) {
		t.Fatalf("created body = %q, want it to start with the marker", fake.body)
	}
}

// createsIssue says whether the first of the calls is a create.
func createsIssue(calls []string) bool {
	return len(calls) > 0 && strings.HasPrefix(calls[0], "create")
}

// TestReportSetupPassesOnALookupError (forsgren#73, step 13): a failed lookup
// comes back as it is, and nothing is written, missing needs or not.
func TestReportSetupPassesOnALookupError(t *testing.T) {
	lookup := errors.New("lookup failed")
	open := github.SetupIssue{Number: 7, State: "open"}
	cases := []struct {
		name    string
		missing []needs.Need
	}{
		{"something missing", []needs.Need{{Steps: "grant the permission"}}},
		{"nothing missing", nil},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			fake := &recordingIssues{found: open, ok: true, err: lookup}
			err := setupReport{issues: fake, repo: "acme/app", version: "0.4.0"}.report(context.Background(), c.missing)
			if !errors.Is(err, lookup) {
				t.Fatalf("report = %v, want the lookup error", err)
			}
			checkSetupCalls(t, fake, nil)
		})
	}
}
