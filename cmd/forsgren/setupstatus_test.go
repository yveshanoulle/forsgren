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
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				for k, v := range c.header {
					w.Header()[k] = v
				}
				w.WriteHeader(c.status)
				if c.status == http.StatusCreated {
					_, _ = w.Write([]byte(`{"number": 7}`))
				}
			}))
			t.Cleanup(srv.Close)
			client, err := github.New(srv.URL, "sesame-sesame-sesame", github.DefaultMaxPages)
			if err != nil {
				t.Fatalf("New: %v", err)
			}
			_, err = client.CreateIssue(context.Background(), "acme/app", "Set up forsgren", "body", []string{setupLabel})
			if got := setupStatus(err); got != c.want {
				t.Errorf("setupStatus(%v) = %q, want %q", err, got, c.want)
			}
		})
	}
	if got := setupStatus(nil); got != statusOK {
		t.Errorf("setupStatus(nil) = %q, want %q", got, statusOK)
	}
}
