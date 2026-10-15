package main

import (
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/needs"
)

// The token expiry warning (forsgren#177, decision #179), check-needs' side:
// the setup issue's renewal item from what collect wrote to --token-expiry.
// A known date decides alone: near is the item, far is none. An unknown one
// (no readable date) keeps the item the open setup issue carries and never
// makes one.

// tokenFileLine is the one line of the file at path, "" when it cannot be read.
func tokenFileLine(path string) string {
	raw, err := os.ReadFile(filepath.Clean(path))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(raw))
}

// readTokenExpiry is the expiry date in the file at path, which collect
// --token-expiry wrote (writeTokenExpiry): one RFC 3339 line. It says false
// for no path, a file that is missing or unreadable and one that holds no
// such date, the lines expiryNone and expiryNoneRunOwn among them: the
// expiry is then unknown.
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

// renewalNeed is the setup issue's renewal item for a token that expires on
// expiry, seen at at, marked with that date (needs.TokenExpiryMark), and
// whether it is one: only when tokenExpiryMessage has something to say.
func renewalNeed(expiry, at time.Time) (needs.Need, bool) {
	message, near := tokenExpiryMessage(expiry, at)
	return needs.Need{Kind: "token_expiry", Steps: message, Hidden: needs.TokenExpiryMark(expiry)}, near
}

// withKeptToken is missing, plus the renewal item the OPEN setup issue
// already carries (by its mark, with the date it names, rebuilt at at), for a
// run that does not know the token's expiry. The issue is then neither
// closed nor given up on, and an issue that carries no item, a closed one or
// none gets nothing added. A collect that failed leaves no file, so it is
// unknown too.
func withKeptToken(found foundIssue, missing []needs.Need, at time.Time) []needs.Need {
	if !isOpen(found.issue, found.ok) {
		return missing
	}
	expiry, marked := needs.TokenExpiryIn(found.issue.Body)
	if kept, near := renewalNeed(expiry, at); marked && near {
		missing = append(missing, kept)
	}
	return missing
}

// isOpen says whether the lookup found the setup issue (ok) and it is open.
func isOpen(found github.SetupIssue, ok bool) bool { return ok && found.State == "open" }
