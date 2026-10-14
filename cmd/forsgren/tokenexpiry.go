package main

import (
	"cmp"
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/github"
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
	return tokenNeed(expiry, message), near
}

// tokenNeed is the setup issue's renewal item with text message, marked with
// the expiry date it is about.
func tokenNeed(expiry time.Time, message string) needs.Need {
	return needs.Need{Kind: "token_expiry", Steps: message, Hidden: needs.TokenExpiryMark(expiry)}
}

// withKeptToken is missing, plus the renewal item the OPEN setup issue
// already carries (by its mark, with the date it names) when the run does not
// know the token's expiry: no readable date in the file at path. The issue is
// then neither closed nor given up on, and an issue that carries no item, a
// closed one or none gets nothing added. A date that is known, near or far,
// is tokenExpiryNeed's to say. A collect that failed leaves no file, so it is
// unknown too (forsgren#177).
func (s setupReport) withKeptToken(
	ctx context.Context, missing []needs.Need, path string, at time.Time,
) ([]needs.Need, error) {
	if _, known := readTokenExpiry(path); known {
		return missing, nil
	}
	found, ok, err := s.issues.FindIssueByMarker(ctx, s.repo, setupLabel, needs.Marker)
	if err != nil || !ok || found.State != "open" {
		return missing, err
	}
	if kept, carries := keptTokenNeed(found.Body, at); carries {
		missing = append(missing, kept)
	}
	return missing, nil
}

// writeTokenExpiry writes the expiry date client's token has to path, one
// UTC RFC 3339 line, or removes path when the client knows none (a token
// without an expiry date, or the job's own). No path is nothing to do
// (forsgren#177).
func writeTokenExpiry(path string, client *github.Client) error {
	if path == "" {
		return nil
	}
	at, known := client.TokenExpiry()
	if !known {
		if err := os.Remove(path); err != nil && !errors.Is(err, fs.ErrNotExist) {
			return err
		}
		return nil
	}
	return os.WriteFile(path, []byte(at.UTC().Format(time.RFC3339)+"\n"), 0o600)
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

// keptTokenNeed is the renewal item the setup issue body carries, rebuilt
// from the date of its mark at at, and whether it carries one that is still
// near (the clock only moves on, so a marked item is).
func keptTokenNeed(body string, at time.Time) (needs.Need, bool) {
	expiry, marked := needs.TokenExpiryIn(body)
	message, near := tokenExpiryMessage(expiry, at)
	return tokenNeed(expiry, message), marked && near
}
