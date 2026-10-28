package main

import (
	"context"
	"os"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/needs"
)

// refusedView is the setup issue's item for `view: weekly`.
const refusedView = "- [ ] `view`: `weekly` is not accepted: use standard, numbers or scoring. " +
	"Using the default `standard`."

// refusedDays is the item for `history_days: 0`.
const refusedDays = "- [ ] `history_days`: `0` is not accepted: use a whole number of days from 30 to 1825. " +
	"Using the default `365`."

// configWith replaces the checkout's config with lines (after the version and
// projects lines).
func configWith(t *testing.T, lines ...string) {
	t.Helper()
	text := "version: 1\nprojects: []\n" + strings.Join(lines, "\n") + "\n"
	if err := os.WriteFile("forsgren.config.yml", []byte(text), 0o600); err != nil {
		t.Fatal(err)
	}
}

// runCheckNeeds runs check-needs for acme/data against the checkout at 0.4.0
// and returns the exit code and the status it recorded.
func runCheckNeeds(t *testing.T) (int, string) {
	t.Helper()
	setVersion(t, "0.4.0")
	t.Setenv("GITHUB_TOKEN", testToken)
	code, _, _ := runCommand("check-needs", "--config", "forsgren.config.yml",
		"--repository", "acme/data", "--status", "needs-status.txt")
	return code, readFile(t, "needs-status.txt")
}

// TestCheckNeedsMakesAnItemOfEachRefusedSetting (forsgren#538): with every
// requirement in place, two refused settings open the setup issue with one
// item each, naming key, value, reason and default, under the refused
// settings heading alone; the run stays exit 0 and ok.
func TestCheckNeedsMakesAnItemOfEachRefusedSetting(t *testing.T) {
	fake := newRecordingIssueServer(t, "", "")
	installationWithIssuesWrite(t)
	configWith(t, "view: weekly", "history_days: 0")
	code, status := runCheckNeeds(t)
	if code != 0 || status != statusOK {
		t.Errorf("want exit 0 and %q, got %d, %q", statusOK, code, status)
	}
	wantOneWrite(t, fake.writes, "POST /repos/acme/data/issues ", refusedDays, "## Missing requirements")
	wantInOrderIn(t, fake.writes[0], "## Refused settings", refusedView, refusedDays)
}

// TestCheckNeedsKeepsTheTwoHeadingsApart (forsgren#538): a missing
// requirement and a refused setting stand under their own headings.
func TestCheckNeedsKeepsTheTwoHeadingsApart(t *testing.T) {
	fake := newRecordingIssueServer(t, "", "")
	installationWithoutIssuesWrite(t)
	configWith(t, "view: weekly")
	code, _ := runCheckNeeds(t)
	if code != 0 {
		t.Errorf("want exit 0, got %d", code)
	}
	wantInOrderIn(t, strings.Join(fake.writes, "\n"), "## Missing requirements", "## Refused settings", refusedView)
}

// wantInOrderIn fails t unless each of parts is in body, after the one before.
func wantInOrderIn(t *testing.T, body string, parts ...string) {
	t.Helper()
	rest := body
	for _, part := range parts {
		i := strings.Index(rest, part)
		if i < 0 {
			t.Fatalf("want %q in order in %q", part, body)
		}
		rest = rest[i+len(part):]
	}
}

// wantOneWrite fails t unless the only write is one that starts with prefix,
// holds want and does not hold unwanted.
func wantOneWrite(t *testing.T, writes []string, prefix, want, unwanted string) {
	t.Helper()
	if len(writes) != 1 || !strings.HasPrefix(writes[0], prefix) {
		t.Fatalf("want one write starting %q, got %q", prefix, writes)
	}
	if !strings.Contains(writes[0], want) || (unwanted != "" && strings.Contains(writes[0], unwanted)) {
		t.Errorf("want %q and not %q in the write, got %q", want, unwanted, writes[0])
	}
}

// TestCheckNeedsDropsAFixedSettingAndClosesTheIssue (forsgren#538): the open
// issue that carries the item is updated without the fixed one, and closed
// once no requirement is missing and no setting is refused.
func TestCheckNeedsDropsAFixedSettingAndClosesTheIssue(t *testing.T) {
	carried := needs.Marker + "\n\n## Refused settings\n\n" + refusedView + "\n" + refusedDays + "\n"
	fake := newRecordingIssueServer(t, "open", carried)
	installationWithIssuesWrite(t)
	configWith(t, "history_days: 0")
	runCheckNeeds(t)
	wantOneWrite(t, fake.writes, "PATCH /repos/acme/data/issues/7 ", refusedDays, "`view`")
	fake = newRecordingIssueServer(t, "open", carried)
	configWith(t, "view: standard")
	runCheckNeeds(t)
	wantClosed(t, fake)
}

// TestCheckNeedsReopensForARefusedSettingAlone (forsgren#538): a closed
// setup issue is reopened when only a setting is refused.
func TestCheckNeedsReopensForARefusedSettingAlone(t *testing.T) {
	fake := newRecordingIssueServer(t, "closed", needs.Marker+"\n")
	installationWithIssuesWrite(t)
	configWith(t, "view: weekly")
	runCheckNeeds(t)
	wantOneWrite(t, fake.writes, "PATCH /repos/acme/data/issues/7 ", refusedView, "")
}

// TestCheckNeedsRefusedSettingIsNeverARedRun (forsgren#538): a refused
// setting with a refused write is the status no-access, exit 0.
func TestCheckNeedsRefusedSettingIsNeverARedRun(t *testing.T) {
	newSetupServer(t, 403)
	installationWithIssuesWrite(t)
	configWith(t, "view: weekly")
	if code, status := runCheckNeeds(t); code != 0 || status != statusNoAccess {
		t.Errorf("want exit 0 and %q, got %d, %q", statusNoAccess, code, status)
	}
}

// TestReportMakesTheCallTheRefusedSettingsCallFor (forsgren#538): refused
// settings alone create, update or reopen the issue; none and nothing missing
// close it.
func TestReportMakesTheCallTheRefusedSettingsCallFor(t *testing.T) {
	title := needs.Title("1.29.1")
	refused := setupItems{refused: []needs.Refusal{{Key: "view", Written: "weekly", Reason: "r", Default: "standard"}}}
	open := github.SetupIssue{Number: 7, State: "open"}
	closed := github.SetupIssue{Number: 7, State: "closed"}
	cases := []struct {
		name  string
		items setupItems
		found github.SetupIssue
		ok    bool
		want  []string
	}{
		{"no issue", refused, github.SetupIssue{}, false, []string{"create " + title + " [forsgren-setup]"}},
		{"open", refused, open, true, []string{"update 7 " + title}},
		{"closed", refused, closed, true, []string{"reopen 7 " + title}},
		{"both lists empty", setupItems{}, open, true,
			[]string{"close 7 All items are in place as of forsgren 1.29.1."}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			fake := &recordingIssues{}
			report := setupReport{issues: fake, repo: "acme/app", version: "1.29.1"}
			if err := report.report(context.Background(), foundIssue{c.found, c.ok}, c.items); err != nil {
				t.Fatal(err)
			}
			checkSetupCalls(t, fake, c.want)
			if createsIssue(c.want) && !strings.Contains(fake.body, "`view`") {
				t.Errorf("want the item in the body, got %q", fake.body)
			}
		})
	}
}
