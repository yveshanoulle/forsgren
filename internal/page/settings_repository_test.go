package page

import (
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// withRepositorySettings is the placeholder with the settings of cfg, the
// top-level keys and the two per-repository rows (forsgren#512).
func withRepositorySettings(cfg config.Config) Data {
	data := Placeholder(testVersion)
	data.Settings = append(cfg.Settings(), cfg.RepositorySettings()...)
	return data
}

// TestSettingsPageShowsTheRepositoryRowsAsCounts (forsgren#512).
func TestSettingsPageShowsTheRepositoryRowsAsCounts(t *testing.T) {
	cfg := config.Config{Projects: []config.Project{{Repositories: []config.Repository{
		{Rules: []config.Rule{{Paths: []string{"x/"}}, {}}, Paths: map[string][]string{"a": {"x"}, "b": {"y"}, "c": {"z"}}},
	}}}}
	wantAll(t, "settings.html", rendered(t, "settings.html", withRepositorySettings(cfg)),
		`<th scope="row">deployments</th>
            <td>set on 1 repository (2 rules)</td>
            <td>per repository, in projects</td>
            <td>not set</td>`,
		`<th scope="row">paths</th>
            <td>set on 3 services and 1 rule</td>
            <td>per service or rule, in projects</td>
            <td>not set</td>`)
}

// TestSettingsPageSaysNotSetForNoRepositorySettings (forsgren#512).
func TestSettingsPageSaysNotSetForNoRepositorySettings(t *testing.T) {
	wantAll(t, "settings.html", rendered(t, "settings.html", withRepositorySettings(config.Config{})),
		`<th scope="row">deployments</th>
            <td>(not set)</td>`,
		`<th scope="row">paths</th>
            <td>(not set)</td>`)
}

// TestSettingsPageNamesNothingOfTheRepositories (forsgren#512): a config full
// of private-looking names renders none of them on the settings page.
func TestSettingsPageNamesNothingOfTheRepositories(t *testing.T) {
	cfg := config.Config{Projects: []config.Project{{Name: "Secret project", Repositories: []config.Repository{{
		Name:       "acme/secret-repo",
		Label:      "Secret",
		Deployment: config.Deployment{Kind: config.Environment, Name: "prod-secret"},
		Services:   map[string]string{"secret-task": "Secret service"},
		Paths:      map[string][]string{"secret-task": {"internal-secret/"}},
		Rules: []config.Rule{{Deployment: config.Deployment{Kind: config.Workflow, Name: "secret.yml"},
			Label: "Secret", Paths: []string{"internal-secret/"}}},
	}}}}}
	wantNone(t, "settings.html", rendered(t, "settings.html", withRepositorySettings(cfg)),
		"acme", "secret", "Secret", "internal-", "prod-")
}
