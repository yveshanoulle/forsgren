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
