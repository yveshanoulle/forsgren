package github

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"testing"
	"time"
)

// budgetHeaders are the rate-limit headers of one answer, as Go canonicalises
// them; "" leaves a header out.
func budgetHeaders(remaining, limit string, reset time.Time) http.Header {
	h := http.Header{}
	for key, value := range map[string]string{"X-Ratelimit-Remaining": remaining, "X-Ratelimit-Limit": limit,
		"X-Ratelimit-Reset": strconv.FormatInt(reset.Unix(), 10)} {
		if value != "" {
			h.Set(key, value)
		}
	}
	return h
}

// stops and sends are the answers, by the remaining and the limit they give,
// after which the client stops or keeps sending.
var (
	stops = map[string][2]string{
		"below the floor":                  {"80", "5000"},
		"one under 5% of 5000":             {"249", "5000"},
		"1000 an hour: the floor of 100":   {"99", "1000"},
		"a large limit: 5% is the margin":  {"2999", "60000"},
		"no limit header: the floor holds": {"99", ""},
	}
	sends = map[string][2]string{
		"exactly 5% of 5000":           {"250", "5000"},
		"1000 an hour: at the floor":   {"100", "1000"},
		"a large limit: at the margin": {"3000", "60000"},
		"no remaining header":          {"", "5000"},
		"plenty left":                  {"4000", "5000"},
	}
)

// TestAClientAtItsMarginSendsNoFurtherRequest (forsgren#64): the client reads
// X-RateLimit-Remaining and X-RateLimit-Limit on every answer, and once
// Remaining is below max(100, 5% of Limit) it sends no further request and
// returns ErrBudget, naming the repository and the reset time.
func TestAClientAtItsMarginSendsNoFurtherRequest(t *testing.T) {
	reset := time.Now().Add(40 * time.Minute).UTC().Truncate(time.Second)
	for name, c := range stops {
		t.Run(name, func(t *testing.T) {
			requests, err := secondRequest(t, true, budgetHeaders(c[0], c[1], reset))
			wantError(t, err, ErrBudget, "acme/app: ", c[0]+" of ", "resets at "+reset.Format(time.RFC3339))
			if requests != 1 {
				t.Errorf("want no second request, got %d requests", requests)
			}
		})
	}
}

// TestAClientAboveItsMarginKeepsSending: at the margin, or with no number to
// judge by, the second request is sent.
func TestAClientAboveItsMarginKeepsSending(t *testing.T) {
	reset := time.Now().Add(40 * time.Minute)
	for name, c := range sends {
		t.Run(name, func(t *testing.T) {
			wantBothSent(t, true, budgetHeaders(c[0], c[1], reset))
		})
	}
}

// TestAClientWithoutTheMarginKeepsSending: only collect asks for the margin;
// the lookups of render and the setup issue send as before.
func TestAClientWithoutTheMarginKeepsSending(t *testing.T) {
	wantBothSent(t, false, budgetHeaders("10", "5000", time.Now().Add(time.Hour)))
}

// TestTheMarginEndsAtTheReset: a reset time that has passed gives the budget
// back, so the request is sent.
func TestTheMarginEndsAtTheReset(t *testing.T) {
	wantBothSent(t, true, budgetHeaders("10", "5000", time.Now().Add(-time.Minute)))
}

// wantBothSent fails unless a second request after an answer with header is
// sent and answered.
func wantBothSent(t *testing.T, margin bool, header http.Header) {
	t.Helper()
	if requests, err := secondRequest(t, margin, header); err != nil || requests != 2 {
		t.Errorf("want a second request and no error, got %d requests, %v", requests, err)
	}
}

// secondRequest answers a first request with header, then makes a second one,
// on a client with the margin or without: how many requests the fake got and
// the second one's error.
func secondRequest(t *testing.T, margin bool, header http.Header) (int, error) {
	t.Helper()
	f := newFake(t)
	f.on(deploymentsPath, reply{body: "[]", header: header})
	f.on(releasesPath, reply{body: "[]"})
	client := f.client(t, DefaultMaxPages)
	if margin {
		client.WithBudgetMargin()
	}
	if err := calls("acme/app")["deployments"](client); err != nil {
		t.Fatalf("the first request has no answer to judge by, got %v", err)
	}
	err := calls("acme/app")["releases"](client)
	return len(f.seen()), err
}

