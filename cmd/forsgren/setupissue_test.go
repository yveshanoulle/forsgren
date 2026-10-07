package main

import (
	"context"
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
}

func (r *recordingIssues) FindIssueByMarker(_ context.Context, _, _, _ string) (github.SetupIssue, bool, error) {
	return r.found, r.ok, nil
}

func (r *recordingIssues) CreateIssue(_ context.Context, _, title, body string, labels []string) (int64, error) {
	r.calls = append(r.calls, fmt.Sprintf("create %s %v", title, labels))
	r.body = body
	return 1, nil
}

func (r *recordingIssues) UpdateIssue(_ context.Context, _ string, n int64, title, _ string) error {
	r.calls = append(r.calls, fmt.Sprintf("update %d %s", n, title))
	return nil
}

func (r *recordingIssues) ReopenIssue(_ context.Context, _ string, n int64, title, _ string) error {
	r.calls = append(r.calls, fmt.Sprintf("reopen %d %s", n, title))
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
			if err := reportSetup(context.Background(), fake, "acme/app", v, c.missing); err != nil {
				t.Fatalf("reportSetup: %v", err)
			}
			if !reflect.DeepEqual(fake.calls, c.want) {
				t.Fatalf("calls = %q, want %q", fake.calls, c.want)
			}
			if len(c.want) > 0 && strings.HasPrefix(c.want[0], "create") &&
				!strings.HasPrefix(fake.body, needs.Marker) {
				t.Fatalf("created body = %q, want it to start with the marker", fake.body)
			}
		})
	}
}
