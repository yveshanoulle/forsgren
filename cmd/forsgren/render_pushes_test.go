package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
	"github.com/yveshanoulle/forsgren/internal/metrics"
	"github.com/yveshanoulle/forsgren/internal/page"
)

// The push measures reach the page data (forsgren#397, step 4), read beside
// the history like pulls.csv; no template uses them yet.

const (
	pushShaBefore = "1111111111111111111111111111111111111111"
	pushShaAfter  = "2222222222222222222222222222222222222222"
	pushShaCommit = "3333333333333333333333333333333333333333"
	pushesHead    = "# forsgren pushes v1\nrepository,pushed_at,before,after,kind,bot,commits\n"
	pushCommitsH  = "# forsgren push commits v2\nrepository,after,sha,author,authored_at,first_parent,parents\n"
	pushesDeniedH = "# forsgren pushes denied v1\nrepository,denied_at\n"
	// pushesDeniedH2 is the head of the pushes denied format v2 (forsgren#414), read as v1 is.
	pushesDeniedH2 = "# forsgren pushes denied v2\nrepository,denied_at,token\n"
)

// pushesProject is the one project of these tests, Acme Shop, listing acme/api.
func pushesProject() config.Config {
	return config.Config{Projects: []config.Project{
		{Name: "Acme Shop", Repositories: []config.Repository{{Name: "acme/api"}}},
	}}
}

// writePushes writes data/pushes.csv and data/push_commits.csv beside the
// history at data: one push of acme/api on 2 October that brought one commit
// authored 25 minutes before it.
func writePushes(t *testing.T, data string) {
	t.Helper()
	push := history.Push{Repository: "acme/api", PushedAt: time.Date(2026, 10, 2, 10, 0, 0, 0, time.UTC),
		Before: pushShaBefore, After: pushShaAfter, Kind: history.PushKindPush, Bot: history.ByHuman, Commits: 1}
	commit := history.PushCommit{Repository: "acme/api", After: pushShaAfter, SHA: pushShaCommit,
		Author: "acme-dev", AuthoredAt: push.PushedAt.Add(-25 * time.Minute), FirstParent: true, Parents: 1}
	dir := filepath.Dir(data)
	if _, err := history.AppendPushes(filepath.Join(dir, "pushes.csv"), []history.Push{push}); err != nil {
		t.Fatal(err)
	}
	commits := filepath.Join(dir, "push_commits.csv")
	if _, err := history.AppendPushCommits(commits, []history.PushCommit{commit}); err != nil {
		t.Fatal(err)
	}
}

// pushData is withHistory of the history at data for pushesProject.
func pushData(t *testing.T, data string) page.Data {
	t.Helper()
	got, err := withHistory(page.Data{}, pushesProject(), data, time.Date(2026, 10, 3, 12, 0, 0, 0, time.UTC))
	if err != nil {
		t.Fatal(err)
	}
	return got
}

// TestRenderReadsThePushMeasuresBesideTheHistory: with pushes.csv and
// push_commits.csv beside --data, the page data carries the push measures of
// each project (one commit, 25 min to main) and its deployment measures, in
// the config's order.
func TestRenderReadsThePushMeasuresBesideTheHistory(t *testing.T) {
	data := writeHistory(t, acmeHistory())
	writePushes(t, data)
	got := pushData(t, data)
	if len(got.TbdMetrics) != 1 || got.TbdMetrics[0].Deploy.Project != "Acme Shop" {
		t.Fatalf("want a row per project, got %+v", got.TbdMetrics)
	}
	want := metrics.PushMeasures{Project: "Acme Shop", Pushes: 1, Commits: 1, Direct: 1,
		TimeToMain: metrics.DurationSpread{Count: 1, Mean: 25 * time.Minute},
		PerPush:    metrics.CountSpread{Count: 1, Mean: 1}}
	if got.TbdMetrics[0].Push != want {
		t.Errorf("want %+v, got %+v", want, got.TbdMetrics[0].Push)
	}
}

// TestRenderSaysThePushesAreUncollectedWithoutAPushesFile: no pushes.csv is
// its own state, never a fallback to deployments.
func TestRenderSaysThePushesAreUncollectedWithoutAPushesFile(t *testing.T) {
	got := pushData(t, writeHistory(t, acmeHistory()))
	if push := got.TbdMetrics[0].Push; !push.Uncollected || push.Commits != 0 {
		t.Errorf("want uncollected with no commit, got %+v", push)
	}
}

