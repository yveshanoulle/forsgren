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
			want: Config{Version: 1, Projects: []Project{{
				Name: "Acme",
				Repositories: []Repository{
					{Name: "acme/app", Deployment: Deployment{Kind: Environment, Name: "production"}},
				},
			}}},
			repos: 1,
		},
		{
			file: "full.yml",
			want: Config{Version: 1, Projects: []Project{
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
		})
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
		{"wrong type", "version: 1\nprojects: acme\n", ErrSyntax, "line 2: cannot"},
		{"version as text", edit("version: 1", `version: "1"`), ErrSyntax, "line 1: cannot"},
		{"two documents", valid + "---\n" + valid, ErrSyntax, "more than one YAML document"},
		{"missing version", edit("version: 1\n", ""), ErrVersionMissing,
			"version is missing: write version: 1 at the top of the file"},
		{"version 2", edit("version: 1", "version: 2"), ErrVersionUnsupported,
			"unsupported version 2: this forsgren reads version 1"},
		{"version 0", edit("version: 1", "version: 0"), ErrVersionUnsupported, "unsupported version 0"},
		{"no projects key", "version: 1\n", ErrNoProjects, "no projects: list at least one under the projects key"},
		{"empty projects", "version: 1\nprojects: []\n", ErrNoProjects, "no projects"},
	})
}

// TestParseRefusesProjectsAndRepositories: names, duplicates and the
// deployment of each repository.
func TestParseRefusesProjectsAndRepositories(t *testing.T) {
	checkRefusals(t, []refusal{
		{"project without name", edit("  - name: Acme\n", "  - name: \"\"\n"), ErrProjectName,
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
		{"workflow without extension", edit("environment=production", "workflow=deploy"), ErrDeployment,
			`invalid deployment "workflow=deploy": the workflow file must end in .yml or .yaml`},
		{"workflow extension only", edit("environment=production", "workflow=.yml"), ErrDeployment,
			`invalid deployment "workflow=.yml": the workflow file must end in .yml or .yaml`},
		{"workflow with a directory", edit("environment=production", "workflow=.github/workflows/deploy.yml"),
			ErrDeployment, "the workflow is a file name in .github/workflows, without a directory"},
	})
}
