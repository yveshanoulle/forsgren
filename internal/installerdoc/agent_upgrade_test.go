package installerdoc

import (
	"regexp"
	"strings"
	"testing"
)

// upgraderWIP is the line the upgrader carries until 166-11.
const upgraderWIP = "Work in progress (forsgren#166): not ready to follow yet."

// TestUpgraderStarts (forsgren#166, step 166-1): agent-upgrade.md checks
// the login's repo and workflow scopes, asks the person for one thing, the
// address of their current report, reads that report's footer and
// settings.html, and falls back to forsgren.config.yml when the settings
// page is missing. Since 166-11 the file no longer says it is a work in
// progress, README.md links it, and so do the docs and the installer.
func TestUpgraderStarts(t *testing.T) {
	wantAll(t, "step 1", upgraderSection(t, "Step 1."),
		"gh auth status", "'repo'", "'workflow'", "address of your current forsgren report")
	wantAll(t, "step 2", upgraderSection(t, "Step 2."),
		"settings.html", "Forsgren</a>", "exists from forsgren 0.5.0", "forsgren.config.yml")
	if strings.Contains(readUpgrader(t), upgraderWIP) {
		t.Error("the work-in-progress line is still there")
	}
	for _, path := range []repoFile{"README.md", "docs/updating-and-releases.md", installerFile} {
		if !strings.Contains(readRepoFile(t, path), string(upgraderFile)) {
			t.Errorf("%s does not link %s", path, upgraderFile)
		}
	}
}

// TestUpgraderStep2ComparesTheTwoPins (forsgren#166, step 166-2): step 2
// reads the version and the commit of both caller pins (metrics.yml in
// forsgren.yml, auto_update.yml in forsgren-update.yml), stops when they
// differ, checks the pinned commit is the one VERSION's release points at,
// and compares the footer's version with the pin without stopping on it.
func TestUpgraderStep2ComparesTheTwoPins(t *testing.T) {
	step := upgraderSection(t, "Step 2.")
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
	step := upgraderSection(t, "Step 3.")
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
	step := section(t, upgraderFile, "Step 4.")
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
	wantAll(t, "the never-do list", upgraderSection(t, "What you must never do"),
		"a repository named `forsgren` under another owner is an installation, not forsgren itself")
	wantAll(t, "step 2", upgraderSection(t, "Step 2."),
		"`OWNER/REPO` may be `OWNER/forsgren`",
		"exactly `yveshanoulle/forsgren` or `yveshanoulle/forsgren-template`",
		"A 404 means the installation is older than forsgren 0.5.0")
}

