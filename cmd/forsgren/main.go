// Command forsgren is the composition root: it reads the command line and
// hands the work to the internal packages.
//
// Usage:
//
//	forsgren render --out <dir>
//	forsgren check-config --config <path>
package main

import (
	"flag"
	"fmt"
	"io"
	"os"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/page"
)

const usage = `usage: forsgren render --out <dir>
       forsgren check-config --config <path>`

// version is the forsgren release this binary is, shown on every page it
// renders. It is the one source of the version: a var, not a const, so a
// release build can set it with
// -ldflags "-X main.version=<version>"; the default is the next release.
var version = "0.0.1"

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

// run executes one command and returns the process exit status: 0 on
// success, 1 when the work failed, 2 on a usage error.
func run(args []string, stdout, stderr io.Writer) int {
	if len(args) > 0 {
		switch args[0] {
		case "render":
			return render(args[1:], stdout, stderr)
		case "check-config":
			return checkConfig(args[1:], stdout, stderr)
		}
	}
	_, _ = fmt.Fprintln(stderr, usage)
	return 2
}

// checkConfig loads and validates an installation's forsgren.config.yml and
// says in one line whether it is valid: the cheapest way for an owner, or a
// workflow, to see a config mistake before a run depends on it.
func checkConfig(args []string, stdout, stderr io.Writer) int {
	flags := flag.NewFlagSet("check-config", flag.ContinueOnError)
	flags.SetOutput(stderr)
	path := flags.String("config", "", "the forsgren.config.yml to check")
	if err := flags.Parse(args); err != nil {
		return 2
	}
	if *path == "" {
		_, _ = fmt.Fprintln(stderr, "check-config: --config <path> is required")
		return 2
	}
	cfg, err := config.Load(*path)
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "check-config: %v\n", err)
		return 1
	}
	_, _ = fmt.Fprintf(stdout, "OK: %s is a valid forsgren config (version %d): projects: %d, repositories: %d\n",
		*path, cfg.Version, len(cfg.Projects), cfg.RepositoryCount())
	return 0
}

func render(args []string, stdout, stderr io.Writer) int {
	flags := flag.NewFlagSet("render", flag.ContinueOnError)
	flags.SetOutput(stderr)
	out := flags.String("out", "", "directory to write the site into")
	if err := flags.Parse(args); err != nil {
		return 2
	}
	if *out == "" {
		_, _ = fmt.Fprintln(stderr, "render: --out <dir> is required")
		return 2
	}
	n, err := page.WriteSite(*out, page.Placeholder(version))
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "render: %v\n", err)
		return 1
	}
	_, _ = fmt.Fprintf(stdout, "rendered %d page(s) into %s\n", n, *out)
	return 0
}
