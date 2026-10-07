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
}

// checkNeeds checks the needs of the running version against the
// installation's checkout (the working directory) and its config, writes the
// setup issue through reportSetup with the job's token, and records
// setupStatus in --status (forsgren#73, step 15). It prints each missing
// need's steps and the status on stdout. It exits 0 once its flags are valid,
// whatever the check or the write did (a note on stderr, a status that is not
// ok), and 2 on a usage error.
func checkNeeds(args []string, stdout, stderr io.Writer) int {
	o, ok := checkNeedsFlags(args, stderr)
	if !ok {
		return 2
	}
	status := reportNeeds(o, stdout, stderr)
	_, _ = fmt.Fprintf(stdout, "check-needs: %s\n", status)
	writeStatus(o.status, status, stderr)
	return 0
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
	if err := flags.Parse(args); err != nil {
		return o, false
	}
	for _, missing := range []struct{ name, arg, value string }{
		{"config", "<path>", o.config}, {"repository", "<owner/name>", o.repository},
	} {
		if missing.value == "" {
			_, _ = fmt.Fprintf(stderr, "check-needs: --%s %s is required\n", missing.name, missing.arg)
			return o, false
		}
	}
	return o, true
}

// reportNeeds finds the needs missing from the checkout, prints their steps,
// writes the setup issue and returns how that went: failed, with a note on
// stderr, when the running version has no needs or the client cannot be made.
func reportNeeds(o checkNeedsOptions, stdout, stderr io.Writer) string {
	all, err := needs.For(version)
	if err != nil {
		return noteFailed(stderr, err)
	}
	at := needs.Installation{Root: ".", ConfigKeys: configKeys(o.config, stderr), Getenv: os.Getenv}
	missing := needs.Missing(all, at)
	for _, n := range missing {
		_, _ = fmt.Fprintln(stdout, n.Steps)
	}
	client, err := jobClient(github.DefaultMaxPages)
	if err != nil {
		return noteFailed(stderr, err)
	}
	err = reportSetup(context.Background(), client, o.repository, version, missing)
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "check-needs: the setup issue could not be written: %v\n", err)
	}
	return setupStatus(err)
}

// noteFailed says on stderr why the check could not run and returns the
// status failed.
func noteFailed(stderr io.Writer, err error) string {
	_, _ = fmt.Fprintf(stderr, "check-needs: the needs could not be checked: %v\n", err)
	return statusFailed
}

// configKeys are the top-level keys of the config file at path, sorted. A
// file that cannot be read or parsed has none, with a note on stderr: the
// needs for config keys then count as missing.
func configKeys(path string, stderr io.Writer) []string {
	var doc map[string]any
	raw, err := os.ReadFile(filepath.Clean(path))
	if err == nil {
		err = yaml.Unmarshal(raw, &doc)
	}
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "check-needs: the config keys are unknown: %v\n", err)
		return nil
	}
	keys := make([]string, 0, len(doc))
	for key := range doc {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}
