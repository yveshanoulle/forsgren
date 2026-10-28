package main

import (
	"path/filepath"
	"strings"
	"testing"
)

// The setting week_commits (forsgren#548, decision #549 A) through the real
// pipeline: the Commits columns of the Week page are off unless it is true.

// fixtureWeekPageWith is week.html of the fixture rendered with the extra line
// added to its config.
func fixtureWeekPageWith(t *testing.T, extra string) string {
	t.Helper()
	pinNow(t)
	file := readFile(t, fixtureSite+"/forsgren.config.yml")
	dir := filepath.Join(t.TempDir(), "site")
	code, _, stderr := runCommand("render", "--out", dir, "--config", writeConfig(t, file+extra),
		"--data", fixtureSite+"/data/deployments.csv")
	if code != 0 {
		t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
	}
	return readFile(t, filepath.Join(dir, "week.html"))
}

// TestTheWeekPageShowsItsCommitsColumnsOnlyWithWeekCommitsTrue: left out, false
// and a value that is not accepted give three columns per group and no en dash;
// true gives four.
func TestTheWeekPageShowsItsCommitsColumnsOnlyWithWeekCommitsTrue(t *testing.T) {
	for name, tc := range map[string]struct {
		line    string
		commits bool
	}{
		"absent": {"", false}, "false": {"week_commits: false\n", false},
		"not accepted": {"week_commits: yes\n", false}, "true": {"week_commits: true\n", true},
	} {
		t.Run(name, func(t *testing.T) {
			wantWeekCommitsColumns(t, fixtureWeekPageWith(t, tc.line), tc.commits)
		})
	}
}

// wantWeekCommitsColumns checks the Week page against one week_commits mode:
// four columns per group, a Commits header and the en dash of a row Per
// repository with commits, three columns and neither without.
func wantWeekCommitsColumns(t *testing.T, page string, commits bool) {
	t.Helper()
	cols := `colspan="3"`
	if commits {
		cols = `colspan="4"`
	}
	if !strings.Contains(page, cols) {
		t.Errorf("want %s in the Week page", cols)
	}
	if strings.Contains(page, ">Commits<") != commits {
		t.Errorf("want a Commits header %v", commits)
	}
	if strings.Contains(page, "<td>–</td>") != commits {
		t.Errorf("want the en dash of a row Per repository %v", commits)
	}
}

// TestARefusedWeekCommitsValueIsExplainedOnTheSettingsPage (forsgren#183, #538):
// the settings page names the value as written and the reason, false kept.
func TestARefusedWeekCommitsValueIsExplainedOnTheSettingsPage(t *testing.T) {
	dir := renderInto(t, "--config", writeConfig(t, validConfig+"week_commits: yes\n"))
	settings := readSite(t, dir, "settings.html")
	refused := `<span class="written">yes</span> is not accepted: use true or false.`
	for _, want := range []string{"week_commits", refused} {
		if !strings.Contains(settings, want) {
			t.Errorf("want %q on the settings page", want)
		}
	}
}

// TestCheckConfigWarnsAboutARefusedWeekCommits: one setting not accepted, the
// warning on stderr, exit 0.
func TestCheckConfigWarnsAboutARefusedWeekCommits(t *testing.T) {
	code, stdout, stderr := runCommand("check-config", "--config", writeConfig(t, "week_commits: yes\n"+validConfig))
	if code != 0 {
		t.Errorf("want exit 0, got %d", code)
	}
	if !strings.HasSuffix(stdout, "settings not accepted: 1\n") {
		t.Errorf("want one setting not accepted, got %q", stdout)
	}
	if !strings.Contains(stderr, `invalid week_commits "yes": use true or false; using the default false`) {
		t.Errorf("want the refusal on stderr, got %q", stderr)
	}
}

// TestCheckNeedsMakesARefusedWeekCommitsASetupIssueItem (forsgren#538): a
// week_commits value that is not accepted is one item under the refused
// settings heading, naming the key, the value, the reason and the default
// false in force; the run stays exit 0 and ok.
func TestCheckNeedsMakesARefusedWeekCommitsASetupIssueItem(t *testing.T) {
	fake := newRecordingIssueServer(t, "", "")
	installationWithIssuesWrite(t)
	configWith(t, "week_commits: yes")
	code, status := runCheckNeeds(t)
	if code != 0 || status != statusOK {
		t.Errorf("want exit 0 and %q, got %d, %q", statusOK, code, status)
	}
	if len(fake.writes) != 1 {
		t.Fatalf("want one write, got %q", fake.writes)
	}
	wantInOrderIn(t, fake.writes[0], "## Refused settings",
		"- [ ] `week_commits`: `yes` is not accepted: use true or false. Using the default `false`.")
}
