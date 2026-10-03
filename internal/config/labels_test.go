package config

import (
	"path/filepath"
	"reflect"
	"testing"
)

// labelled is a valid config with every label form (forsgren#38): acme/app
// names three of its tasks, acme/web is one row, acme/cli has no row.
const labelled = `version: 1
projects:
  - name: Acme Shop
    repositories:
      - name: acme/app
        services:
          deploy-api: API
          deploy-admin: ADMIN
          deploy-ios: IOS
      - name: acme/web
        label: Website
      - name: acme/cli
        deployment: release
`

// TestLabelsAreRead (forsgren#38): a repository's label, and the labels of
// its services by task, as written; a repository with neither has none.
func TestLabelsAreRead(t *testing.T) {
	got, err := parse([]byte(labelled))
	if err != nil {
		t.Fatalf("want no error, got %v", err)
	}
	production := Deployment{Kind: Environment, Name: DefaultEnvironment}
	want := []Repository{
		{Name: "acme/app", Deployment: production,
			Services: map[string]string{"deploy-api": "API", "deploy-admin": "ADMIN", "deploy-ios": "IOS"}},
		{Name: "acme/web", Deployment: production, Label: "Website"},
		{Name: "acme/cli", Deployment: Deployment{Kind: Release}},
	}
	if !reflect.DeepEqual(got.Projects[0].Repositories, want) {
		t.Errorf("want\n%+v\ngot\n%+v", want, got.Projects[0].Repositories)
	}
	if n := got.LabelCount(); n != 4 {
		t.Errorf("want 4 labels counted, got %d", n)
	}
}

// TestLoadLabelledFixture loads the made-up fixture with labels, and every
// fixture without them counts none.
func TestLoadLabelledFixture(t *testing.T) {
	got, err := Load(filepath.Join("testdata", "labels.yml"))
	if err != nil {
		t.Fatalf("want no error, got %v", err)
	}
	if n := got.LabelCount(); n != 4 {
		t.Errorf("want 4 labels, got %d", n)
	}
	for _, file := range []string{"minimal.yml", "full.yml", "no-projects.yml"} {
		cfg, err := Load(filepath.Join("testdata", file))
		if err != nil || cfg.LabelCount() != 0 {
			t.Errorf("%s: want it valid with no labels, got %d, %v", file, cfg.LabelCount(), err)
		}
	}
}

// TestNullLabelsAreLeftOut: a label or services key without a value is the
// key left out, as YAML reads it.
func TestNullLabelsAreLeftOut(t *testing.T) {
	for _, extra := range []string{"        label:\n", "        services:\n", "        label: null\n"} {
		got, err := parse([]byte(valid + extra))
		if err != nil || got.LabelCount() != 0 {
			t.Errorf("%q: want valid with no labels, got %d, %v", extra, got.LabelCount(), err)
		}
	}
}

// labelRepository is valid's repository line, which the refusals below add
// a label or services to.
const labelRepository = "        deployment: environment=production\n"

// withLabels is valid with extra lines added to its repository.
func withLabels(extra string) string { return edit(labelRepository, labelRepository+extra) }

// TestParseRefusesWrongLabels (forsgren#38): an empty label, a label used
// twice in a project, a value that is not text, an empty services map, an
// empty task, label and services together, and services on a release.
func TestParseRefusesWrongLabels(t *testing.T) {
	twice := `version: 1
projects:
  - name: Acme
    repositories:
      - name: acme/app
        services:
          deploy-api: API
      - name: acme/web
        label: api
`
	checkRefusals(t, []refusal{
		{"empty label", withLabels("        label: \"\"\n"), ErrLabel,
			`project "Acme": repository "acme/app": invalid label: a label is empty`},
		{"label of blanks", withLabels("        label: \"  \"\n"), ErrLabel,
			"invalid label: a label is empty"},
		{"empty service label", withLabels("        services:\n          deploy-api: \"\"\n"),
			ErrLabel, `repository "acme/app": invalid label: a label is empty`},
		{"service label without a value", withLabels("        services:\n          deploy-api:\n"),
			ErrLabel, "invalid label: a label is empty"},
		{"label twice in a project", twice, ErrLabel,
			`project "Acme": repository "acme/web": invalid label: "api" is used twice in the project (case is ignored)`},
		{"service label twice", withLabels("        services:\n          a: API\n          b: API\n"),
			ErrLabel, `invalid label: "API" is used twice in the project`},
		{"label a number", withLabels("        label: 5\n"), ErrSyntax,
			"line 7: cannot use !!int `5` here: labels and tasks are text"},
		{"label a list", withLabels("        label: [a]\n"), ErrSyntax,
			"line 7: cannot use !!seq here: labels and tasks are text"},
		{"service label a boolean", withLabels("        services:\n          deploy-api: true\n"),
			ErrSyntax, "line 8: cannot use !!bool `true` here: labels and tasks are text"},
		{"task a number", withLabels("        services:\n          5: API\n"),
			ErrSyntax, "line 8: cannot use !!int `5` here: labels and tasks are text"},
		{"services a list", withLabels("        services: [API]\n"), ErrSyntax, "line 7: cannot"},
		{"empty services", withLabels("        services: {}\n"), ErrLabel,
			"invalid label: services lists no task; write task: label lines, or leave services out"},
		{"empty task", withLabels("        services:\n          \"\": API\n"), ErrLabel,
			"invalid label: a task is empty"},
		{"label and services", withLabels("        label: App\n        services:\n          a: API\n"),
			ErrLabel, "invalid label: use label or services, not both"},
		{"services on a release", edit(labelRepository, "        deployment: release\n        services:\n          v1: x\n"),
			ErrLabel, "invalid label: a release's task is its tag, new with each release; use label"},
	})
}
