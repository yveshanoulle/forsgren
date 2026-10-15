package main

// The --token-expiry file (forsgren#177, forsgren#194): collect writes it,
// check-needs and run-summary read it, all through tokenExpiry. It holds one
// line: the token's expiry date in UTC RFC 3339, "2027-01-12T08:35:47Z", or a
// word for a token with no date to count from. No file, or one that cannot be
// read or holds anything else, is a token collect could not ask about.

import (
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/github"
)

// The words the file holds besides a date (forsgren#194): the token answered
// GitHub and has no expiry date, and, when it is the job's own token
// (GITHUB_TOKEN, route A), that it is renewed every run; or GitHub sent an
// expiry header that is no date forsgren can read, which the file does not
// repeat (the note on stderr shows it).
const (
	expiryNone       = "no-expiry"
	expiryNoneRunOwn = "no-expiry run-token"
	expiryUnreadable = "unreadable"
)

// tokenExpiry is what the file says of the token: its date when dated, else
// one of the words, or none when collect could not ask.
type tokenExpiry struct {
	dated bool
	date  time.Time
	word  string
}

// line is the file's line for e.
func (e tokenExpiry) line() string {
	if e.dated {
		return e.date.UTC().Format(time.RFC3339)
	}
	return e.word
}

// expiryOf is what the line says, the reverse of line: a date, a word, or
// nothing known for any other line.
func expiryOf(line string) tokenExpiry {
	if date, err := time.Parse(time.RFC3339, line); err == nil {
		return tokenExpiry{dated: true, date: date}
	}
	switch line {
	case expiryNone, expiryNoneRunOwn, expiryUnreadable:
		return tokenExpiry{word: line}
	}
	return tokenExpiry{}
}

// tokenExpiryOf is what client's token has to leave in the file, and whether
// it has anything: its expiry date, else, once GitHub answered it, the word
// for a header that is no date, for the run's own token or for none. A token
// that never got an answer leaves nothing. Of the token itself nothing is
// read but whether it is a run token.
func tokenExpiryOf(client *github.Client) (tokenExpiry, bool) {
	if at, known := client.TokenExpiry(); known {
		return tokenExpiry{dated: true, date: at}, true
	}
	word := expiryNone
	if _, unreadable := client.UnreadableTokenExpiry(); unreadable {
		word = expiryUnreadable
	} else if client.IsRunToken() {
		word = expiryNoneRunOwn
	}
	return tokenExpiry{word: word}, client.Answered()
}

// readExpiryFile is what the file at path says; nothing known for no path or
// a file that cannot be read.
func readExpiryFile(path string) tokenExpiry { return expiryOf(fileLine(path)) }

// readTokenExpiry is the expiry date in the file at path, and false when it
// holds none: no path, no file, a word or anything else. The expiry is then
// unknown.
func readTokenExpiry(path string) (time.Time, bool) {
	e := readExpiryFile(path)
	return e.date, e.dated
}

// fileLine is the one line of the small file at path, trimmed, "" for no path
// and when it cannot be read.
func fileLine(path string) string {
	if path == "" {
		return ""
	}
	raw, err := os.ReadFile(filepath.Clean(path))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(raw))
}
