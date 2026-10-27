package installerdoc

import "testing"

// The upgrader proposes (forsgren#503, step 1): it looks at what GitHub
// records, shows what it found and why, and writes only with the person's yes.

// TestUpgraderProposesTheFoldersOfAService: for a service without `paths` it
// reads the deploy workflow and proposes folders; the person says yes, edits
// or skips.
func TestUpgraderProposesTheFoldersOfAService(t *testing.T) {
	wantAll(t, "agent-upgrade.md step 5", upgraderSection(t, "Step 5."),
		"look, propose, ask",
		"read-only, with the person's `gh`",
		"gh api repos/acme/app/actions/workflows --jq '.workflows[] | .path'",
		"gh api -H 'Accept: application/vnd.github.raw' repos/acme/app/contents/.github/workflows/deploy-web.yml",
		"`on.push.paths` and `paths-ignore`",
		"the deploy job's `working-directory`",
		"the folder of a Dockerfile it builds",
		"what you found and why",
		"the exact line you would write",
		"The person says yes, edits it, or skips it",
		"Ask which workflow it is when more than one could be")
}

// TestUpgraderProposesDeploymentRules: for each repository it lists what
// GitHub records and proposes a `deployments:` entry when more than one
// source is in use.
func TestUpgraderProposesDeploymentRules(t *testing.T) {
	wantAll(t, "agent-upgrade.md step 5", upgraderSection(t, "Step 5."),
		"**Several ways to deploy**",
		"gh api 'repos/acme/site/deployments?per_page=100' --jq '.[] | [.environment, .task] | @tsv' | sort | uniq -c",
		"gh release list -R acme/site -L 5 --exclude-drafts --exclude-pre-releases",
		"When more than one source is in use",
		"propose a `deployments:` entry",
		"`release: Releases`",
		"`environment=github-pages: {label: Website, paths: [website/]}`",
		"each rule is its own row",
		"the total row counts every deployment",
		"`deployment:` and `deployments:` never both",
		"only with the person's yes")
	wantAll(t, "agent-upgrade.md step 8", upgraderSection(t, "Step 8."),
		"Several ways to deploy (step 5 item 6)",
		"in place of the repository's `deployment:` line")
}
