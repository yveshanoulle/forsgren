// Command forsgren is the composition root: it reads the command line and
// hands the work to the internal packages.
//
// Usage:
//
//	forsgren render --out <dir> [--config <path>] [--data <path>]
//	                [--latest <version>] [--waiting-pr <number>]
//	forsgren check-config --config <path>
//	forsgren init-config --config <path>
//	forsgren collect --config <path> --data <path>
//	forsgren latest-release
//	forsgren waiting-pull-request --version <x.y.z> [--status <path>]
//	forsgren check-needs --config <path> --repository <owner/name> [--status <path>]
//	forsgren run-summary --latest <version> --waiting-pr <number>
//	                     --pr-check <ok|no-access|rate-limited|failed|skipped> --repository <owner/name>
package main

import (
	"flag"
	"fmt"
	"io"
	"os"

	"github.com/yveshanoulle/forsgren/internal/config"
)

const usage = `usage: forsgren render --out <dir> [--config <path>] [--data <path>]
                       [--latest <version>] [--waiting-pr <number>]
       forsgren check-config --config <path>
       forsgren init-config --config <path>
       forsgren collect --config <path> --data <path>
       forsgren latest-release
       forsgren waiting-pull-request --version <x.y.z> [--status <path>]
       forsgren check-needs --config <path> --repository <owner/name> [--status <path>]
       forsgren run-summary --latest <version> --waiting-pr <number>
                            --pr-check <ok|no-access|rate-limited|failed|skipped> --repository <owner/name>`

// version is the forsgren release this binary is, shown on every page it
// renders. It is the one source of the version: a var, not a const, so a
// release build can set it with
// -ldflags "-X main.version=<version>"; the default is the next release.
var version = "0.4.2"

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

// commands are the subcommands by name.
var commands = map[string]func(args []string, stdout, stderr io.Writer) int{
	"render":               render,
	"check-config":         checkConfig,
	"init-config":          initConfig,
	"collect":              collectDeployments,
	"latest-release":       latestRelease,
	"waiting-pull-request": waitingPullRequest,
	"run-summary":          runSummary,
	"check-needs":          checkNeeds,
	"check-update":         checkUpdate,
	"install-update":       installUpdate,
}

// run executes one command and returns the process exit status: 0 on
// success, 1 when the work failed, 2 on a usage error.
func run(args []string, stdout, stderr io.Writer) int {
	if len(args) > 0 {
		if command, ok := commands[args[0]]; ok {
			return command(args[1:], stdout, stderr)
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
	labels := ""
	if n := cfg.LabelCount(); n > 0 {
		labels = fmt.Sprintf(", labels: %d", n)
	}
	_, _ = fmt.Fprintf(stdout, "OK: %s is a valid forsgren config (version %d): projects: %d, repositories: %d%s\n",
		path, cfg.Version, len(cfg.Projects), cfg.RepositoryCount(), labels)
	return 0
}

// initConfig writes the starter config to a missing forsgren.config.yml and
// leaves an existing file as it is, whatever it holds: `created <path>` or
// `kept <path>`, both exit 0. A real error (a directory in place of the file,
// a directory that is missing or not writable) exits 1.
func initConfig(args []string, stdout, stderr io.Writer) int {
	path, ok := requiredFlag(stderr, args, "init-config", "config", "<path>",
		"the forsgren.config.yml to create when missing")
	if !ok {
		return 2
	}
	created, err := config.Init(path)
	if err != nil {
		return failed(stderr, "init-config", err)
	}
	verb := "kept"
	if created {
		verb = "created"
	}
	_, _ = fmt.Fprintf(stdout, "%s %s\n", verb, path)
	return 0
}

// requiredFlag parses the arguments of a command that takes one required
// flag, --<name> <arg>: its value and true, or false once the usage error is
// on stderr (flag's own message, or `<command>: --<name> <arg> is required`).
func requiredFlag(stderr io.Writer, args []string, command, name, arg, help string) (string, bool) {
	values, ok := requiredFlags(stderr, args, command, flagSpec{name, arg, help})
	if !ok {
		return "", false
	}
	return values[0], true
}

// flagSpec is one required flag, --<name> <arg>, and its help.
type flagSpec struct{ name, arg, help string }

// requiredFlags parses the arguments of a command whose flags are all
// required: their values in the order of specs and true, or false once the
// usage error is on stderr (flag's own message, or the first missing flag's
// `<command>: --<name> <arg> is required`).
func requiredFlags(stderr io.Writer, args []string, command string, specs ...flagSpec) ([]string, bool) {
	flags := newFlags(command, stderr)
	values := make([]*string, len(specs))
	for i, s := range specs {
		values[i] = flags.String(s.name, "", s.help)
	}
	if err := flags.Parse(args); err != nil {
		return nil, false
	}
	parsed := make([]string, len(specs))
	for i, s := range specs {
		if *values[i] == "" {
			_, _ = fmt.Fprintf(stderr, "%s: --%s %s is required\n", command, s.name, s.arg)
			return nil, false
		}
		parsed[i] = *values[i]
	}
	return parsed, true
}

// newFlags is the flag set of a command: a parse error is returned, never an
// exit, and flag's own messages go to stderr.
func newFlags(command string, stderr io.Writer) *flag.FlagSet {
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(stderr)
	return flags
}

// failed says why the command's work failed, `<command>: <err>`, on stderr,
// and returns its exit status, 1.
func failed(stderr io.Writer, command string, err error) int {
	_, _ = fmt.Fprintf(stderr, "%s: %v\n", command, err)
	return 1
}
