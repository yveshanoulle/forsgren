package config

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// TestLoadValid loads the made-up fixtures under testdata/ and checks every
// field, the default deployment included.
func TestLoadValid(t *testing.T) {
	cases := []struct {
		file  string
		want  Config
		repos int
	}{
		{
			file: "minimal.yml",
			want: Config{Version: 1, HistoryDays: DefaultHistoryDays, Projects: []Project{{
				Name: "Acme",
				Repositories: []Repository{
					{Name: "acme/app", Deployment: Deployment{Kind: Environment, Name: "production"}},
				},
			}}},
			repos: 1,
		},
		{
			file: "full.yml",
			want: Config{Version: 1, HistoryDays: DefaultHistoryDays, Projects: []Project{
				{Name: "Acme Shop", Repositories: []Repository{
					{Name: "acme/api", Deployment: Deployment{Kind: Environment, Name: "production"}},
					{Name: "acme/ios-app", Deployment: Deployment{Kind: Workflow, Name: "testflight.yml"}},
					{Name: "acme/website", Deployment: Deployment{Kind: Environment, Name: "production"}},
				}},
				{Name: "Acme Tools", Repositories: []Repository{
					{Name: "acme-labs/cli.tool", Deployment: Deployment{Kind: Release}},
					{Name: "acme/docs", Deployment: Deployment{Kind: Workflow, Name: "publish.yaml"}},
				}},
			}},
			repos: 5,
		},
	}
	for _, tc := range cases {
		t.Run(tc.file, func(t *testing.T) {
			got, err := Load(filepath.Join("testdata", tc.file))
			if err != nil {
				t.Fatalf("want no error, got %v", err)
			}
			if !reflect.DeepEqual(got, tc.want) {
				t.Errorf("want\n%+v\ngot\n%+v", tc.want, got)
			}
			if n := got.RepositoryCount(); n != tc.repos {
				t.Errorf("want %d repositories counted, got %d", tc.repos, n)
			}
		})
	}
}

// TestDefaultDeploymentIsProductionEnvironment pins the default of
// forsgren#6: a repository that names no deployment is measured by its
// GitHub Deployments to the environment production.
func TestDefaultDeploymentIsProductionEnvironment(t *testing.T) {
	got, err := parse([]byte(edit("        deployment: environment=production\n", "")))
	if err != nil {
		t.Fatalf("want no error, got %v", err)
	}
	want := Deployment{Kind: Environment, Name: DefaultEnvironment}
	if d := got.Projects[0].Repositories[0].Deployment; d != want || DefaultEnvironment != "production" {
		t.Errorf("want %+v (production), got %+v", want, d)
	}
}

func TestLoadMissingFileIsReadError(t *testing.T) {
	path := filepath.Join(t.TempDir(), "forsgren.config.yml")
	_, err := Load(path)
	if !errors.Is(err, ErrRead) {
		t.Fatalf("want ErrRead, got %v", err)
	}
	if !strings.Contains(err.Error(), path+": cannot read the config file") {
		t.Errorf("want the path and the reason, got %q", err)
	}
}

func TestLoadNamesTheFileInARefusal(t *testing.T) {
	path := filepath.Join(t.TempDir(), "forsgren.config.yml")
	if err := os.WriteFile(path, []byte(edit("version: 1", "version: 2")), 0o600); err != nil {
		t.Fatal(err)
	}
	_, err := Load(path)
	if !errors.Is(err, ErrVersionUnsupported) {
		t.Fatalf("want ErrVersionUnsupported, got %v", err)
	}
	if !strings.HasPrefix(err.Error(), path+": unsupported version 2") {
		t.Errorf("want the message to start with the path, got %q", err)
	}
}

// valid is the config every refusal case starts from: each case changes one
// thing, so the refusal it expects can only come from that change.
const valid = `version: 1
projects:
  - name: Acme
    repositories:
      - name: acme/app
        deployment: environment=production
`

// edit returns valid with its first old replaced by repl. It panics when old
// is not in valid, so a case can never test the unchanged config by mistake.
func edit(old, repl string) string {
	if !strings.Contains(valid, old) {
		panic("edit: " + old + " is not in the valid config")
	}
	return strings.Replace(valid, old, repl, 1)
}

const secondProject = `  - name: ACME
    repositories:
      - name: acme/other
`

