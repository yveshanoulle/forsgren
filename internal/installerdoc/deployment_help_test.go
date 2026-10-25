package installerdoc

import (
	"strings"
	"testing"
)

// TestInstallerHelpsWhenNoDeploymentIsFound (forsgren#399): step 3 of the
// installer, when it finds nothing or a deploy job without an environment,
// proposes environment: production on the job or a record step after a
// deploy outside Actions, each only with the person's yes, never pushes to
// a product repository, and checks that the next deploy shows.
func TestInstallerHelpsWhenNoDeploymentIsFound(t *testing.T) {
	step := asOneLine(section(t, installerFile, "Step 3."))
	wantAll(t, "installer step 3", step,
		"Nothing is found, or a deploy job has no environment",
		"propose `environment: production` on the deploy job",
		"a record step after the deploy",
		"gh api repos/acme/app/deployments -f ref=COMMIT_SHA -f environment=production",
		"`deployments: write`",
		"Only with the person's yes",
		"Never push to a product repository on your own",
		"check that the next deploy shows",
		"(docs/configuration.md#giving-a-repository-the-deployments-forsgren-counts)")
}

// TestUpgraderHelpsWhenNoDeploymentShows (forsgren#399): step 9 of the
// upgrader gives the same help where it reads "No deployments".
func TestUpgraderHelpsWhenNoDeploymentShows(t *testing.T) {
	step := asOneLine(section(t, upgraderFile, "Step 9."))
	wantAll(t, "upgrader step 9", step,
		"propose `environment: production` on the deploy job",
		"a record step after the deploy",
		"Only with the person's yes",
		"Never push to a product repository on your own",
		"check that the next deploy shows",
		"(docs/configuration.md#giving-a-repository-the-deployments-forsgren-counts)")
}

// TestDeleterSaysNothingAboutDeploymentSetup (forsgren#399): agent-delete.md
// was checked and has no deployment setup to update.
func TestDeleterSaysNothingAboutDeploymentSetup(t *testing.T) {
	if strings.Contains(readRepoFile(t, deleterFile), "environment:") {
		t.Error("agent-delete.md speaks of a deployment environment")
	}
}
