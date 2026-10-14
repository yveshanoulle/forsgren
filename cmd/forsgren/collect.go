package main

import (
	"cmp"
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/collect"
	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/github"
)

// githubAPI is the GitHub REST API collect and the lookups (latest-release,
// waiting-pull-request) read, and now the clock of collect and render: vars
// so the tests can point them at a test server and a fixed day.
var (
	githubAPI = "https://api.github.com"
	now       = time.Now
)

var errNoToken = errors.New("FORSGREN_TOKEN is not set: " +
	"collect needs a read-only GitHub token for the configured repositories")

// collectDeployments reads each configured repository's deployments from
// GitHub and appends the final ones to the history, the commits of the new
// successes to commits.csv next to it, and the new or changed failure issues
// to failures.csv next to it: one line per repository
// on stdout, exit 0; exit 1 when the config, the token, the history or any
// repository failed (after every repository was tried), 2 on a usage error.
// With no repository configured it does nothing, and needs no token.
func collectDeployments(args []string, stdout, stderr io.Writer) int {
	paths, ok := collectFlags(stderr, args)
	if !ok {
		return 2
	}
	cfg, err := config.Load(paths[0])
	if err != nil {
		return failed(stderr, "collect", err)
	}
	if cfg.RepositoryCount() == 0 {
		return 0
	}
	client, err := githubClient()
	if err != nil {
		return failed(stderr, "collect", err)
	}
	o := collect.Options{Client: client, History: paths[1], Now: now(), Stdout: stdout, Stderr: stderr}
	if err := collectAndNoteExpiry(cfg, o, paths[2], client); err != nil {
		return failed(stderr, "collect", err)
	}
	return 0
}

// collectAndNoteExpiry runs collect, then writes the token's expiry to
// expiryPath (writeTokenExpiry), whether or not a repository failed; a write
// that failed is the error, else collect's own.
func collectAndNoteExpiry(cfg config.Config, o collect.Options, expiryPath string, client *github.Client) error {
	runErr := collect.Run(context.Background(), cfg, o)
	if err := writeTokenExpiry(expiryPath, client); err != nil {
		return err
	}
	warnTokenExpiry(o.Stderr, o.Now, client)
	return runErr
}

// collectFlags parses collect's arguments: the required --config and --data,
// in that order, and the optional --token-expiry, "" when not given. It
// returns false once the usage error is on stderr.
func collectFlags(stderr io.Writer, args []string) ([3]string, bool) {
	flags := newFlags("collect", stderr)
	var p [3]string
	flags.StringVar(&p[0], "config", "", "the forsgren.config.yml that lists the repositories, <path>")
	flags.StringVar(&p[1], "data", "",
		"the history to append to, data/deployments.csv; commits.csv, failures.csv beside it, <path>")
	flags.StringVar(&p[2], "token-expiry", "",
		"a file to write the token's expiry date to, one UTC RFC 3339 line; removed when the token has none (optional)")
	if err := flags.Parse(args); err != nil {
		return p, false
	}
	for i, m := range []struct{ name, arg string }{{"config", "<path>"}, {"data", "<path>"}} {
		if p[i] == "" {
			_, _ = fmt.Fprintf(stderr, "collect: --%s %s is required\n", m.name, m.arg)
			return p, false
		}
	}
	return p, true
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

// githubClient is a client of githubAPI with the installation's token, from
// the environment only: never a flag, which would show in a process list.
func githubClient() (*github.Client, error) {
	token := strings.TrimSpace(os.Getenv("FORSGREN_TOKEN"))
	if token == "" {
		return nil, errNoToken
	}
	return github.New(githubAPI, token, github.DefaultMaxPages)
}

// jobClient is a client of githubAPI with the workflow job's token,
// GITHUB_TOKEN from the environment, reading up to maxPages pages; a refusal
// names GITHUB_TOKEN. No token is allowed: the client then sends no
// Authorization header.
func jobClient(maxPages int) (*github.Client, error) {
	client, err := github.New(githubAPI, strings.TrimSpace(os.Getenv("GITHUB_TOKEN")), maxPages)
	if err != nil {
		return nil, err
	}
	return client.WithTokenName("GITHUB_TOKEN"), nil
}

// expiryWarningDays is how many days before its expiry date the token starts
// to be warned about (forsgren#177).
const expiryWarningDays = 14

// warnTokenExpiry says on stderr that the token expires on its date, and how
// to make a new one, when the date is at most expiryWarningDays after now
// or already past; nothing for a date further away or none known. The run's
// outcome is not touched.
func warnTokenExpiry(stderr io.Writer, at time.Time, client *github.Client) {
	expiry, known := client.TokenExpiry()
	if !known || expiry.After(at.AddDate(0, 0, expiryWarningDays)) {
		return
	}
	when := "expires on " + expiry.UTC().Format(time.DateOnly)
	if expiry.Before(at) {
		when = "has expired on " + expiry.UTC().Format(time.DateOnly)
	}
	repo := cmp.Or(os.Getenv("GITHUB_REPOSITORY"), "this installation's repository")
	_, _ = fmt.Fprintf(stderr, "collect: warning: FORSGREN_TOKEN %s. Make a new fine-grained token and set it "+
		"with `gh secret set FORSGREN_TOKEN -R %s` in a separate terminal.\n", when, repo)
}
