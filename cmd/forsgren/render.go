package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
	"github.com/yveshanoulle/forsgren/internal/metrics"
	"github.com/yveshanoulle/forsgren/internal/page"
)

// dataWithoutConfig is the usage error of --data alone: the history is
// grouped by the config's projects, so it has nothing to report on without.
const dataWithoutConfig = "render: --data <path> needs --config <path>, which lists the projects"

// renderOptions are render's flags: the required --out, the optional
// --config and --data (empty when absent).
type renderOptions struct {
	out, config, data string
}

// render writes the site. With --config it also reads the installation's
// forsgren.config.yml, so the page can say when no projects are configured
// yet (forsgren#12); with --data as well it reads the history and shows each
// project's deployment frequency, counted back from now. Without --config
// (the repository's own build has no installation config) the page is the
// placeholder, unchanged.
func render(args []string, stdout, stderr io.Writer) int {
	o, ok := renderFlags(args, stderr)
	if !ok {
		return 2
	}
	data, err := pageData(o, now())
	if err != nil {
		return failed(stderr, "render", err)
	}
	n, err := page.WriteSite(o.out, data)
	if err != nil {
		return failed(stderr, "render", err)
	}
	_, _ = fmt.Fprintf(stdout, "rendered %d page(s) into %s\n", n, o.out)
	return 0
}

// pageData is what the page shows for the options at the render time at.
func pageData(o renderOptions, at time.Time) (page.Data, error) {
	data := page.Placeholder(version)
	if o.config == "" {
		return data, nil
	}
	cfg, err := config.Load(o.config)
	if err != nil {
		return data, err
	}
	data.NoProjects = len(cfg.Projects) == 0
	if o.data == "" {
		return data, nil
	}
	records, err := loadHistory(o.data)
	if err != nil {
		return data, err
	}
	data.Frequencies = metrics.DeploymentFrequency(cfg.Projects, records, at)
	data.AsOf = at.UTC().Format(time.DateOnly)
	return data, nil
}

// loadHistory reads the history at path. A missing file is an empty
// history: a new installation renders before its first collect has stored
// anything. Any other refusal (an unknown version, a malformed line) is
// history's own error.
func loadHistory(path string) ([]history.Record, error) {
	records, err := history.Load(path)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	return records, err
}

// renderFlags parses render's arguments. It returns false once the usage
// error is on stderr.
func renderFlags(args []string, stderr io.Writer) (renderOptions, bool) {
	flags := flag.NewFlagSet("render", flag.ContinueOnError)
	flags.SetOutput(stderr)
	var o renderOptions
	flags.StringVar(&o.out, "out", "", "directory to write the site into")
	flags.StringVar(&o.config, "config", "", "the forsgren.config.yml the page reports on (optional)")
	flags.StringVar(&o.data, "data", "", "the history the page counts, data/deployments.csv (optional, needs --config)")
	if err := flags.Parse(args); err != nil {
		return o, false
	}
	switch {
	case o.out == "":
		_, _ = fmt.Fprintln(stderr, "render: --out <dir> is required")
		return o, false
	case o.data != "" && o.config == "":
		_, _ = fmt.Fprintln(stderr, dataWithoutConfig)
		return o, false
	}
	return o, true
}
