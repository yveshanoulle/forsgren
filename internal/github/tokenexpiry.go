package github

import (
	"net/http"
	"strings"
	"time"
)

// tokenExpiryHeader is the header GitHub adds to every answer to a token that
// has an expiry date (forsgren#177). A token without one gets no header.
const tokenExpiryHeader = "GitHub-Authentication-Token-Expiration"

// The two shapes of the header's value, GitHub's own documented example being
// "2021-04-12 18:37:49 UTC": the zone is the word UTC, or a numeric offset.
var tokenExpiryLayouts = []string{"2006-01-02 15:04:05 UTC", "2006-01-02 15:04:05 -0700"}

// TokenExpiry is the day the token expires, from the header of the answers so
// far, and whether any answer carried one: a token without an expiry date, a
// header that is not a date and no answer yet all say false, never an error.
func (c *Client) TokenExpiry() (time.Time, bool) { return c.expiry, !c.expiry.IsZero() }

// noteExpiry keeps the expiry date h names, when it names one.
func (c *Client) noteExpiry(h http.Header) {
	value := strings.TrimSpace(h.Get(tokenExpiryHeader))
	for _, layout := range tokenExpiryLayouts {
		if at, err := time.Parse(layout, value); err == nil {
			c.expiry = at
			return
		}
	}
}
