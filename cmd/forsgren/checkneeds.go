package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"

	"go.yaml.in/yaml/v3"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/needs"
)

// checkNeedsOptions are check-needs' flags: the config whose keys count, the
// installation's repository the setup issue lives in, and the optional file
// that records how the write went.
type checkNeedsOptions struct {
	config, repository, status string
	// tokenExpiry is the file collect wrote the token's expiry date to, "" for none.
	tokenExpiry string
	// pullsDenied is the file collect noted the refused pull request reads in.
	pullsDenied string
	// pushesDenied is the file collect noted the refused push reads in.
	pushesDenied string
}

// checkNeeds checks the needs of the running version against the
// installation's checkout (the working directory) and its config, writes the
// setup issue through setupReport with the job's token, and records the
// outcome (writeOutcome) in --status (forsgren#73). It prints each missing
// need's steps and the status on stdout. It exits 0 once its flags are valid,
// whatever the check or the write did (a note on stderr, a status that is not
// ok), and 2 on a usage error.
func checkNeeds(args []string, stdout, stderr io.Writer) int {
	o, ok := checkNeedsFlags(args, stderr)
	if !ok {
		return 2
	}
	status := statusSkipped
	if isDevelopment() {
		noteDevelopment(stderr)
	} else {
		status = reportNeeds(o, stdout, stderr)
	}
	_, _ = fmt.Fprintf(stdout, "check-needs: %s\n", status)
	writeStatus(o.status, status, stderr)
	return 0
}

// noteDevelopment says on stderr why a development build checks nothing: it
// does not know what it needs, an unknown version being no older release, so
// the setup issue is neither written nor closed (forsgren#340).
func noteDevelopment(stderr io.Writer) {
	_, _ = fmt.Fprintln(stderr, "check-needs: a development build does not know what it needs; "+
		"the setup issue is neither written nor closed (forsgren#340)")
}

// checkNeedsFlags parses check-needs' arguments: the required --config and
// --repository, and the optional --status path. It returns false once the
// usage error is on stderr.
func checkNeedsFlags(args []string, stderr io.Writer) (checkNeedsOptions, bool) {
	flags := newFlags("check-needs", stderr)
	var o checkNeedsOptions
	flags.StringVar(&o.config, "config", "", "the forsgren.config.yml whose keys the config needs ask for, <path>")
	flags.StringVar(&o.repository, "repository", "", "the installation's repository, <owner/name>")
	flags.StringVar(&o.status, "status", "",
		"a file to write how the setup issue went to: ok, no-access, rate-limited or failed (optional)")
	flags.StringVar(&o.tokenExpiry, "token-expiry", "",
		"the file collect --token-expiry wrote the token's expiry date to; a date near makes a setup issue item (optional)")
	flags.StringVar(&o.pullsDenied, "pulls-denied", defaultPullsDenied,
		"the file collect noted the refused pull request reads in; each makes a setup issue item (optional)")
	flags.StringVar(&o.pushesDenied, "pushes-denied", defaultPushesDenied,
		"the file collect noted the refused push reads in; each makes a setup issue item (optional)")
	if err := flags.Parse(args); err != nil {
		return o, false
	}
	return o, !missingRequired(stderr, "check-needs",
		requiredValue{"config", "<path>", o.config}, requiredValue{"repository", "<owner/name>", o.repository})
}

// reportNeeds finds the needs missing from the checkout, with the token's
// renewal item when the expiry date collect wrote is near (renewalNeed),
// prints their steps, writes the setup issue and returns how that went:
// failed, with a note on stderr, when the running version's needs cannot be
// read, a file of refused reads cannot be read (the setup issue is then left
// as it is, forsgren#395) or the client cannot be made.
func reportNeeds(o checkNeedsOptions, stdout, stderr io.Writer) string {
	missing, known, err := gatherNeeds(o, stderr)
	if err != nil {
		return noteFailed(stderr, err)
	}
	for _, n := range missing {
		_, _ = fmt.Fprintln(stdout, n.Steps)
	}
	client, err := jobClient(github.DefaultMaxPages)
	if err != nil {
		return noteFailed(stderr, err)
	}
	return writeSetup(setupReport{issues: client, repo: o.repository, version: runningVersion()}, missing, known, stderr)
}

