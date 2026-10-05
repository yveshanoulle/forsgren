package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Made-up commits of the pin: the old one at v0.1.3, the new one at v0.1.4.
const (
	oldPinSHA = "437c858abd71d6f33e6f714af7984de3855d8e73"
	newPinSHA = "0123456789abcdef0123456789abcdef01234567"
)

// autoUpdateConfig is a valid config of an installation that merges patch
// updates by itself.
const autoUpdateConfig = oneRepository + "auto_update: true\nauto_update_level: patch\n"

// bumpPatch is the patch of Dependabot's bump of the pin in forsgren.yml, as
// GitHub's pull request files answer has it: the hunk without file headers.
const bumpPatch = "@@ -14 +14 @@\n" +
	"-    uses: yveshanoulle/forsgren/.github/workflows/metrics.yml@" + oldPinSHA + " # v0.1.3\n" +
	"+    uses: yveshanoulle/forsgren/.github/workflows/metrics.yml@" + newPinSHA + " # v0.1.4\n"

// jsonOf is v as the JSON GitHub answers with.
func jsonOf(t *testing.T, v any) string {
	t.Helper()
	body, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return string(body)
}

// TestCheckUpdateMergesDependabotsPatchBump pins forsgren#58, step 16: on
// Dependabot's pull request that moves the pin one patch release, whose
// release is published with its tag at the pinned commit, check-update says
// `merge v0.1.3 to v0.1.4` on stdout and exits 0.
func TestCheckUpdateMergesDependabotsPatchBump(t *testing.T) {
	fakeAPI(t, map[string]string{
		"/repos/acme/data/pulls/7": `{"user": {"login": "dependabot[bot]"}}`,
		"/repos/acme/data/pulls/7/files": jsonOf(t, []map[string]string{
			{"filename": ".github/workflows/forsgren.yml", "patch": bumpPatch}}),
		"/repos/yveshanoulle/forsgren/releases/tags/v0.1.4": `{"tag_name": "v0.1.4", "draft": false}`,
		"/repos/yveshanoulle/forsgren/commits/tags/v0.1.4":  newPinSHA,
	}, 0)
	path := filepath.Join(t.TempDir(), "forsgren.config.yml")
	if err := os.WriteFile(path, []byte(autoUpdateConfig), 0o600); err != nil {
		t.Fatal(err)
	}
	var stdout, stderr bytes.Buffer
	code := run([]string{"check-update", "--config", path, "--repo", "acme/data", "--pull", "7"}, &stdout, &stderr)
	if code != 0 || strings.TrimSpace(stdout.String()) != "merge v0.1.3 to v0.1.4" {
		t.Errorf("want exit 0 and `merge v0.1.3 to v0.1.4`, got %d, %q, stderr %q", code, stdout.String(), stderr.String())
	}
}
