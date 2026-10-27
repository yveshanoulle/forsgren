package config

import (
	"strings"
	"testing"
)

// secretConfig is a config full of names that must never reach a public page.
func secretConfig() Config {
	return Config{Projects: []Project{{Name: "Secret project", Repositories: []Repository{{
		Name:       "acme/secret-repo",
		Label:      "Secret",
		Deployment: Deployment{Kind: Environment, Name: "prod-secret"},
		Services:   map[string]string{"secret-task": "Secret service"},
		Paths:      map[string][]string{"secret-task": {"internal-secret/"}},
		Rules: []Rule{
			{Deployment: Deployment{Kind: Environment, Name: "prod-secret"}, Label: "Secret",
				Paths: []string{"internal-secret/"}},
			{Deployment: Deployment{Kind: Workflow, Name: "secret.yml"}, Label: "Other"},
		},
	}}}}}
}

// repositorySettingsOf are the two repository settings of c by key.
func repositorySettingsOf(t *testing.T, c Config) map[string]Setting {
	t.Helper()
	got := map[string]Setting{}
	for _, s := range c.RepositorySettings() {
		got[s.Key] = s
	}
	if len(got) != 2 {
		t.Fatalf("want the two settings deployments and paths, got %+v", c.RepositorySettings())
	}
	return got
}

// TestRepositorySettingsSayNotSetForNone (forsgren#512).
func TestRepositorySettingsSayNotSetForNone(t *testing.T) {
	got := repositorySettingsOf(t, Config{Projects: []Project{{Repositories: []Repository{{Name: "a/b"}}}}})
	for _, key := range []string{"deployments", "paths"} {
		if s := got[key]; s.Set || s.Value != "" || s.Default != "not set" {
			t.Errorf("%s: want not set, an empty value and the default not set, got %+v", key, s)
		}
	}
}

// TestRepositorySettingsCountOnly (forsgren#512): counts with the right plurals.
func TestRepositorySettingsCountOnly(t *testing.T) {
	cases := []struct {
		name        string
		repos       []Repository
		deployments string
		paths       string
	}{
		{"one repository, one rule", []Repository{{Rules: []Rule{{}}}}, "set on 1 repository (1 rule)", ""},
		{"two rules", []Repository{{Rules: []Rule{{}, {}}}}, "set on 1 repository (2 rules)", ""},
		{"two repositories", []Repository{{Rules: []Rule{{}}}, {Rules: []Rule{{}, {}}}, {}},
			"set on 2 repositories (3 rules)", ""},
		{"three services and a rule", []Repository{
			{Paths: map[string][]string{"a": {"x"}, "b": {"y"}}},
			{Paths: map[string][]string{"c": {"z"}}, Rules: []Rule{{Paths: []string{"p"}}, {}}}},
			"set on 1 repository (2 rules)", "set on 3 services and 1 rule"},
		{"one service", []Repository{{Paths: map[string][]string{"a": {"x"}}}}, "", "set on 1 service"},
		{"two rules with paths", []Repository{{Rules: []Rule{{Paths: []string{"a"}}, {Paths: []string{"b"}}}}},
			"set on 1 repository (2 rules)", "set on 2 rules"},
	}
	for _, c := range cases {
		got := repositorySettingsOf(t, Config{Projects: []Project{{Repositories: c.repos}}})
		if d := got["deployments"]; d.Value != c.deployments || d.Set != (c.deployments != "") {
			t.Errorf("%s: deployments: want %q, got %+v", c.name, c.deployments, d)
		}
		if p := got["paths"]; p.Value != c.paths || p.Set != (c.paths != "") {
			t.Errorf("%s: paths: want %q, got %+v", c.name, c.paths, p)
		}
	}
}

// TestRepositorySettingsCarryNoName (forsgren#512): nothing of a repository
// reaches the settings.
func TestRepositorySettingsCarryNoName(t *testing.T) {
	for _, s := range secretConfig().RepositorySettings() {
		for _, field := range []string{s.Key, s.Value, s.Default, s.Written, s.Reason} {
			for _, secret := range []string{"ecret", "prod", "acme", "internal"} {
				if strings.Contains(field, secret) {
					t.Errorf("%s: want no name, got %q in %q", s.Key, secret, field)
				}
			}
		}
	}
}

// TestSettingsStayTheTopLevelKeys (forsgren#512): deployments and paths are
// keys of a repository, not of the file, so Settings leaves them out and the
// drift tests over Settings stay about top-level keys.
func TestSettingsStayTheTopLevelKeys(t *testing.T) {
	for _, s := range (Config{}).Settings() {
		if s.Key == "deployments" || s.Key == "paths" {
			t.Errorf("want %s out of Settings, got it in", s.Key)
		}
	}
}
