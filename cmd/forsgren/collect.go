package main

import (
	"context"
	"errors"
	"io"
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
	opts, ok := collectFlags(stderr, args)
	if !ok {
		return 2
	}
	cfg, err := config.Load(opts.config)
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
	o := collect.Options{Client: client, History: opts.data, Now: now(), Stdout: stdout, Stderr: stderr}
	if err := collectAndNoteExpiry(cfg, o, opts.tokenExpiry, client); err != nil {
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
	noteUnreadableExpiry(o.Stderr, client)
	return runErr
}

// collectOptions are collect's flags: the required config and history
// (data), and the file to write the token's expiry date to, "" for none.
type collectOptions struct {
	config, data, tokenExpiry string
}

// collectFlags parses collect's arguments: the required --config and --data
// and the optional --token-expiry. It returns false once the usage error is
// on stderr.
func collectFlags(stderr io.Writer, args []string) (collectOptions, bool) {
	flags := newFlags("collect", stderr)
	var o collectOptions
	flags.StringVar(&o.config, "config", "", "the forsgren.config.yml that lists the repositories, <path>")
	flags.StringVar(&o.data, "data", "",
		"the history to append to, data/deployments.csv; commits.csv, failures.csv beside it, <path>")
	flags.StringVar(&o.tokenExpiry, "token-expiry", "",
		"a file to write the token's expiry date to, one UTC RFC 3339 line; removed when the token has none (optional)")
	if err := flags.Parse(args); err != nil {
		return o, false
	}
	return o, !missingRequired(stderr, "collect",
		requiredValue{"config", "<path>", o.config}, requiredValue{"data", "<path>", o.data})
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