// TestEveryCallStopsAtTheMargin: the margin is kept by the one place every
// call sends through, so no call can start a request past it.
func TestEveryCallStopsAtTheMargin(t *testing.T) {
	reset := time.Now().Add(time.Hour)
	for name, call := range calls("acme/app") {
		t.Run(name, func(t *testing.T) {
			f := newFake(t)
			f.on(deploymentsPath, reply{body: "[]", header: budgetHeaders("10", "5000", reset)})
			client := f.client(t, DefaultMaxPages).WithBudgetMargin()
			if _, _, err := client.Deployments(context.Background(), "acme/app", "production", sinceOnly); err != nil {
				t.Fatal(err)
			}
			wantError(t, call(client), ErrBudget)
			if n := len(f.seen()); n != 1 {
				t.Errorf("want only the first request, got %d", n)
			}
		})
	}
}

// TestARefusalAtZeroIsStillARateLimit: a request GitHub refuses with nothing
// left stays ErrRateLimit, a failure; the margin only stops requests not yet
// sent.
func TestARefusalAtZeroIsStillARateLimit(t *testing.T) {
	f := newFake(t)
	f.on(deploymentsPath, reply{status: 403, header: budgetHeaders("0", "5000", time.Now().Add(time.Hour))})
	err := calls("acme/app")["deployments"](f.client(t, DefaultMaxPages).WithBudgetMargin())
	wantError(t, err, ErrRateLimit)
	if errors.Is(err, ErrBudget) {
		t.Errorf("want a refusal, not the margin: %v", err)
	}
}

// TestReserveStopsWhereTheCallerCouldNotFinish (forsgren#64, decision #239):
// with 300 of 5000 left the margin is 250, so 50 requests are still to send
// and one more than the margin leaves is permitted; a caller that needs n
// more after this one is refused when fewer than n are spare, with the
// ErrBudget message of every other stop. No margin, no answer yet, or a
// reset that has passed: nil.
func TestReserveStopsWhereTheCallerCouldNotFinish(t *testing.T) {
	reset := time.Now().Add(40 * time.Minute).UTC().Truncate(time.Second)
	client := reservedClient(t, budgetHeaders("300", "5000", reset), true)
	if err := client.Reserve("acme/app", 50); err != nil {
		t.Errorf("want 50 spare for 50 needed, got %v", err)
	}
	wantError(t, client.Reserve("acme/app", 51), ErrBudget, "acme/app: ", "300 of 5000",
		"resets at "+reset.Format(time.RFC3339))
	for name, c := range map[string]*Client{
		"no margin":   reservedClient(t, budgetHeaders("300", "5000", reset), false),
		"after reset": reservedClient(t, budgetHeaders("300", "5000", time.Now().Add(-time.Minute)), true),
		"no number":   reservedClient(t, budgetHeaders("", "5000", reset), true),
		"no answer":   newClientWithMargin(t),
	} {
		if err := c.Reserve("acme/app", 5000); err != nil {
			t.Errorf("%s: want no stop, got %v", name, err)
		}
	}
}

// newClientWithMargin is a client with the margin that has had no answer.
func newClientWithMargin(t *testing.T) *Client {
	t.Helper()
	return newFake(t).client(t, DefaultMaxPages).WithBudgetMargin()
}

// reservedClient is a client, with the margin or without, that has had one
// answer with header.
func reservedClient(t *testing.T, header http.Header, margin bool) *Client {
	t.Helper()
	f := newFake(t)
	f.on(deploymentsPath, reply{body: "[]", header: header})
	client := f.client(t, DefaultMaxPages)
	if margin {
		client.WithBudgetMargin()
	}
	if err := calls("acme/app")["deployments"](client); err != nil {
		t.Fatal(err)
	}
	return client
}