// TestUpgraderStep5AsksOnlyWhatIsTheirs (forsgren#166, step 166-5): step 5
// asks every question in one message with the current values filled in,
// handles a waiting Dependabot pull request that its level keeps open, and
// asks for a go-sentence naming every write before anything is committed.
func TestUpgraderStep5AsksOnlyWhatIsTheirs(t *testing.T) {
	step := upgraderSection(t, "Step 5.")
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
	step := section(t, upgraderFile, "Step 6.")
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
	step := upgraderSection(t, "Step 7.")
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

// TestUpgraderSupportsFromV020AndStep8WritesTheChosenSettings (forsgren#166,
// step 166-8): step 2 states once that the file supports installations
// pinned to forsgren 0.2.0 or later and stops on an older pin, without tying
// a missing forsgren-update.yml to a version; step 8 writes only the
// settings the person chose (keys above projects:, auto_update, the level,
// default-days), checks the config with check-config at LATEST, commits like
// route 6b without a trailer, and reads the files back.
func TestUpgraderSupportsFromV020AndStep8WritesTheChosenSettings(t *testing.T) {
	step2 := upgraderSection(t, "Step 2.")
	wantAll(t, "step 2", step2,
		"supports installations pinned to forsgren 0.2.0 or later",
		"older than v0.2.0: stop and report (not supported)")
	step7 := upgraderSection(t, "Step 7.")
	if strings.Contains(step2, "before forsgren 0.2.0") || strings.Contains(step7, "before forsgren 0.2.0") {
		t.Error("a missing forsgren-update.yml is tied to a version")
	}
	wantAll(t, "step 8", upgraderSection(t, "Step 8."),
		"above `projects:`",
		"go run github.com/yveshanoulle/forsgren/cmd/forsgren@LATEST check-config --config WORK/new/forsgren.config.yml",
		"default-days",
		"only the settings the person chose",
		"route 6b",
		"no `Co-Authored-By`",
		"read back",
		"Nothing chosen: skip this step")
}

// TestUpgraderStep9StartsARunAndChecksThePublishedPage (forsgren#166, step
// 166-9): step 9 starts the run itself (the schedule can be hours late),
// watches it to its end, then reads the published page with retries (Pages
// can serve the old page for minutes): the footer names LATEST, the
// settings page shows the chosen settings, a page that is hidden answers
// 404 and a shown one 200, a custom domain answers over HTTPS, and no setup
// issue stays open.
func TestUpgraderStep9StartsARunAndChecksThePublishedPage(t *testing.T) {
	wantAll(t, "step 9", upgraderSection(t, "Step 9."),
		"gh workflow run forsgren.yml -R OWNER/REPO",
		"the schedule can run hours late",
		"gh run watch RUN -R OWNER/REPO --exit-status",
		"gh run view RUN -R OWNER/REPO --log-failed",
		"Forsgren</a>",
		"at most 5 times",
		"settings.html",
		"404",
		"HTTPS",
		"gh issue list -R OWNER/REPO -l forsgren-setup")
}

// TestUpgraderEndsWithTheReportCleanupLaterAndGoingBack (forsgren#166, step
// 166-10): step 10 tells the person what changed in one message and removes
// WORK after leaving it (every `rm -r WORK` directly follows `cd WORK/..`);
// Later says what the next release does for the person's auto-update choice
// and that the file can be run again; Going back, which step 9 points to,
// undoes the upgrade with a new commit, never forced, and names what it
// undoes, with its own go.
func TestUpgraderEndsWithTheReportCleanupLaterAndGoingBack(t *testing.T) {
	wantAll(t, "step 10", upgraderSection(t, "Step 10."),
		"in one message", "the page address", "`VERSION` to `LATEST`")
	wantAll(t, "Later", upgraderSection(t, "Later"),
		"04:00 UTC", "auto_update_level", "run again", "agent-installer.md")
	back := upgraderSection(t, "Going back")
	wantAll(t, "Going back", back,
		"a new commit", "route 6b", "BEFORE", "unknown key", "Reply \"go: restore", "no `Co-Authored-By`")
	if strings.Contains(back, "force=true") || strings.Contains(back, "--force") {
		t.Error("Going back forces a push")
	}
	found, notLeavingFirst := workRemovals(t, upgraderFile)
	for _, r := range notLeavingFirst {
		t.Errorf("line %d is not directly preceded by `cd WORK/..`", r.line)
	}
	if found == 0 {
		t.Error("no `rm -r WORK` found")
	}
}

// TestUpgraderKeepsTheInstallersFixedRules (forsgren#166, step 166-11): the
// rules both files give a fresh agent in the same words stay equal, so the
// two cannot drift apart.
func TestUpgraderKeepsTheInstallersFixedRules(t *testing.T) {
	shared := []string{
		"Never force-push, and never rewrite history in any repository.",
		"Never install tools. When a tool is missing, stop and tell the person.",
		"Never change the person's git or gh configuration. When a step needs it, the person runs the command.",
		"Never offer to run a command that sets a secret or token inside your own session: no `!` shortcut, and never " +
			"ask for the token to be pasted to you. The person runs it in a separate terminal window, because the token " +
			"would land in the conversation.",
		"**A wait is not a failure.**",
		"Do not rely on shell variables or a changed directory carrying over from one command to the next;",
		"**The person does some steps themselves.** They are marked **Person**. Hand the person the text or command " +
			"as written, wait until they say it is done, then do the check yourself.",
	}
	for _, path := range agentFiles {
		wantAll(t, string(path), readRepoFileAsOneLine(t, path), shared...)
	}
}

// codeWords matches a capitalised word of a command: a placeholder.
var codeWords = regexp.MustCompile(`[A-Z][A-Z0-9]+`)

// fencedOrInlineCode returns the text of every fenced block and every code
// span of doc.
func fencedOrInlineCode(doc string) []string {
	fenced := regexp.MustCompile("(?s)```.*?```")
	spans := regexp.MustCompile("`([^`\n]+)`")
	code := fenced.FindAllString(doc, -1)
	for _, m := range spans.FindAllStringSubmatch(fenced.ReplaceAllString(doc, ""), -1) {
		code = append(code, m[1])
	}
	return code
}

// placeholderWords returns the capitalised words of one piece of code that
// stand for a value: not part of a longer name (FORSGREN_TOKEN) and not a
// word of an HTTP method or of a command's own output.
func placeholderWords(code string) []string {
	literal := map[string]bool{"POST": true, "PATCH": true, "LOGIN": true, "OK": true}
	var words []string
	for _, at := range codeWords.FindAllStringIndex(code, -1) {
		word := code[at[0]:at[1]]
		inName := strings.HasPrefix(code[at[1]:], "_") || (at[0] > 0 && code[at[0]-1] == '_')
		if !literal[word] && !inName {
			words = append(words, word)
		}
	}
	return words
}

// placeholdersUsed returns the placeholder words of all the code of doc.
func placeholdersUsed(doc string) map[string]bool {
	used := map[string]bool{}
	for _, code := range fencedOrInlineCode(doc) {
		for _, word := range placeholderWords(code) {
			used[word] = true
		}
	}
	return used
}

// TestEveryPlaceholderOfACommandIsListed (forsgren#166, 166-w; forsgren#174):
// each capitalised word used in a command of agent-upgrade.md and of
// agent-delete.md is named in that file's "How to work through this file",
// either as a placeholder or as a name a command makes.
func TestEveryPlaceholderOfACommandIsListed(t *testing.T) {
	for _, path := range []repoFile{upgraderFile, deleterFile} {
		listed := section(t, path, "How to work")
		for word := range placeholdersUsed(readRepoFile(t, path)) {
			if !strings.Contains(listed, "`"+word+"`") {
				t.Errorf("%s: %s is used in a command but not listed under How to work", path, word)
			}
		}
	}
}

// testedWith is the shape of both files' Tested-with line: the forsgren
// version, or the version moved from and to, the agent and the model.
var testedWith = regexp.MustCompile(
	`(?m)^Tested with: forsgren v\d+\.\d+\.\d+( → v\d+\.\d+\.\d+)?, Claude Code, model claude-sonnet-5-5\.$`)

// TestBothFilesNameWhatTheyWereTestedWith (forsgren#166, step 166-14;
// forsgren#174, step 174-2): the upgrader's and the deleter's Tested-with
// lines have the installer's shape, now that a fresh agent followed each on a
// real installation, and every file's "Before you start" is a ## section.
func TestBothFilesNameWhatTheyWereTestedWith(t *testing.T) {
	for _, path := range agentFiles {
		doc := readRepoFile(t, path)
		if !testedWith.MatchString(doc) {
			t.Errorf("%s has no Tested-with line of the usual shape", path)
		}
		if strings.Contains(doc, "not yet tested") {
			t.Errorf("%s still says it is not yet tested", path)
		}
		if !strings.Contains(doc, "\n## Before you start (for the person)") {
			t.Errorf("%s: Before you start is not a ## section", path)
		}
	}
	wantAll(t, string(upgraderFile), readRepoFileAsOneLine(t, upgraderFile),
		"Tested with: forsgren v0.8.5 → v1.3.0, Claude Code, model claude-sonnet-5-5.")
	wantAll(t, string(deleterFile), readRepoFileAsOneLine(t, deleterFile),
		"Tested with: forsgren v1.3.2, Claude Code, model claude-sonnet-5-5. "+
			"Start your agent with that model (in Claude Code: `claude --model sonnet`).")
}

// testedMajor captures the major of the version a file was tested with: the
// last one on the line, so "v0.8.5 → v1.3.0" gives 1.
var testedMajor = regexp.MustCompile(`(?m)^Tested with: forsgren (?:v\d+\.\d+\.\d+ → )?v(\d+)\.`)

// versionLineMajor captures the major of `var version` in
// cmd/forsgren/main.go, the one source of the running version.
var versionLineMajor = regexp.MustCompile(`(?m)^var version = "(\d+)\.`)

// mainGo is the file that holds the running version. This package cannot
// import package main, so it reads the `var version` line as text.
const mainGo repoFile = "cmd/forsgren/main.go"

// runningMajor returns the major of the running version.
func runningMajor(t *testing.T) string {
	t.Helper()
	m := versionLineMajor.FindStringSubmatch(readRepoFile(t, mainGo))
	if m == nil {
		t.Fatal("cmd/forsgren/main.go has no var version line")
	}
	return m[1]
}

// TestEveryAgentFileWasTestedOnTheRunningMajor (forsgren#148, decision
// #170): a release that starts a new major fails until the agent files have
// a new proof run behind them; within a major the line passes.
func TestEveryAgentFileWasTestedOnTheRunningMajor(t *testing.T) {
	running := runningMajor(t)
	for _, path := range agentFiles {
		tested := testedMajor.FindStringSubmatch(readRepoFile(t, path))
		if tested == nil {
			t.Errorf("%s has no Tested-with line to read a major from", path)
		} else if tested[1] != running {
			t.Errorf("%s was tested on forsgren major %s, but the running version is major %s: "+
				"run a new proof and update its Tested-with line", path, tested[1], running)
		}
	}
}

// TestUpgraderStep5SaysTheReleaseBeforeTheQuestions (forsgren#166, step
// 166-14): a fact that needs no answer is a statement before the numbered
// questions, not a question.
func TestUpgraderStep5SaysTheReleaseBeforeTheQuestions(t *testing.T) {
	step := upgraderSection(t, "Step 5.")
	statement := strings.Index(step, "Before the questions, say")
	questions := strings.Index(step, "The questions, in this order")
	if statement < 0 || questions < 0 || statement > questions {
		t.Error("step 5 does not say the release before the questions")
	}
	if strings.Contains(step, "**The release.**") || strings.Contains(step, "No answer is needed") {
		t.Error("step 5 still asks the release as a numbered question")
	}
}

// TestUpgraderStep8NamesEverySettingInTheCommitMessage (forsgren#166, step
// 166-14): the commit message names every setting the commit changes, the
// update wait included.
func TestUpgraderStep8NamesEverySettingInTheCommitMessage(t *testing.T) {
	wantAll(t, "step 8", upgraderSection(t, "Step 8."),
		"every setting the commit changes, the update wait included",
		"forsgren: set auto_update, auto_update_level, days_page and the update wait for LATEST")
}

// TestUpgraderStep9ReadsNotSet (forsgren#169): the settings check after the
// run tells a key the person set (their value, bare) from one they left alone
// (`(not set)` after the value), and step 2 item 2 reads both pages: the
// default in the last field with `(not set)`, and the older True and False.
func TestUpgraderStep9ReadsNotSet(t *testing.T) {
	wantAll(t, "step 9", upgraderSection(t, "Step 9."),
		"shows their value without `(not set)`",
		"shows the same value as before, with `(not set)` after it when the file does not set it",
		"shows its default followed by `(not set)`")
	step2 := upgraderSection(t, "Step 2.")
	wantAll(t, "step 2", step2,
		"such as `;auto_update;true;true, false;false;`",
		"From forsgren 1.7.2 on the last field is the default of the key",
		"`(not set)` after the current value means the file leaves the key out",
		"Up to forsgren 1.7.1 the last field is `True` when the file leaves the key out and `False` when it sets it")
	if strings.Contains(upgraderSection(t, "Step 9."), "ends with `False`") {
		t.Error("step 9 still says ends with `False`")
	}
}
