package installerdoc

import "testing"

// handOffPage is the docs page on measuring deployments that a workflow
// hands off to a system outside GitHub (forsgren#557).
const handOffPage repoFile = "docs/hand-off-pipelines.md"

// TestHandOffPageNamesTheBoundaryAndTheThreeRoutes (forsgren#557): the page
// says what a successful hand-off run means, gives the three routes with the
// documented REST endpoints and the permission each needs, and says how a
// failure after the hand-off reaches the numbers.
func TestHandOffPageNamesTheBoundaryAndTheThreeRoutes(t *testing.T) {
	wantAll(t, string(handOffPage), readRepoFileAsOneLine(t, handOffPage),
		"# Hand-off pipelines",
		"## The boundary",
		"means handed off, not live",
		"**Received**", "**Synced**", "**Released**",
		"## Route A: record a GitHub Deployment from outside",
		"POST /repos/{owner}/{repo}/deployments",
		"POST /repos/{owner}/{repo}/deployments/{deployment_id}/statuses",
		"Deployments: Read and write",
		"`ref` must be the app commit",
		"## Route B: trigger a small workflow from outside",
		"POST /repos/{owner}/{repo}/dispatches",
		"POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches",
		"deployments: write",
		"## Route C: keep the triggering workflow",
		"`workflow=`",
		"steps.handoff.outcome",
		"## Failures after the hand-off",
		"the `failure` label",
		"close it as not planned",
		"(configuration.md#giving-a-repository-the-deployments-forsgren-counts)",
		"(pages-and-views.md#change-fail-rate)")
}

// TestHandOffPageIsLinkedFromTheDocsLists (forsgren#557): README.md's
// Documentation list, docs/getting-started.md's reference list and the
// configuration page, where it says what a repository must hold for its
// deployment rule, link the page.
func TestHandOffPageIsLinkedFromTheDocsLists(t *testing.T) {
	wantAll(t, "README.md", section(t, "README.md", "Documentation"),
		"- [Hand-off pipelines](docs/hand-off-pipelines.md)")
	wantAll(t, "docs/getting-started.md", readRepoFileAsOneLine(t, "docs/getting-started.md"),
		"- [Hand-off pipelines](hand-off-pipelines.md)")
	wantAll(t, "docs/configuration.md",
		asOneLine(section(t, "docs/configuration.md", "Configuration")),
		"[Hand-off pipelines](hand-off-pipelines.md)")
}
