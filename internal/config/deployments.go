package config

// Several deployment rules for one repository (forsgren#498, decision #499
// A): a `deployments:` map of rule to label, or to {label, paths} (the form
// of forsgren#496), each entry its own row.
//
//	repositories:
//	  - name: acme/site
//	    deployments:
//	      release: Releases
//	      environment=github-pages:
//	        label: Website
//	        paths: [website/, shared/]
//
// A rule is written as `deployment:` writes it. `deployments:` replaces
// `deployment:`, `label:` and `services:` on the repository: it is refused
// beside any of them, and a rule takes no `services` of its own, since the
// rule already is the split.

import (
	"errors"
	"fmt"
	"strings"

	"go.yaml.in/yaml/v3"
)

var (
	errBothDeployments = errors.New("use deployment or deployments, not both")
	errRulesAndLabels  = errors.New("deployments cannot be used with label or services")
	errNoRules         = errors.New("deployments lists no rule; write rule: label lines, or leave deployments out")
	errRuleEmpty       = errors.New("a deployment rule is empty")
)

const rulesShape = "line %d: deployments is a map of deployment rule to label"

// ruleEntry is one rule of `deployments:` as the file writes it.
type ruleEntry struct {
	rule text
	svc  service
}

// ruleList is the entries of `deployments:` in file order.
type ruleList []ruleEntry

// UnmarshalYAML takes a mapping of rule to label or {label, paths}, keeping
// the order of the file and refusing a rule listed twice.
func (l *ruleList) UnmarshalYAML(n *yaml.Node) error {
	if n.Kind != yaml.MappingNode {
		return typeError(rulesShape, n.Line)
	}
	*l = ruleList{}
	seen := map[string]bool{}
	for i := 0; i+1 < len(n.Content); i += 2 {
		var e ruleEntry
		if err := e.rule.UnmarshalYAML(n.Content[i]); err != nil {
			return err
		}
		if seen[string(e.rule)] {
			return typeError("line %d: deployment rule %q is listed twice", n.Content[i].Line, string(e.rule))
		}
		seen[string(e.rule)] = true
		if err := e.svc.UnmarshalYAML(n.Content[i+1]); err != nil {
			return err
		}
		*l = append(*l, e)
	}
	return nil
}

// toRuledRepository is the repository whose file entry has `deployments:`.
func (r fileRepository) toRuledRepository(where string) (Repository, error) {
	if r.Deployment != "" {
		return Repository{}, fmt.Errorf("%s: %w: %w", where, ErrDeployment, errBothDeployments)
	}
	if r.Label != nil || r.Services != nil {
		return Repository{}, fmt.Errorf("%s: %w: %w", where, ErrDeployment, errRulesAndLabels)
	}
	rules, err := r.Deployments.rules(where)
	if err != nil {
		return Repository{}, err
	}
	return Repository{Name: r.Name, Deployment: rules[0].Deployment, Rules: rules}, nil
}

// rules checks each entry, its rule, its label and its paths, and that no
// label is used twice in the repository (ignoring case).
func (l ruleList) rules(where string) ([]Rule, error) {
	if len(l) == 0 {
		return nil, fmt.Errorf("%s: %w: %w", where, ErrDeployment, errNoRules)
	}
	out := make([]Rule, 0, len(l))
	labels := map[string]bool{}
	for _, e := range l {
		rule, err := e.check(labels)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", where, err)
		}
		out = append(out, rule)
	}
	return out, nil
}

// check is the entry's Rule, its label claimed in labels.
func (e ruleEntry) check(labels map[string]bool) (Rule, error) {
	deployment, err := parseRule(string(e.rule))
	if err != nil {
		return Rule{}, fmt.Errorf("%w %q: %w", ErrDeployment, string(e.rule), err)
	}
	paths, err := e.svc.check()
	if err != nil {
		return Rule{}, fmt.Errorf("%w: rule %q: %w", ErrLabel, string(e.rule), err)
	}
	key := strings.ToLower(string(e.svc.label))
	if labels[key] {
		return Rule{}, fmt.Errorf("%w: %q is used twice in the repository (case is ignored)", ErrLabel,
			string(e.svc.label))
	}
	labels[key] = true
	return Rule{Deployment: deployment, Label: string(e.svc.label), Paths: paths}, nil
}

// parseRule is parseDeployment for a rule that must be written: the empty
// rule is no default here.
func parseRule(s string) (Deployment, error) {
	if strings.TrimSpace(s) == "" {
		return Deployment{}, errRuleEmpty
	}
	return parseDeployment(s)
}

// oneRule is the rule list of a repository written with `deployment:`: the
// one rule, without a label or paths.
func oneRule(d Deployment) []Rule { return []Rule{{Deployment: d}} }

// DeploymentRules are the repository's deployment rules: Rules, or the one
// rule of Deployment when it has none.
func (r Repository) DeploymentRules() []Rule {
	if len(r.Rules) > 0 {
		return r.Rules
	}
	return oneRule(r.Deployment)
}

// ruleLabels are the labels of the repository's rules, in rule order.
func (r Repository) ruleLabels() []string {
	var out []string
	for _, rule := range r.Rules {
		if rule.Label != "" {
			out = append(out, rule.Label)
		}
	}
	return out
}
