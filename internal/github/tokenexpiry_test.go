package github

import (
	"net/http"
	"testing"
	"time"
)

// expiryHeader is GitHub's header on an answer to a token that has an expiry
// date (forsgren#177).
const expiryHeader = "GitHub-Authentication-Token-Expiration"

// expiryAfter reads the default branch of acme/app from a fake that answers
// with header, and returns the expiry the client recorded.
func expiryAfter(t *testing.T, header http.Header) (time.Time, bool) {
	t.Helper()
	f := newFake(t)
	f.on("/repos/acme/app", reply{header: header, body: `{"default_branch":"main"}`})
	c := f.client(t, 1)
	if _, err := c.DefaultBranch(t.Context(), "acme/app"); err != nil {
		t.Fatalf("want the default branch, got %v", err)
	}
	return c.TokenExpiry()
}

// TestTheClientRecordsTheTokenExpiryFromTheAnswersHeader (forsgren#177): the
// date of GitHub's token expiration header, in UTC or with a numeric offset,
// is the token's expiry.
func TestTheClientRecordsTheTokenExpiryFromTheAnswersHeader(t *testing.T) {
	cases := []struct{ name, value, want string }{
		{"UTC", "2027-01-12 08:35:47 UTC", "2027-01-12T08:35:47Z"},
		{"offset", "2027-01-12 08:35:47 -0400", "2027-01-12T12:35:47Z"},
	}
	for _, c := range cases {
		got, ok := expiryAfter(t, http.Header{expiryHeader: {c.value}})
		if !ok || got.UTC().Format(time.RFC3339) != c.want {
			t.Errorf("%s: want expiry %s, got %v (%v)", c.name, c.want, got, ok)
		}
	}
}

// TestNoTokenExpiryWithoutAUsableHeader (forsgren#177): a token without an
// expiry date gets no header, and a header that is not a date is no expiry
// either; neither is an error.
func TestNoTokenExpiryWithoutAUsableHeader(t *testing.T) {
	cases := map[string]http.Header{
		"missing":   {},
		"empty":     {expiryHeader: {""}},
		"not date":  {expiryHeader: {"soon"}},
		"date only": {expiryHeader: {"2027-01-12"}},
		"zone name": {expiryHeader: {"2027-01-12 08:35:47 PST"}},
	}
	for name, h := range cases {
		if got, ok := expiryAfter(t, h); ok {
			t.Errorf("%s: want no expiry, got %v", name, got)
		}
	}
}

// answersTo reads the default branch of each repository of acme in turn from
// a fake that answers with the header of the same index, with the client
// shaped by shape (nil for the installation's own).
func answersTo(t *testing.T, shape func(*Client) *Client, headers ...http.Header) *Client {
	t.Helper()
	f := newFake(t)
	c := f.client(t, 1)
	if shape != nil {
		c = shape(c)
	}
	for i, h := range headers {
		repo := "acme/app" + string(rune('a'+i))
		f.on("/repos/"+repo, reply{header: h, body: `{"default_branch":"main"}`})
		if _, err := c.DefaultBranch(t.Context(), repo); err != nil {
			t.Fatalf("want the default branch, got %v", err)
		}
	}
	return c
}

// TestAMissingHeaderKeepsTheLastExpiry (forsgren#177): an answer without the
// header after one with it leaves the date as it was; an answer with a newer
// date replaces it.
func TestAMissingHeaderKeepsTheLastExpiry(t *testing.T) {
	valid := http.Header{expiryHeader: {"2027-01-12 08:35:47 UTC"}}
	c := answersTo(t, nil, valid, http.Header{})
	if got, ok := c.TokenExpiry(); !ok || got.UTC().Format(time.RFC3339) != "2027-01-12T08:35:47Z" {
		t.Errorf("want the date kept, got %v (%v)", got, ok)
	}
	newer := http.Header{expiryHeader: {"2027-02-01 00:00:00 UTC"}}
	c = answersTo(t, nil, valid, http.Header{}, newer)
	if got, _ := c.TokenExpiry(); got.UTC().Format(time.RFC3339) != "2027-02-01T00:00:00Z" {
		t.Errorf("want the newer date, got %v", got)
	}
}

// TestAnUnreadableHeaderKeepsTheLastExpiryAndIsNotedOnce (forsgren#177): a
// header that is not a date leaves the last valid date, and the first such
// value is kept for one note per run, not one per answer.
func TestAnUnreadableHeaderKeepsTheLastExpiryAndIsNotedOnce(t *testing.T) {
	valid := http.Header{expiryHeader: {"2027-01-12 08:35:47 UTC"}}
	c := answersTo(t, nil, valid, http.Header{expiryHeader: {"soon"}}, http.Header{expiryHeader: {"later"}})
	if got, ok := c.TokenExpiry(); !ok || got.UTC().Format(time.RFC3339) != "2027-01-12T08:35:47Z" {
		t.Errorf("want the valid date kept, got %v (%v)", got, ok)
	}
	if got, ok := c.UnreadableTokenExpiry(); !ok || got != "soon" {
		t.Errorf("want the first unreadable value \"soon\", got %q (%v)", got, ok)
	}
	if _, ok := answersTo(t, nil, valid).UnreadableTokenExpiry(); ok {
		t.Error("want nothing unreadable after a readable header")
	}
}

// TestOnlyTheInstallationsTokenFeedsTheExpiry (forsgren#177): collect reads
// with the client of FORSGREN_TOKEN (githubClient); a client named for
// another token (jobClient: GITHUB_TOKEN, which expires after an hour and
// whose answers carry the header too) records neither a date nor an
// unreadable value.
func TestOnlyTheInstallationsTokenFeedsTheExpiry(t *testing.T) {
	job := func(c *Client) *Client { return c.WithTokenName("GITHUB_TOKEN") }
	c := answersTo(t, job, http.Header{expiryHeader: {"2027-01-12 08:35:47 UTC"}}, http.Header{expiryHeader: {"soon"}})
	if got, ok := c.TokenExpiry(); ok {
		t.Errorf("want no expiry from the job's token, got %v", got)
	}
	if got, ok := c.UnreadableTokenExpiry(); ok {
		t.Errorf("want no unreadable value from the job's token, got %q", got)
	}
}
