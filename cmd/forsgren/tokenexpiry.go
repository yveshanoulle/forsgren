package main

import (
	"cmp"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"time"

	"github.com/yveshanoulle/forsgren/internal/github"
)

// The token expiry warning (forsgren#177), collect's side: the message, the
// --token-expiry file collect clears and writes, and the run log's warning
// and note. check-needs' side, the setup issue's renewal item, is in
// tokenrenewal.go.

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

// removeTokenExpiry removes the expiry file of an earlier run at path, the
// first thing collect does: whatever then fails before the token is answered
// leaves no file, which check-needs reads as unknown, never as an old run's date. No path, or no
// file, is nothing to do; a file that cannot be removed is an error.
func removeTokenExpiry(path string) error {
	if path == "" {
		return nil
	}
	if err := os.Remove(path); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	return nil
}

// The two lines the --token-expiry file holds besides a date (forsgren#194):
// the token answered GitHub and has no expiry date, and, when it is the job's
// own token (GITHUB_TOKEN, route A), that it is renewed every run.
const (
	expiryNone       = "no-expiry"
	expiryNoneRunOwn = "no-expiry run-token"
)

// tokenExpiryLine is the one line client's token has to leave in the file: its
// UTC RFC 3339 expiry date, else, once GitHub answered it without a date,
// expiryNone or expiryNoneRunOwn; none for a token that never got an
// answer, and none when a header was sent that is no date (it may have one).
// Of the token itself nothing is read but whether it is a run token.
func tokenExpiryLine(client *github.Client) (string, bool) {
	if at, known := client.TokenExpiry(); known {
		return at.UTC().Format(time.RFC3339), true
	}
	if _, unreadable := client.UnreadableTokenExpiry(); unreadable {
		return "", false
	}
	switch {
	case client.IsRunToken() && client.Answered():
		return expiryNoneRunOwn, true
	case client.Answered():
		return expiryNone, true
	}
	return "", false
}

// writeTokenExpiry writes what client's token has to say about its expiry to
// path, one line (tokenExpiryLine), whole or not at all: it is written to
// path+".tmp" and renamed over path, and the temporary file is removed when
// that fails. A collect whose token never got an answer leaves no file; the
// file of an earlier run was removed at the start (removeTokenExpiry). What
// this run's own answers say is written even when a repository failed after
// the token answered: it is this run's observation, not an old one. No path is
// nothing to do (forsgren#177, #194).
func writeTokenExpiry(path string, client *github.Client) error {
	line, known := tokenExpiryLine(client)
	if path == "" || !known {
		return nil
	}
	temp := path + ".tmp"
	err := os.WriteFile(temp, []byte(line+"\n"), 0o600)
	if err == nil {
		err = os.Rename(temp, path)
	}
	if err != nil {
		_ = os.Remove(temp)
	}
	return err
}

// warnTokenExpiry says on stderr that the token expires on its date, and how
// to make a new one, when tokenExpiryMessage has something to say; nothing
// for a date further away or none known. The run's outcome is not touched.
func warnTokenExpiry(stderr io.Writer, at time.Time, client *github.Client) {
	expiry, known := client.TokenExpiry()
	if !known {
		return
	}
	if message, near := tokenExpiryMessage(expiry, at); near {
		_, _ = fmt.Fprintf(stderr, "collect: warning: %s\n", message)
	}
}

// noteUnreadableExpiry says once on stderr that GitHub sent an expiry header
// that is not a date, naming its first value (at most 64 bytes, quoted); the
// date kept from earlier answers, if any, stands (forsgren#177).
func noteUnreadableExpiry(stderr io.Writer, client *github.Client) {
	value, unreadable := client.UnreadableTokenExpiry()
	if !unreadable {
		return
	}
	_, _ = fmt.Fprintf(stderr, "collect: note: GitHub sent an expiry header forsgren cannot read: %q\n",
		value[:min(len(value), 64)])
}
