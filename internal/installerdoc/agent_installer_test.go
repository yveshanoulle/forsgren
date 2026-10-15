package installerdoc

import (
	"strings"
	"testing"
)

// TestStep16RemovesCustomDomainBeforeReSetting (forsgren#142, step 142-9):
// setting the same custom domain again starts no certificate request, so
// step 16 must remove the domain (cname=null) before setting it again.
func TestStep16RemovesCustomDomainBeforeReSetting(t *testing.T) {
	step := section(t, installerFile, "Step 16.")
	if !strings.Contains(step, "-F cname=null") {
		t.Errorf("step 16 does not remove the custom domain with `-F cname=null`:\n%s", step)
	}
}

// TestEveryWorkFolderRemovalLeavesTheFolderFirst (forsgren#142, step 142-9):
// an agent that removes the folder it works in raises Claude Code's
// dangerous-rm prompt, so every `rm -r WORK` is directly preceded by
// `cd WORK/..`.
func TestEveryWorkFolderRemovalLeavesTheFolderFirst(t *testing.T) {
	found, notLeavingFirst := workRemovals(t, installerFile)
	for _, r := range notLeavingFirst {
		t.Errorf("line %d %q is not directly preceded by `cd WORK/..`", r.line, r.text)
	}
	if found == 0 {
		t.Error("no `rm -r WORK` found: the test would pass vacuously")
	}
}

// TestStep16GivesThePersonTheSettingsPagesTip (forsgren#142, step 142-9):
// when the API removal fails or the state stays empty, step 16 hands the
// person the click path in Settings > Pages, and Starting over points to it
// instead of repeating it.
func TestStep16GivesThePersonTheSettingsPagesTip(t *testing.T) {
	step := section(t, installerFile, "Step 16.")
	for _, want := range []string{"settings/pages", "Remove", "DNS check successful"} {
		if !strings.Contains(step, want) {
			t.Errorf("step 16 does not contain %q", want)
		}
	}
	if !strings.Contains(section(t, installerFile, "Starting over"), "step 16") {
		t.Error("Starting over does not point to the step-16 tip")
	}
}

// TestCustomDomainIsSetAfterTheCNAMEStep (forsgren#173): GitHub checks DNS
// when the custom domain is set, so the step that sets it (the
// `pages -f cname=DOMAIN` call) must come after the step that has the person
// add the CNAME record, and must check that record through a public resolver.
func TestCustomDomainIsSetAfterTheCNAMEStep(t *testing.T) {
	text := readInstaller(t)
	dns := strings.Index(text, "## Step 14. Custom domain: the DNS record")
	set := strings.Index(text, "## Step 15. Custom domain: set it on the repository")
	if dns < 0 || set < 0 || dns > set {
		t.Fatalf("the DNS record step (at %d) must come before the set-the-domain step (at %d)", dns, set)
	}
	call := strings.Index(text, "-f cname=DOMAIN")
	if call < set {
		t.Errorf("the call that sets the custom domain (at %d) is before the set-the-domain step (at %d)", call, set)
	}
	step := section(t, installerFile, "Step 15.")
	if !strings.Contains(step, "dig +short @1.1.1.1 DOMAIN") {
		t.Errorf("step 15 does not check the CNAME through a public resolver first:\n%s", step)
	}
}

// TestStep10BKeepsTheSecretCommandOutOfTheSession (forsgren#175): the
// command that sets the secret is run by the person in a separate terminal
// window, never offered inside the agent's session (no `!` shortcut).
func TestStep10BKeepsTheSecretCommandOutOfTheSession(t *testing.T) {
	step := asOneLine(section(t, installerFile, "Step 10."))
	wantAll(t, "step 10", step, "separate terminal window", "no `!` shortcut")
}

// TestStep14ChecksTheCNAMEBeforeAskingForIt (forsgren#175): the DNS record
// may already exist, so step 14 runs the dig first and asks the person to
// add or fix the record only when it is missing or wrong.
func TestStep14ChecksTheCNAMEBeforeAskingForIt(t *testing.T) {
	step := asOneLine(section(t, installerFile, "Step 14."))
	check := strings.Index(step, "Check first whether the record already exists")
	ask := strings.Index(step, "hand the person this")
	if check < 0 || ask < 0 || check > ask {
		t.Fatalf("step 14 must check the record (at %d) before it hands the person the ask (at %d):\n%s", check, ask, step)
	}
	wantAll(t, "step 14", step, "only when it is missing or wrong")
}

// TestStep13DoesNotAskForTheValueOfAVerifiedDomain (forsgren#175): for a
// domain the person says is already verified, the agent reads the TXT record
// with dig itself, records that "verified" rests on the person's word, and
// goes on, without asking for GitHub's value.
func TestStep13DoesNotAskForTheValueOfAVerifiedDomain(t *testing.T) {
	step := asOneLine(section(t, installerFile, "Step 13."))
	wantAll(t, "step 13", step,
		"you check the TXT record is in DNS with dig yourself",
		"that \"verified\" rests on the person's word",
		"do not ask the person to copy GitHub's value")
	if strings.Contains(step, "only send you the record's name and value") {
		t.Error("step 13 still has an already verified person send the record's name and value")
	}
}

// TestInstallerStep12ReadsTheDefaultColumn (forsgren#169): the settings proof
// reads the last field of each row as the key's default value and tells a key
// the file sets (a bare value) from one it leaves out (`(not set)` after the
// value), so it can be checked from the page alone; it no longer speaks of
// True and False.
func TestInstallerStep12ReadsTheDefaultColumn(t *testing.T) {
	proof := asOneLine(section(t, installerFile, "Step 12."))
	wantAll(t, "step 12", proof,
		"`;view;numbers;standard, numbers, scoring;standard;`",
		"last field of each row is the default of the key: `standard`, `false`, `major`, `365`, `100`, "+
			"`8`, `30`, `true`, `false`, `unlisted`, `unlisted`",
		"show the value of the config, without `(not set)`",
		"`history_chunk_days` shows `100 (not set)` and `working_hours` shows `8 (not set)`",
		"Eleven rows in all")
	for _, old := range []string{"`True` (the default)", "`False` (set in forsgren.config.yml", ";False;"} {
		if strings.Contains(proof, old) {
			t.Errorf("agent-installer.md step 12 still says %q", old)
		}
	}
}