// gatherNeeds are the needs missing from the checkout, the token's renewal
// item when its expiry date is near and an item for each refused read, with
// whether the token's expiry date is known. The error is that of the needs
// of the running version, or of a file of refused reads that cannot be read
// (forsgren#395): none of them may be taken for no needs.
func gatherNeeds(o checkNeedsOptions, stderr io.Writer) ([]needs.Need, bool, error) {
	missing, err := missingNeeds("check-needs", o.config, stderr)
	if err != nil {
		return nil, false, err
	}
	expiry, known := readTokenExpiry(o.tokenExpiry)
	if n, near := renewalNeed(expiry, now()); known && near {
		missing = append(missing, n)
	}
	refused, err := refusedNeeds(o.pullsDenied, o.pushesDenied)
	return append(missing, refused...), known, err
}

// writeSetup writes the setup issue for the missing needs, looking it up
// once, with the renewal item the open issue already carries when the
// token's expiry is not known (withKeptToken), and returns how that went (writeOutcome).
func writeSetup(s setupReport, missing []needs.Need, expiryKnown bool, stderr io.Writer) string {
	ctx := context.Background()
	found, err := s.find(ctx)
	if err == nil {
		if !expiryKnown {
			missing = withKeptToken(found, missing, now())
		}
		err = s.report(ctx, found, missing)
	}
	return writeOutcome(len(missing), err, stderr)
}

// writeOutcome is the status of the setup issue's write and, when it failed,
// the note on stderr saying which write it was. With something missing the
// status is setupStatus of the error. With nothing missing it is ok whatever
// the close did: the summary and the footer speak only when something is
// missing, so a failed close is never a missing need (forsgren#73).
func writeOutcome(missing int, err error, stderr io.Writer) string {
	if err == nil {
		return statusOK
	}
	if missing == 0 {
		_, _ = fmt.Fprintf(stderr, "check-needs: the setup issue could not be closed: %v\n", err)
		return statusOK
	}
	_, _ = fmt.Fprintf(stderr, "check-needs: the setup issue could not be written: %v\n", err)
	return setupStatus(err)
}

// missingNeeds are the needs of the running version that are not in place in
// the checkout (the working directory), given the config file at config:
// what check-needs writes the setup issue about and run-summary lists. Its
// notes on stderr start with name, the running command. The error is For's:
// a version or a declaration that cannot be read.
func missingNeeds(name, config string, stderr io.Writer) ([]needs.Need, error) {
	all, err := needs.For(runningVersion())
	if err != nil {
		return nil, err
	}
	at := needs.Installation{Root: ".", ConfigKeys: configKeys(name, config, stderr), Getenv: os.Getenv}
	return needs.Missing(all, at), nil
}

// noteFailed says on stderr why the check could not run and returns the
// status failed.
func noteFailed(stderr io.Writer, err error) string {
	_, _ = fmt.Fprintf(stderr, "check-needs: the needs could not be checked: %v\n", err)
	return statusFailed
}

// configKeys are the top-level keys of the config file at path, sorted. A
// file that cannot be read or parsed has none, with a note on stderr: the
// needs for config keys then count as missing. The note starts with name,
// the running command.
func configKeys(name, path string, stderr io.Writer) []string {
	var doc map[string]any
	raw, err := os.ReadFile(filepath.Clean(path))
	if err == nil {
		err = yaml.Unmarshal(raw, &doc)
	}
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "%s: the config keys are unknown: %v\n", name, err)
		return nil
	}
	keys := make([]string, 0, len(doc))
	for key := range doc {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}
