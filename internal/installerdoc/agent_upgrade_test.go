package installerdoc

import (
	"strings"
	"testing"
)

// upgraderFile is the agent upgrader, named from the repository root.
const upgraderFile = "agent-upgrade.md"

// upgraderWIP is the line the upgrader carries until 166-11.
const upgraderWIP = "Work in progress (forsgren#166): not ready to follow yet."

// wantAll reports each of wants that text does not contain.
func wantAll(t *testing.T, where, text string, wants ...string) {
	t.Helper()
	for _, want := range wants {
		if !strings.Contains(text, want) {
			t.Errorf("%s does not contain %q", where, want)
		}
	}
}

// TestUpgraderStarts (forsgren#166, step 166-1): agent-upgrade.md checks
// the login's repo and workflow scopes, asks the person for one thing, the
// address of their current report, reads that report's footer and
// settings.html, and falls back to forsgren.config.yml when the settings
// page is missing. Until 166-11 the file says it is a work in progress and
// README.md does not link it (166-11 removes the line and adds the link).
func TestUpgraderStarts(t *testing.T) {
	doc := readRepoFile(t, upgraderFile)
	wantAll(t, "step 1", asOneLine(section(t, doc, "Step 1.")),
		"gh auth status", "'repo'", "'workflow'", "address of your current forsgren report")
	wantAll(t, "step 2", asOneLine(section(t, doc, "Step 2.")),
		"settings.html", "Forsgren</a>", "exists from forsgren 0.5.0", "forsgren.config.yml")
	wantAll(t, upgraderFile, doc, upgraderWIP)
	if strings.Contains(readRepoFile(t, "README.md"), upgraderFile) {
		t.Errorf("README.md links %s before 166-11", upgraderFile)
	}
}

// TestUpgraderStep2ComparesTheTwoPins (forsgren#166, step 166-2): step 2
// reads the version and the commit of both caller pins (metrics.yml in
// forsgren.yml, auto_update.yml in forsgren-update.yml), stops when they
// differ, checks the pinned commit is the one VERSION's release points at,
// and compares the footer's version with the pin without stopping on it.
func TestUpgraderStep2ComparesTheTwoPins(t *testing.T) {
	step := asOneLine(section(t, readRepoFile(t, upgraderFile), "Step 2."))
	wantAll(t, "step 2", step,
		"auto_update.yml@",
		"the same version and the same commit",
		"gh api repos/yveshanoulle/forsgren/commits/VERSION --jq .sha",
		"differs from the pin",
		"stop and report (a half-moved pin)")
}

// TestUpgraderStep3FindsTheLatestRelease (forsgren#166, step 166-3): step 3
// takes the latest release from the release list (not tags), its commit
// from the API, compares versions as numbers, stops when the pin is not
// older, and reads a waiting Dependabot pull request from its diff.
func TestUpgraderStep3FindsTheLatestRelease(t *testing.T) {
	step := asOneLine(section(t, readRepoFile(t, upgraderFile), "Step 3."))
	wantAll(t, "step 3", step,
		"gh release list -R yveshanoulle/forsgren --exclude-drafts --exclude-pre-releases",
		"not the tags",
		"gh api repos/yveshanoulle/forsgren/commits/LATEST --jq .sha",
		"sort -V",
		"already the latest release",
		"gh pr list -R OWNER/REPO --app dependabot --state open",
		"gh pr diff PR -R OWNER/REPO",
		"`LATESTSHA`")
}

// TestUpgraderStep4ReadsEveryReleaseNote (forsgren#166, step 166-4): step 4
// reads the notes of every release after VERSION up to LATEST, oldest first,
// states the general rule, and keeps the 1.3.0 Daily page change in its
// worked example alone, so the rule is not a 1.3.0 special case.
func TestUpgraderStep4ReadsEveryReleaseNote(t *testing.T) {
	step := section(t, readRepoFile(t, upgraderFile), "Step 4.")
	rule, example, found := strings.Cut(step, "Worked example")
	if !found {
		t.Fatal("step 4 has no Worked example")
	}
	wantAll(t, "step 4", asOneLine(rule),
		"gh release list -R yveshanoulle/forsgren --exclude-drafts --exclude-pre-releases -L 100",
		"gh release view TAG -R yveshanoulle/forsgren --json body --jq .body",
		"oldest first",
		"Read each release's notes for what it asks of an installation",
		"No new permission, secret or config key",
		"forsgren-setup")
	wantAll(t, "the worked example", asOneLine(example),
		"1.3.0", "days_page: true", "loses its Daily page")
	if strings.Contains(rule, "1.3.0") || strings.Contains(rule, "days_page") {
		t.Error("step 4 names 1.3.0 or days_page outside its worked example")
	}
}