const repeatedRepository = `  - name: Acme Two
    repositories:
      - name: ACME/App
`

// refusal is one invalid config, the error it must wrap and a part of the
// message it must carry.
type refusal struct {
	name string
	yaml string
	want error
	msg  string
}

// checkRefusals also holds every refusal to one line: check-config prints it
// into a workflow log, where a line of it that starts with :: would run as
// a workflow command (forsgren#9).
func checkRefusals(t *testing.T, cases []refusal) {
	t.Helper()
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := parse([]byte(tc.yaml))
			if !errors.Is(err, tc.want) {
				t.Fatalf("want %v, got %v", tc.want, err)
			}
			if !strings.Contains(err.Error(), tc.msg) {
				t.Errorf("want the message to contain %q, got %q", tc.msg, err)
			}
			if strings.ContainsAny(err.Error(), "\r\n") {
				t.Errorf("want the message on one line, got %q", err)
			}
		})
	}
}

// noProjectsMessage is what a file without a projects value is told: an
// installation that measures nothing yet says so, `projects: []`, and a
// forgotten or empty key is not taken for it (forsgren#12).
const noProjectsMessage = "no projects: list at least one under the projects key, or use projects: [] for none"

// TestExplicitEmptyProjectsIsValid: `projects: []` is a config that measures
// nothing yet, the starter forsgren writes (forsgren#12).
func TestExplicitEmptyProjectsIsValid(t *testing.T) {
	cases := map[string]string{
		"flow list":              "version: 1\nprojects: []\n",
		"flow list with a space": "version: 1\nprojects: [ ]\n",
		"projects first":         "projects: []\nversion: 1\n",
		"with comments":          "# nothing yet\nversion: 1\n# measure later\nprojects: [] # none\n",
	}
	for name, yaml := range cases {
		t.Run(name, func(t *testing.T) {
			got, err := parse([]byte(yaml))
			if err != nil {
				t.Fatalf("want no error, got %v", err)
			}
			if got.Version != 1 || len(got.Projects) != 0 || got.RepositoryCount() != 0 {
				t.Errorf("want version 1 and no projects, got %+v", got)
			}
		})
	}
}

// TestLoadFileWithEmptyProjects loads a made-up fixture file.
func TestLoadFileWithEmptyProjects(t *testing.T) {
	got, err := Load(filepath.Join("testdata", "no-projects.yml"))
	if err != nil {
		t.Fatalf("want no error, got %v", err)
	}
	if got.Version != 1 || len(got.Projects) != 0 {
		t.Errorf("want version 1 and no projects, got %+v", got)
	}
}

// TestParseRefusesTheFileShape: the YAML itself, the version and the
// projects list.
func TestParseRefusesTheFileShape(t *testing.T) {
	checkRefusals(t, []refusal{
		{"empty file", "", ErrEmpty, "the config file is empty"},
		{"comments only", "# nothing yet\n", ErrEmpty, "the config file is empty"},
		{"not YAML", "version: [1\n", ErrSyntax, "not a valid forsgren config"},
		{"unknown top-level key", edit("projects:", "projcts:"), ErrSyntax, `line 2: unknown key "projcts"`},
		{"unknown repository key", edit("deployment:", "deploy:"), ErrSyntax, `line 6: unknown key "deploy"`},
		{"every unknown key, one per line", "version: 1\nprojects:\n  - name: Acme\n    bogus: 1\n    other: 2\n",
			ErrSyntax, `line 4: unknown key "bogus"; line 5: unknown key "other"`},
		{"unknown key with a space and a semicolon", "version: 1\nprojects:\n  - name: Acme\n    \"a b;c\": 1\n",
			ErrSyntax, `line 4: unknown key "a b;c"`},
		{"unknown key with a line break", "version: 1\nprojects:\n  - name: Acme\n    \"x\\n::warning::injected\": 1\n",
			ErrSyntax, `line 4: unknown key "x\n::warning::injected"`},
		{"wrong type", "version: 1\nprojects: acme\n", ErrSyntax, "line 2: cannot"},
		{"wrong type with a line break", "version: \"\\n::error::\"\nprojects: []\n",
			ErrSyntax, "line 1: cannot use !!str `\\n::error::` here"},
		{"version as text", edit("version: 1", `version: "1"`), ErrSyntax, "line 1: cannot"},
		{"two documents", valid + "---\n" + valid, ErrSyntax, "more than one YAML document"},
		{"missing version", edit("version: 1\n", ""), ErrVersionMissing,
			"version is missing: write version: 1 at the top of the file"},
		{"version 2", edit("version: 1", "version: 2"), ErrVersionUnsupported,
			"unsupported version 2: this forsgren reads version 1"},
		{"version 0", edit("version: 1", "version: 0"), ErrVersionUnsupported, "unsupported version 0"},
		{"no projects key", "version: 1\n", ErrNoProjects, noProjectsMessage},
		{"projects without a value", "version: 1\nprojects:\n", ErrNoProjects, noProjectsMessage},
		{"projects null", "version: 1\nprojects: null\n", ErrNoProjects, noProjectsMessage},
		{"projects tilde", "version: 1\nprojects: ~\n", ErrNoProjects, noProjectsMessage},
		{"no projects and no version", "projects: []\n", ErrVersionMissing, "version is missing"},
		{"no projects and version 2", "version: 2\nprojects: []\n", ErrVersionUnsupported, "unsupported version 2"},
	})
}

