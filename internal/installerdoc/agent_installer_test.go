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