// TestUpgraderTellsForsgrenItselfFromAnInstallation (forsgren#166, step
// 166-5): an installation may be named forsgren, so the never-do list means
// yveshanoulle/forsgren exactly, step 2 refuses only that exact name and the
// template's, and a 404 on settings.html reads as older than 0.5.0.
func TestUpgraderTellsForsgrenItselfFromAnInstallation(t *testing.T) {
	doc := readRepoFile(t, upgraderFile)
	wantAll(t, "the never-do list", asOneLine(section(t, doc, "What you must never do")),
		"a repository named `forsgren` under another owner is an installation, not forsgren itself")
	wantAll(t, "step 2", asOneLine(section(t, doc, "Step 2.")),
		"`OWNER/REPO` may be `OWNER/forsgren`",
		"exactly `yveshanoulle/forsgren` or `yveshanoulle/forsgren-template`",
		"A 404 means the installation is older than forsgren 0.5.0")
}

// TestUpgraderStep5AsksOnlyWhatIsTheirs (forsgren#166, step 166-5): step 5
// asks every question in one message with the current values filled in,
// handles a waiting Dependabot pull request that its level keeps open, and
// asks for a go-sentence naming every write before anything is committed.
func TestUpgraderStep5AsksOnlyWhatIsTheirs(t *testing.T) {
	step := asOneLine(section(t, readRepoFile(t, upgraderFile), "Step 5."))
	wantAll(t, "step 5", step,
		"in one message",
		"Never show the person a placeholder",
		"auto_update_level",
		"the update wait",
		"WORK/asks.md",
		"its level kept it from merging",
		"raise the level",
		"merge it once",
		"move the pins in step 6",
		"Reply \"go: upgrade OWNER/REPO from VERSION to LATEST",
		"A bare \"go\"",
		"Nothing is committed before that reply")
}

// TestUpgraderStep6MovesThePinsInOneCommit (forsgren#166, step 166-6):
// step 6 merges the waiting pull request without --admin, or moves both pins
// in one commit through the Git Data API (blobs, tree, commit, ref), never
// forced, with no trailer in the message, and reads the ref and both files
// back.
func TestUpgraderStep6MovesThePinsInOneCommit(t *testing.T) {
	step := section(t, readRepoFile(t, upgraderFile), "Step 6.")
	wantAll(t, "step 6", asOneLine(step),
		"gh pr merge PR -R OWNER/REPO --squash",
		"Never `--admin`",
		"repos/OWNER/REPO/git/blobs",
		"repos/OWNER/REPO/git/trees",
		"repos/OWNER/REPO/git/commits",
		"repos/OWNER/REPO/git/refs/heads/BRANCH",
		"-F force=false",
		"no `Co-Authored-By`",
		"in one commit",
		"read back")
	for _, banned := range []string{"force=true", "--force", "-f force"} {
		if strings.Contains(step, banned) {
			t.Errorf("step 6 contains %q", banned)
		}
	}
}

// TestUpgraderStep7BringsOverOnlyWhatTheNotesName (forsgren#166, step
// 166-7): step 7 reads the template's current files, changes the
// installation's own copies only where the release notes ask, never copies a
// whole template file, keeps the token line, stays inside the go of step 5
// (a line the plan did not name shows the plan again), commits like route 6b
// without a trailer, and reads the files back.
func TestUpgraderStep7BringsOverOnlyWhatTheNotesName(t *testing.T) {
	step := asOneLine(section(t, readRepoFile(t, upgraderFile), "Step 7."))
	wantAll(t, "step 7", step,
		"repos/yveshanoulle/forsgren-template/contents/.github/dependabot.yml",
		"repos/yveshanoulle/forsgren-template/contents/.github/workflows/forsgren-update.yml",
		"Never copy a whole template file over the installation's",
		"WORK/asks.md",
		"`FORSGREN_TOKEN:` line",
		"default-days",
		"show the plan again and wait for a new go",
		"route 6b",
		"no `Co-Authored-By`",
		"read back",
		"Nothing named: skip this step")
}