// TestParseRefusesProjectsAndRepositories: names, duplicates and the
// deployment of each repository.
func TestParseRefusesProjectsAndRepositories(t *testing.T) {
	checkRefusals(t, []refusal{
		{"project without name", edit("  - name: Acme\n", "  - name: \"\"\n"), ErrProjectName,
			"project 1: a project has no name"},
		{"project name of blanks", edit("  - name: Acme\n", "  - name: \"  \"\n"), ErrProjectName,
			"project 1: a project has no name"},
		{"duplicate project ignoring case", valid + secondProject, ErrDuplicateProject,
			`project 2 "ACME": duplicate project name, the same as project 1 "Acme" (case is ignored)`},
		{"project without repositories", "version: 1\nprojects:\n  - name: Acme\n", ErrNoRepositories,
			`project "Acme": the project has no repositories`},
		{"repository without owner", edit("acme/app", "app"), ErrRepositoryName,
			`project "Acme": repository "app": not an owner/name repository such as acme/app`},
		{"repository with a path", edit("acme/app", "acme/app/x"), ErrRepositoryName, `repository "acme/app/x": not an`},
		{"repository as a URL", edit("acme/app", "https://github.com/acme/app"), ErrRepositoryName,
			`repository "https://github.com/acme/app": not an`},
		{"repository dot-dot", edit("acme/app", "acme/.."), ErrRepositoryName, `repository "acme/..": not an`},
		{"repository owner with a dot", edit("acme/app", "ac.me/app"), ErrRepositoryName, `repository "ac.me/app": not an`},
		{"repository without name", edit("      - name: acme/app\n", "      - name: \"\"\n"), ErrRepositoryName,
			`repository "": not an owner/name repository`},
		{"repository twice ignoring case", valid + repeatedRepository, ErrDuplicateRepository,
			`project "Acme Two": repository "ACME/App": listed twice, first in project "Acme" (case is ignored)`},
		{"deployment unknown form", edit("environment=production", "releases"), ErrDeployment,
			`repository "acme/app": invalid deployment "releases": ` +
				"use environment=<name>, workflow=<file>.yml or .yaml, or release"},
		{"deployment case", edit("environment=production", "Release"), ErrDeployment,
			`invalid deployment "Release": use environment=<name>`},
		{"environment without name", edit("environment=production", "environment="), ErrDeployment,
			`invalid deployment "environment=": the environment has no name`},
		{"environment name of blanks", edit("environment=production", "\"environment=  \""), ErrDeployment,
			`invalid deployment "environment=  ": the environment has no name`},
		{"workflow without extension", edit("environment=production", "workflow=deploy"), ErrDeployment,
			`invalid deployment "workflow=deploy": the workflow file must end in .yml or .yaml`},
		{"workflow extension only", edit("environment=production", "workflow=.yml"), ErrDeployment,
			`invalid deployment "workflow=.yml": the workflow file must end in .yml or .yaml`},
		{"workflow with a directory", edit("environment=production", "workflow=.github/workflows/deploy.yml"),
			ErrDeployment, "the workflow is a file name in .github/workflows, without a directory"},
	})
}
