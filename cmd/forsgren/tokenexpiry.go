package main

import (
	"cmp"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/needs"
)

// expiryWarningDays is how many days before its expiry date the token starts
// to be warned about (forsgren#177).
const expiryWarningDays = 14

// tokenExpiryMessage is what to tell about a token that expires on expiry,
// seen at at, and whether to tell it: only for a date at most
// expiryWarningDays after at, or already past. It names the date and how to
// make a new token, in the repository $GITHUB_REPOSITORY, else "this
// installation's repository". collect's warning and the setup issue's item
// are this one text.
func tokenExpiryMessage(expiry, at time.Time) (string, bool) {
	if expiry.After(at.AddDate(0, 0, expiryWarningDays)) {
		return "", false
	}
	when := "expires on " + expiry.UTC().Format(time.DateOnly)
	if expiry.Before(at) {
		when = "has expired on " + expiry.UTC().Format(time.DateOnly)
	}
	repo := cmp.Or(os.Getenv("GITHUB_REPOSITORY"), "this installation's repository")
	return "FORSGREN_TOKEN " + when + ". Make a new fine-grained token and set it " +
		"with `gh secret set FORSGREN_TOKEN -R " + repo + "` in a separate terminal.", true
}

// readTokenExpiry is the expiry date in the file at path, which collect
// --token-expiry wrote: one RFC 3339 line. It says false for no path, a
// file that is missing or unreadable and one that holds no such date; the
// one reader of that file (forsgren#177).
func readTokenExpiry(path string) (time.Time, bool) {
	if path == "" {
		return time.Time{}, false
	}
	raw, err := os.ReadFile(filepath.Clean(path))
	if err != nil {
		return time.Time{}, false
	}
	expiry, err := time.Parse(time.RFC3339, strings.TrimSpace(string(raw)))
	return expiry, err == nil
}

// tokenExpiryNeed is the setup issue's item for the token whose expiry date
// collect wrote to path (--token-expiry), and whether there is one: not when
// readTokenExpiry finds no date, or the date is further away than
// expiryWarningDays from at. Then nothing is missing and the setup issue
// closes again (forsgren#177).
func tokenExpiryNeed(path string, at time.Time) (needs.Need, bool) {
	expiry, known := readTokenExpiry(path)
	if !known {
		return needs.Need{}, false
	}
	message, near := tokenExpiryMessage(expiry, at)
	return needs.Need{Kind: "token_expiry", Steps: message}, near
}
