// Command forsgren is the composition root: it reads the command line and
// hands the work to the internal packages.
//
// Usage:
//
//	forsgren render --out <dir>
package main

import (
	"flag"
	"fmt"
	"io"
	"os"

	"github.com/yveshanoulle/forsgren/internal/page"
)

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
	if len(args) == 0 || args[0] != "render" {
		_, _ = fmt.Fprintln(stderr, "usage: forsgren render --out <dir>")
		return 2
	}
	return render(args[1:], stdout, stderr)
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