// TestRenderSaysThePushesAreNotReadableForARefusedRepository: a line of
// pushes_denied.csv, written in another case, makes the project not readable.
func TestRenderSaysThePushesAreNotReadableForARefusedRepository(t *testing.T) {
	data := writeHistory(t, acmeHistory())
	writePushes(t, data)
	denied := pushesDeniedH2 + "ACME/Api,2026-10-01T00:00:00Z,FORSGREN_TOKEN\n"
	if err := os.WriteFile(filepath.Join(filepath.Dir(data), "pushes_denied.csv"), []byte(denied), 0o600); err != nil {
		t.Fatal(err)
	}
	if push := pushData(t, data).TbdMetrics[0].Push; !push.NotReadable || push.Uncollected {
		t.Errorf("want not readable alone, got %+v", push)
	}
}

// TestRenderRefusesABadPushFile: a malformed or unknown-version pushes file,
// push commits file or pushes denied file fails render with its own message,
// naming it, as the other data files do; never read as none.
func TestRenderRefusesABadPushFile(t *testing.T) {
	wantBadFileRefused(t, "pushes.csv", map[string]badFile{
		"unknown version": {"# forsgren pushes v2\n", "unknown history format version"},
		"malformed line":  {pushesHead + "acme/api,2026-10-02T10:00:00Z\n", "line 3: malformed history"},
	})
	wantBadFileRefused(t, "push_commits.csv", map[string]badFile{
		"unknown version": {"# forsgren push commits v3\n", "unknown history format version"},
		"malformed line":  {pushCommitsH + "acme/api,x\n", "line 3: malformed history"},
	})
	wantBadFileRefused(t, "pushes_denied.csv", map[string]badFile{
		"unknown version": {"# forsgren pushes denied v3\n", "unknown history format version"},
		"malformed line":  {pushesDeniedH + "acme/api\n", "line 3: malformed history"},
		"a token value":   {pushesDeniedH2 + "acme/api,2026-10-01T00:00:00Z,ghp_abc\n", "line 3: malformed history"},
	})
}

// TestRenderShowsThePushGroupsAndTheirStatesOnTheTbdPage (forsgren#397, step
// 5): with the pushes beside --data, Acme Shop's row has its commits and
// pushes, the shares, 25 m to main from one commit and, for lack of a
// second value, dashes for the median and p90; Acme Tools, with no push, 0
// commits and dashes for the shares; without pushes.csv every project says the
// pushes are not collected yet; a refused repository says its push activity is
// not readable, never deployment numbers in its place.
func TestRenderShowsThePushGroupsAndTheirStatesOnTheTbdPage(t *testing.T) {
	pinNow(t)
	data := writeData(t, acmeHistory(), acmeCommits())
	wantIn(t, tbdSiteOf(t, validConfig, data), pushesNotCollected(3), pushesNotCollected(4))
	writePushes(t, data)
	got := tbdSiteOf(t, validConfig, data)
	wantIn(t, got, tdRow("25 m", "-", "-")+"\n            "+
		`<td colspan="3">No pull requests have been collected yet</td>`+"\n            "+
		`<td colspan="3">No pull requests have been collected yet</td>`+"\n            "+shopTimes,
		tdRow("1", "1", "12", "1", "-", "-", "1", "-", "-", "100%", "0%", "0%", "0%", "0"),
		tdRow("0", "0", "0", "-", "-", "-", "-", "-", "-", "-", "-", "-", "-", "-"))
	if strings.Contains(got, "Pushes not collected yet") {
		t.Errorf("want no state with the pushes collected, got:\n%s", got)
	}
	denied := pushesDeniedH + "ACME/Api,2026-10-01T00:00:00Z\n"
	if err := os.WriteFile(filepath.Join(filepath.Dir(data), "pushes_denied.csv"), []byte(denied), 0o600); err != nil {
		t.Fatal(err)
	}
	wantIn(t, tbdSiteOf(t, validConfig, data),
		`<td colspan="3">Push activity not readable</td>`, `<td colspan="4">Push activity not readable</td>`)
}
