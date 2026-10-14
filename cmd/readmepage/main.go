// Command readmepage renders README.md to the one HTML page forsgren.be shows
// (forsgren#132). It is independent of the forsgren command: the starter page
// is the project's own page, not a rendering of an installation's metrics.
//
// Usage:
//
//	readmepage --out <dir> [--readme <path>] [--base <url>]
package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/yveshanoulle/forsgren/internal/page"
	"github.com/yveshanoulle/forsgren/internal/readmepage"
)

// defaultBase is where a relative link of the README points: the file on
// main in forsgren's public repository.
const defaultBase = "https://github.com/yveshanoulle/forsgren/blob/main/"

func main() {
	os.Exit(run(os.Args[1:], os.Stderr))
}

// run renders the README the flags name into <out>/index.html and returns the
// exit code: 0 done, 1 a failure (named on stderr), 2 a usage mistake.
func run(args []string, stderr io.Writer) int {
	flags := flag.NewFlagSet("readmepage", flag.ContinueOnError)
	flags.SetOutput(stderr)
	readme := flags.String("readme", "README.md", "the Markdown file to render")
	base := flags.String("base", defaultBase, "the URL, ending in a slash, a relative link is made absolute against")
	out := flags.String("out", "", "the directory to write index.html into")
	if err := flags.Parse(args); err != nil {
		return 2
	}
	if *out == "" {
		_, _ = fmt.Fprintln(stderr, "readmepage: --out <dir> is required")
		return 2
	}
	if err := write(*readme, *base, *out); err != nil {
		_, _ = fmt.Fprintf(stderr, "readmepage: %v\n", err)
		return 1
	}
	return 0
}

// write renders the Markdown file readme into out/index.html, with the
// site's stylesheet next to it as out/styles.css.
func write(readme, base, out string) error {
	src, err := os.ReadFile(filepath.Clean(readme))
	if err != nil {
		return err
	}
	html, err := readmepage.Render(string(src), base)
	if err != nil {
		return fmt.Errorf("%s: %w", readme, err)
	}
	return publish(out, map[string][]byte{"styles.css": page.Styles(), "index.html": []byte(html)})
}

// publish writes the files, by name, into the directory out, creating it.
func publish(out string, files map[string][]byte) error {
	if err := os.MkdirAll(out, 0o750); err != nil {
		return err
	}
	root, err := os.OpenRoot(out)
	if err != nil {
		return err
	}
	defer func() { _ = root.Close() }()
	for name, data := range files {
		if err := root.WriteFile(name, data, 0o600); err != nil {
			return err
		}
	}
	return nil
}
