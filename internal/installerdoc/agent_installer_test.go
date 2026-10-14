package installerdoc

import (
	"os"
	"strings"
	"testing"
)

const installerFile = "../../agent-installer.md"

func readInstaller(t *testing.T) string {
	t.Helper()
	b, err := os.ReadFile(installerFile)
	if err != nil {
		t.Fatalf("read %s: %v", installerFile, err)
	}
	return string(b)
}

// section returns the text of the "## " section whose heading starts with
// heading, from the heading line up to the next "## " heading (or the end).
func section(t *testing.T, doc, heading string) string {
	t.Helper()
	lines := strings.Split(doc, "\n")
	start := -1
	for i, l := range lines {
		if start < 0 {
			if strings.HasPrefix(l, "## "+heading) {
				start = i
			}
			continue
		}
		if strings.HasPrefix(l, "## ") {
			return strings.Join(lines[start:i], "\n")
		}
	}
	if start < 0 {
		t.Fatalf("no section %q in %s", heading, installerFile)
	}
	return strings.Join(lines[start:], "\n")
}

// TestStep16RemovesCustomDomainBeforeReSetting (forsgren#142, step 142-9):
// setting the same custom domain again starts no certificate request, so
// step 16 must remove the domain (cname=null) before setting it again.
func TestStep16RemovesCustomDomainBeforeReSetting(t *testing.T) {
	step := section(t, readInstaller(t), "Step 16.")
	if !strings.Contains(step, "-F cname=null") {
		t.Errorf("step 16 does not remove the custom domain with `-F cname=null`:\n%s", step)
	}
}

// TestEveryWorkFolderRemovalLeavesTheFolderFirst (forsgren#142, step 142-9):
// an agent that removes the folder it works in raises Claude Code's
// dangerous-rm prompt, so every `rm -r WORK` is directly preceded by
// `cd WORK/..`.
func TestEveryWorkFolderRemovalLeavesTheFolderFirst(t *testing.T) {
	lines := strings.Split(readInstaller(t), "\n")
	found := 0
	for i, l := range lines {
		if !strings.Contains(l, "rm -r WORK") {
			continue
		}
		found++
		if i == 0 || strings.TrimSpace(lines[i-1]) != "cd WORK/.." {
			t.Errorf("line %d %q is not directly preceded by `cd WORK/..`", i+1, strings.TrimSpace(l))
		}
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
	doc := readInstaller(t)
	step := section(t, doc, "Step 16.")
	for _, want := range []string{"settings/pages", "Remove", "DNS check successful"} {
		if !strings.Contains(step, want) {
			t.Errorf("step 16 does not contain %q", want)
		}
	}
	if !strings.Contains(section(t, doc, "Starting over"), "step 16") {
		t.Error("Starting over does not point to the step-16 tip")
	}
}
