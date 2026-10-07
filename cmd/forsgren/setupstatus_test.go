package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/github"
)

// TestSetupStatusSaysHowTheIssueWriteWent (forsgren#73, step 14): a failed
// write of the setup issue is a status, never a red run. The errors are the
// ones internal/github returns for a real CreateIssue call.
func TestSetupStatusSaysHowTheIssueWriteWent(t *testing.T) {
	cases := []struct {
		name   string
		status int
		header http.Header
		want   string
	}{
		{"written", http.StatusCreated, nil, statusOK},
		{"403 without issues: write", http.StatusForbidden, nil, statusNoAccess},
		{"403 that is the rate limit", http.StatusForbidden, http.Header{"X-Ratelimit-Remaining": {"0"}},
			statusRateLimited},
		{"429", http.StatusTooManyRequests, http.Header{"Retry-After": {"30"}}, statusRateLimited},
		{"500", http.StatusInternalServerError, nil, statusFailed},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			err := createIssueAnswered(t, c.status, c.header)
			if got := setupStatus(err); got != c.want {
				t.Errorf("setupStatus(%v) = %q, want %q", err, got, c.want)
			}
		})
	}
	if got := setupStatus(nil); got != statusOK {
		t.Errorf("setupStatus(nil) = %q, want %q", got, statusOK)
	}
}

// createIssueAnswered is the error of a real CreateIssue call against a
// server that answers status with header (and the new issue on a 201).
func createIssueAnswered(t *testing.T, status int, header http.Header) error {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		for k, v := range header {
			w.Header()[k] = v
		}
		w.WriteHeader(status)
		if status == http.StatusCreated {
			_, _ = w.Write([]byte(`{"number": 7}`))
		}
	}))
	t.Cleanup(srv.Close)
	client, err := github.New(srv.URL, "sesame-sesame-sesame", github.DefaultMaxPages)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	text := github.IssueText{Title: "Set up forsgren", Body: "body"}
	_, err = client.CreateIssue(context.Background(), "acme/app", text, []string{setupLabel})
	return err
}
