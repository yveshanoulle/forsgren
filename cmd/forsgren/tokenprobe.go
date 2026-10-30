package main

// forsgren token-probe (forsgren#276): the line of the token-expiry-probe
// artifact metrics.yml uploads, for an installation that checks its tokens
// centrally. One line, FORSGREN_TOKEN, a tab and the token's expiry date
// (YYYY-MM-DD, UTC), never for a token without one, or error: <word> when
// the date is unknown. It reads only the --token-expiry file collect wrote
// (expiryfile.go) and whether the collect step had the secret; the token
// itself never reaches it.

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"
)

// probedSecret is the secret the line is about, the one metrics.yml takes.
const probedSecret = "FORSGREN_TOKEN"

// The --token-state values: whether the collect step had a token.
const (
	tokenStateSet     = "set"
	tokenStateMissing = "missing"
)

// tokenProbe writes the probe line to --out and says it on stdout: exit 0
// whatever the line says, error lines included, 1 when the file cannot be
// written, 2 on a usage error (an unknown --token-state among them).
func tokenProbe(args []string, stdout, stderr io.Writer) int {
	values, ok := requiredFlags(stderr, args, "token-probe",
		flagSpec{"token-expiry", "<path>", "the file collect --token-expiry wrote"},
		flagSpec{"token-state", "<set|missing>", "whether the collect step had FORSGREN_TOKEN"},
		flagSpec{"out", "<path>", "the token-probed.tsv to write"})
	if !ok {
		return 2
	}
	state := values[1]
	if state != tokenStateSet && state != tokenStateMissing {
		_, _ = fmt.Fprintf(stderr, "token-probe: --token-state %q: use %s or %s\n", state, tokenStateSet, tokenStateMissing)
		return 2
	}
	value := probedValue(readExpiryFile(values[0]), state == tokenStateSet)
	out := values[2]
	if err := os.WriteFile(filepath.Clean(out), []byte(probedSecret+"\t"+value+"\n"), 0o600); err != nil {
		return failed(stderr, "token-probe", err)
	}
	_, _ = fmt.Fprintf(stdout, "wrote %s: %s %s\n", out, probedSecret, value)
	return 0
}

// probedValue is what the line says of a token whose file says e: its date,
// never for none, or error: <word> when the date is unknown: unreadable
// (GitHub's header was no date), unknown (the secret was set but collect left
// no answer, as with no project configured) or missing (no secret).
// A run token renews every run, so it has no date to renew by either.
func probedValue(e tokenExpiry, tokenSet bool) string {
	switch {
	case e.dated:
		return e.date.UTC().Format(time.DateOnly)
	case e.word == expiryNone, e.word == expiryNoneRunOwn:
		return "never"
	case e.word == expiryUnreadable:
		return "error: unreadable"
	case tokenSet:
		return "error: unknown"
	}
	return "error: missing"
}
