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
var version = "0.0.2"

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
	path, ok := requiredFlag(stderr, args, "check-config", "config", "<path>", "the forsgren.config.yml to check")
	if !ok {
		return 2
	}
	cfg, err := config.Load(path)
	if err != nil {
		return failed(stderr, "check-config", err)
	}
	_, _ = fmt.Fprintf(stdout, "OK: %s is a valid forsgren config (version %d): projects: %d, repositories: %d\n",
		path, cfg.Version, len(cfg.Projects), cfg.RepositoryCount())
	return 0
}

func render(args []string, stdout, stderr io.Writer) int {
	out, ok := requiredFlag(stderr, args, "render", "out", "<dir>", "directory to write the site into")
	if !ok {
		return 2
	}
	n, err := page.WriteSite(out, page.Placeholder(version))
	if err != nil {
		return failed(stderr, "render", err)
	}
	_, _ = fmt.Fprintf(stdout, "rendered %d page(s) into %s\n", n, out)
	return 0
}

// requiredFlag parses the arguments of a command that takes one required
// flag, --<name> <arg>: its value and true, or false once the usage error is
// on stderr (flag's own message, or `<command>: --<name> <arg> is required`).
func requiredFlag(stderr io.Writer, args []string, command, name, arg, help string) (string, bool) {
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(stderr)
	value := flags.String(name, "", help)
	if err := flags.Parse(args); err != nil {
		return "", false
	}
	if *value == "" {
		_, _ = fmt.Fprintf(stderr, "%s: --%s %s is required\n", command, name, arg)
		return "", false
	}
	return *value, true
}

// failed says why the command's work failed, `<command>: <err>`, on stderr,
// and returns its exit status, 1.
func failed(stderr io.Writer, command string, err error) int {
	_, _ = fmt.Fprintf(stderr, "%s: %v\n", command, err)
	return 1
}
