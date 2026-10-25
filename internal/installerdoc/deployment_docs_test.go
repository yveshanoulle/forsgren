package installerdoc

import "testing"

// TestConfigurationExplainsWhatEachDeploymentKindNeeds (forsgren#398): the
// configuration page tells, per kind of the deployment key, what a
// repository must hold for forsgren to count anything, how to check it, and
// that the deployment must name the commit that went live; the data files
// page links to it where collecting deployments is described.
func TestConfigurationExplainsWhatEachDeploymentKindNeeds(t *testing.T) {
	text := readRepoFileAsOneLine(t, "docs/configuration.md")
	wantAll(t, "docs/configuration.md", text,
		"### Giving a repository the deployments forsgren counts",
		"a workflow job with `environment: production` makes GitHub record one",
		"gh api repos/acme/app/deployments -f ref=COMMIT_SHA -f environment=production",
		"gh api repos/acme/app/deployments/DEPLOYMENT_ID/statuses -f state=success",
		"Deployments: Read and write",
		"`deployments: write`",
		"The deployment must name the commit that went live",
		"nothing to add",
		"publish a GitHub Release",
		"gh api repos/acme/app/deployments --jq")
	data := readRepoFileAsOneLine(t, "docs/data-files.md")
	wantAll(t, "docs/data-files.md", data,
		"(configuration.md#giving-a-repository-the-deployments-forsgren-counts)")
}
