package config

import (
	"reflect"
	"slices"
	"testing"
)

// Several deployment rules for one repository (forsgren#498, step 1,
// decision #499 A): a `deployments:` map of rule to label, or to
// {label, paths}.

// withDeployments is valid with its repository's deployment line replaced by
// extra.
func withDeployments(extra string) string { return edit(labelRepository, extra) }

const twoRules = "        deployments:\n" +
	"          release: Releases\n" +
	"          environment=github-pages:\n" +
	"            label: forsgren.be\n" +
	"            paths: [website/, shared/]\n"

// TestDeploymentsAreReadInFileOrderWithLabelsAndPaths: each rule keeps its
// kind and name, its label and its paths (none for the short form), in the
// order of the file; the repository's labels are theirs.
func TestDeploymentsAreReadInFileOrderWithLabelsAndPaths(t *testing.T) {
	got, err := parse([]byte(withDeployments(twoRules)))
	if err != nil {
		t.Fatalf("want no error, got %v", err)
	}
	r := got.Projects[0].Repositories[0]
	want := []Rule{
		{Deployment: Deployment{Kind: Release}, Label: "Releases"},
		{Deployment: Deployment{Kind: Environment, Name: "github-pages"}, Label: "forsgren.be",
			Paths: []string{"website/", "shared/"}},
	}
	if !reflect.DeepEqual(r.DeploymentRules(), want) {
		t.Errorf("want rules %+v, got %+v", want, r.DeploymentRules())
	}
	if labels := r.Labels(); !slices.Equal(labels, []string{"Releases", "forsgren.be"}) {
		t.Errorf("want the labels of the rules, got %v", labels)
	}
	if got.LabelCount() != 2 {
		t.Errorf("want 2 labelled rows, got %d", got.LabelCount())
	}
}

// TestTheOneRuleFormIsAListOfOneWithoutALabel: deployment: (or none at all)
// reads as one rule with no label and no paths, so the rest of forsgren reads
// one shape; the old fields stay as they were.
func TestTheOneRuleFormIsAListOfOneWithoutALabel(t *testing.T) {
	for line, want := range map[string]Deployment{
		"        deployment: release\n":          {Kind: Release},
		"        deployment: workflow=a.yml\n":   {Kind: Workflow, Name: "a.yml"},
		"        deployment: environment=live\n": {Kind: Environment, Name: "live"},
		"":                                       {Kind: Environment, Name: DefaultEnvironment},
	} {
		got, err := parse([]byte(withDeployments(line)))
		if err != nil {
			t.Fatalf("%q: want no error, got %v", line, err)
		}
		r := got.Projects[0].Repositories[0]
		if rules := r.DeploymentRules(); !reflect.DeepEqual(rules, []Rule{{Deployment: want}}) || r.Deployment != want {
			t.Errorf("%q: want one rule %+v, got %+v (deployment %+v)", line, want, rules, r.Deployment)
		}
	}
}

// TestADeploymentsKeyWithoutAValueIsTheKeyLeftOut: as a null label is.
func TestADeploymentsKeyWithoutAValueIsTheKeyLeftOut(t *testing.T) {
	got, err := parse([]byte(withDeployments("        deployments:\n")))
	if err != nil {
		t.Fatalf("want no error, got %v", err)
	}
	want := []Rule{{Deployment: Deployment{Kind: Environment, Name: DefaultEnvironment}}}
	if rules := got.Projects[0].Repositories[0].DeploymentRules(); !reflect.DeepEqual(rules, want) {
		t.Errorf("want the default rule, got %+v", rules)
	}
}

// TestADeploymentRuleLabelIsClaimedInTheProject: the label of a rule counts
// with the other labels of its project, ignoring case.
func TestADeploymentRuleLabelIsClaimedInTheProject(t *testing.T) {
	twice := `version: 1
projects:
  - name: Acme
    repositories:
      - name: acme/app
        deployments:
          release: Site
      - name: acme/web
        label: site
`
	checkRefusals(t, []refusal{{"project", twice, ErrLabel, `"site" is used twice in the project`}})
}

// TestParseRefusesWrongDeployments: both keys, a rule with a label or
// services of the repository, an empty map, a label used twice, a bad rule, an
// empty rule, a rule listed twice, a bad value, and the paths of the
// long form checked as a service's are.
func TestParseRefusesWrongDeployments(t *testing.T) {
	const where = `project "Acme": repository "acme/app": `
	rules := func(body string) string { return withDeployments("        deployments:\n" + body) }
	checkRefusals(t, []refusal{
		{"both keys", withDeployments("        deployment: release\n        deployments:\n          release: R\n"),
			ErrDeployment, where + "invalid deployment: use deployment or deployments, not both"},
		{"with label", withDeployments("        label: X\n        deployments:\n          release: R\n"),
			ErrDeployment, where + "invalid deployment: deployments cannot be used with label or services"},
		{"with services", withDeployments("        services:\n          t: T\n        deployments:\n          release: R\n"),
			ErrDeployment, where + "invalid deployment: deployments cannot be used with label or services"},
		{"empty map", withDeployments("        deployments: {}\n"), ErrDeployment,
			where + "invalid deployment: deployments lists no rule"},
		{"label twice", rules("          release: Same\n          environment=live: same\n"), ErrLabel,
			where + `invalid label: "same" is used twice in the repository`},
		{"bad rule", rules("          tag: T\n"), ErrDeployment, `invalid deployment "tag": use environment=`},
		{"empty rule", rules("          \"\": T\n"), ErrDeployment, "a deployment rule is empty"},
		{"rule twice", rules("          release: A\n          release: B\n"), ErrSyntax, "is listed twice"},
		{"empty label", rules("          release: \"\"\n"), ErrLabel, `rule "release": a label is empty`},
		{"no label", rules("          release: {paths: [a/]}\n"), ErrLabel, `rule "release": a label is empty`},
		{"bad paths", rules("          release: {label: R, paths: [/a/]}\n"), ErrLabel,
			`rule "release": path "/a/" is absolute`},
		{"empty paths", rules("          release: {label: R, paths: []}\n"), ErrLabel, errNoPaths.Error()},
		{"services in a rule", rules("          release: {label: R, services: {t: T}}\n"), ErrSyntax,
			`unknown key "services"`},
		{"rule a number", rules("          5: R\n"), ErrSyntax, "cannot use !!int `5` here"},
		{"a list", rules("          release: [R]\n"), ErrSyntax, "a service is a label or {label, paths}"},
		{"not a map", withDeployments("        deployments: release\n"), ErrSyntax, "deployments is a map"},
	})
}

// TestARepositoryHasPathsWhenAServiceOrARuleHasThem: a services path or a
// deployment rule's path counts; a rule or a service without paths does not
// (forsgren#510).
func TestARepositoryHasPathsWhenAServiceOrARuleHasThem(t *testing.T) {
	cases := map[string]struct {
		repo Repository
		want bool
	}{
		"nothing":       {Repository{}, false},
		"service paths": {Repository{Paths: map[string][]string{"deploy": {"api/"}}}, true},
		"rule paths":    {Repository{Rules: []Rule{{Label: "A"}, {Label: "B", Paths: []string{"web/"}}}}, true},
		"rules without": {Repository{Rules: []Rule{{Label: "A"}, {Label: "B"}}}, false},
		"service and a rule": {
			Repository{Paths: map[string][]string{"d": {"a/"}}, Rules: []Rule{{Paths: []string{"b/"}}}}, true,
		},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			if got := c.repo.HasPaths(); got != c.want {
				t.Errorf("want HasPaths %v, got %v", c.want, got)
			}
		})
	}
}
