package config

// The labels of config v1 (forsgren#38): the names of a project's sub-rows
// on the page. Only a name the owner writes here reaches the page, never a
// repository's or a task's own name.
//
//	repositories:
//	  - name: acme/app
//	    services:            # task: label, a row per listed task
//	      deploy-api: API
//	  - name: acme/web
//	    label: Website       # one row for all its deployments
//
// A repository with neither has no row of its own and counts in its
// project's total only, as every repository did before.

import (
	"errors"
	"fmt"
	"maps"
	"slices"
	"strings"

	"go.yaml.in/yaml/v3"
)

// text is a label or a task as the file writes it: YAML text and nothing
// else. The YAML library would read `label: 5` or `label: true` into a Go
// string as "5" or "true", so a typed value is refused here instead, worded
// like the library's other refusals. The library never hands a null value
// to it: a null label is no label, a null task's label is empty text.
type text string

// UnmarshalYAML takes a string and refuses any other kind.
func (t *text) UnmarshalYAML(n *yaml.Node) error {
	if n.Kind != yaml.ScalarNode || n.ShortTag() != "!!str" {
		return &yaml.TypeError{Errors: []string{
			fmt.Sprintf("line %d: cannot use %s here: labels and tasks are text", n.Line, kindOf(n)),
		}}
	}
	*t = text(n.Value)
	return nil
}

// kindOf is a node's YAML tag, and its value when it is a scalar.
func kindOf(n *yaml.Node) string {
	if n.Kind == yaml.ScalarNode {
		return n.ShortTag() + " `" + n.Value + "`"
	}
	return n.ShortTag()
}

var (
	errLabelEmpty    = errors.New("a label is empty")
	errTaskEmpty     = errors.New("a task is empty")
	errLabelAndTasks = errors.New("use label or services, not both")
	errNoTasks       = errors.New("services lists no task; write task: label lines, or leave services out")
	errReleaseTasks  = errors.New("a release's task is its tag, new with each release; use label")
)

// labels reads the repository's label or the labels of its services, for a
// repository deployed as kind.
func (r fileRepository) labels(kind DeploymentKind) (string, map[string]string, error) {
	switch {
	case r.Label != nil && r.Services != nil:
		return "", nil, errLabelAndTasks
	case r.Label != nil:
		return string(*r.Label), nil, checkLabel(*r.Label)
	case r.Services != nil:
		services, err := servicesOf(r.Services, kind)
		return "", services, err
	}
	return "", nil, nil
}

// servicesOf checks each task and its label.
func servicesOf(services map[text]text, kind DeploymentKind) (map[string]string, error) {
	if kind == Release {
		return nil, errReleaseTasks
	}
	if len(services) == 0 {
		return nil, errNoTasks
	}
	out := map[string]string{}
	for task, label := range services {
		if isBlank(task) {
			return nil, errTaskEmpty
		}
		if err := checkLabel(label); err != nil {
			return nil, err
		}
		out[string(task)] = string(label)
	}
	return out, nil
}

// checkLabel refuses an empty label, or one of blanks only.
func checkLabel(label text) error {
	if isBlank(label) {
		return errLabelEmpty
	}
	return nil
}

func isBlank(t text) bool { return strings.TrimSpace(string(t)) == "" }

// LabelCount is the number of labelled rows over all projects: a
// repository's label, and each of its services.
func (c Config) LabelCount() int {
	n := 0
	for _, p := range c.Projects {
		for _, r := range p.Repositories {
			n += len(r.Labels())
		}
	}
	return n
}

// Labels are the labels the repository gives its project's rows, sorted:
// its own, or those of its services.
func (r Repository) Labels() []string {
	if r.Label != "" {
		return []string{r.Label}
	}
	return slices.Sorted(maps.Values(r.Services))
}

// claimLabels records the repository's labels in the project's, compared
// ignoring case (two rows "API" and "api" would read as one), or refuses
// one the project already has.
func claimLabels(project map[string]bool, r Repository) error {
	for _, label := range r.Labels() {
		key := strings.ToLower(label)
		if project[key] {
			return fmt.Errorf("%w: %q is used twice in the project (case is ignored)", ErrLabel, label)
		}
		project[key] = true
	}
	return nil
}
