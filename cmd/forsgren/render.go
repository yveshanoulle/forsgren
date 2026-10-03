package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"path/filepath"
	"time"

	"github.com/yveshanoulle/forsgren/internal/collect"
	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
	"github.com/yveshanoulle/forsgren/internal/metrics"
	"github.com/yveshanoulle/forsgren/internal/page"
)

// dataWithoutConfig is the usage error of --data alone: the history is
// grouped by the config's projects, so it has nothing to report on without.
const dataWithoutConfig = "render: --data <path> needs --config <path>, which lists the projects"

// calculatedLayout is how the page shows the render time: UTC, to the minute
// (forsgren#28). Format cuts the seconds off, so the minute shown never lies
// ahead of the moment the numbers were counted back from.
const calculatedLayout = "2006-01-02 15:04"

// renderOptions are render's flags: the required --out, the optional
// --config and --data (empty when absent).
type renderOptions struct {
	out, config, data string
}

// render writes the site. With --config it also reads the installation's
// forsgren.config.yml, so the page can say when no projects are configured
// yet (forsgren#12); with --data as well it reads the history and the
// commits file next to it, and shows each project's deployment frequency
// and lead time for changes, counted back from now. Without --config
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
	data.Projects, err = projectsOf(cfg.Projects, o.data, at)
	if err != nil {
		return data, err
	}
	data.AsOf = at.UTC().Format(calculatedLayout)
	return data, nil
}

// projectsOf is each project's section, from the history at path and the
// commits file next to it (data/commits.csv beside data/deployments.csv,
// forsgren#16), at the render time at.
func projectsOf(projects []config.Project, path string, at time.Time) ([]page.Project, error) {
	records, err := loadOrNone(path, history.Load)
	if err != nil {
		return nil, err
	}
	commits, err := loadOrNone(filepath.Join(filepath.Dir(path), collect.CommitsFile), history.LoadCommits)
	if err != nil {
		return nil, err
	}
	frequencies := metrics.DeploymentFrequency(projects, records, at)
	leadTimes := metrics.LeadTimes(projects, commits, at)
	out := make([]page.Project, len(projects))
	for i := range out {
		out[i] = page.Project{Frequency: frequencies[i], LeadTime: leadTimes[i]}
	}
	return out, nil
}

// loadOrNone reads the file at path with load. A missing file holds
// nothing: a new installation renders before its first collect has stored
// anything. Any other refusal (an unknown version, a malformed line) is
// load's own error, which names the file.
func loadOrNone[T any](path string, load func(string) ([]T, error)) ([]T, error) {
	lines, err := load(path)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	return lines, err
}

// renderFlags parses render's arguments. It returns false once the usage
// error is on stderr.
func renderFlags(args []string, stderr io.Writer) (renderOptions, bool) {
	flags := flag.NewFlagSet("render", flag.ContinueOnError)
	flags.SetOutput(stderr)
	var o renderOptions
	flags.StringVar(&o.out, "out", "", "directory to write the site into")
	flags.StringVar(&o.config, "config", "", "the forsgren.config.yml the page reports on (optional)")
	flags.StringVar(&o.data, "data", "",
		"the history the page counts, data/deployments.csv, commits.csv beside it (optional, needs --config)")
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
