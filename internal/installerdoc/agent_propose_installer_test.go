package installerdoc

import "testing"

// The installer proposes (forsgren#503, step 2): for a new installation it
// looks at what GitHub records, shows what it found and why, and writes only
// with the person's yes.

// TestInstallerProposesTheFoldersAndRules: questions 15 and 16 say the agent
// looks and proposes, step 3 has the read-only commands, step 9 writes only
// what the person accepted.
func TestInstallerProposesTheFoldersAndRules(t *testing.T) {
	step2 := asOneLine(section(t, installerFile, "Step 2."))
	wantAll(t, "agent-installer.md step 2", step2,
		"you look and propose in step 3",
		"the person says yes, edits it, or skips it")
	step3 := asOneLine(section(t, installerFile, "Step 3."))
	wantAll(t, "agent-installer.md step 3", step3,
		"**Propose folders and rules**",
		"gh api -H 'Accept: application/vnd.github.raw' repos/acme/app/contents/.github/workflows/deploy-web.yml",
		"`on.push.paths` and `paths-ignore`",
		"the deploy job's `working-directory`",
		"the folder of a Dockerfile it builds",
		"what you found and why",
		"the exact line you would write",
		"gh api 'repos/acme/site/deployments?per_page=100' --jq '.[] | [.environment, .task] | @tsv' | sort | uniq -c",
		"When more than one source is in use",
		"propose a `deployments:` entry",
		"each rule is its own row",
		"the total row counts every deployment",
		"`deployment:` and `deployments:` never both",
		"Ask which workflow it is when more than one could be",
		"only with the person's yes")
	wantAll(t, "agent-installer.md step 9", asOneLine(section(t, installerFile, "Step 9.")),
		"the lines the person accepted or edited",
		"a proposal the person skipped is not written")
}

// TestUpdatingDocsSayTheUpgraderProposes: the manual says the upgrader now
// proposes folders and deployment rules.
func TestUpdatingDocsSayTheUpgraderProposes(t *testing.T) {
	wantAll(t, "docs/updating-and-releases.md", readRepoFileAsOneLine(t, "docs/updating-and-releases.md"),
		"The upgrader now proposes the folders of a service and the deployment rules of a repository from what GitHub shows")
}
