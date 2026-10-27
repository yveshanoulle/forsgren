package collect

import (
	"errors"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// sampleReport is a report with every kind of line.
func sampleReport() Report {
	return Report{
		Cuts: []Cut{
			{"acme/app", time.Date(2026, 6, 22, 0, 0, 0, 0, time.UTC), RecentRead, ProgressYes},
			{"acme/docs", time.Time{}, RecentDiscarded, ProgressStalled},
		},
		PullsCut:       []string{"acme/shop"},
		BackfillCut:    []string{"acme/lib"},
		PushesCut:      []string{"acme/api"},
		PullFillCut:    []string{"acme/fill"},
		PushFillCut:    []string{"acme/fill"},
		PullBotFillCut: []string{"acme/fill"},
		FilesCut:       []string{"acme/svc"},
		ServiceUnmatched: []UnmatchedService{
			{"acme/app", 43, ServiceUnknown, "Web shop"}, {"acme/api", 7, ServiceAmbiguous, "Web"},
		},
		Failed: []Failed{{"acme/web", FailedSecondary}},
		Reset:  time.Date(2026, 10, 1, 1, 0, 0, 0, time.UTC),
	}
}

const sampleText = "# forsgren collect report v1\n" +
	"incomplete resets=2026-10-01T01:00:00Z\n" +
	"cut acme/app kept=2026-06-22 recent=read issues=unread progress=yes\n" +
	"cut acme/docs kept=none recent=discarded issues=unread progress=stalled\n" +
	"pulls-cut acme/shop\n" +
	"backfill-cut acme/lib\n" +
	"pushes-cut acme/api\n" +
	"pull-commits-fill-cut acme/fill\n" +
	"push-commits-fill-cut acme/fill\n" +
	"pulls-bot-fill-cut acme/fill\n" +
	"commit-files-cut acme/svc\n" +
	"failure-service acme/app 43 unknown Web+shop\n" +
	"failure-service acme/api 7 ambiguous Web\n" +
	"failed acme/web secondary-rate-limit\n"

// TestAReportIsWrittenAsItsFileAndReadBack (forsgren#64, step 3b): the file
// says complete or incomplete with the reset time, one line per repository cut
// short, whose pull requests alone were cut short (forsgren#320, decision
// #307), or failed, and reads back as it was written.
func TestAReportIsWrittenAsItsFileAndReadBack(t *testing.T) {
	if got := sampleReport().Render(); got != sampleText {
		t.Errorf("want\n%q\ngot\n%q", sampleText, got)
	}
	back, err := ParseReport(sampleText)
	if err != nil || back.Render() != sampleText {
		t.Errorf("want the report back, got %v (%v)", back, err)
	}
	if got := (Report{}).Render(); got != "# forsgren collect report v1\ncomplete\n" {
		t.Errorf("want a complete report, got %q", got)
	}
}

// TestAReportIsIncompleteForOneKindOfCutAlone: a repository whose pull
// requests alone (forsgren#320), or whose backfill of the legacy commits alone
// (forsgren#385), the budget cut short makes the report incomplete, with the
// reset time, and nothing else in it.
func TestAReportIsIncompleteForOneKindOfCutAlone(t *testing.T) {
	reset := time.Date(2026, 10, 1, 1, 0, 0, 0, time.UTC)
	head := "# forsgren collect report v1\nincomplete resets=2026-10-01T01:00:00Z\n"
	for line, r := range map[string]Report{
		"pulls-cut acme/app\n":             {PullsCut: []string{"acme/app"}, Reset: reset},
		"backfill-cut acme/app\n":          {BackfillCut: []string{"acme/app"}, Reset: reset},
		"pushes-cut acme/app\n":            {PushesCut: []string{"acme/app"}, Reset: reset},
		"pull-commits-fill-cut acme/app\n": {PullFillCut: []string{"acme/app"}, Reset: reset},
		"push-commits-fill-cut acme/app\n": {PushFillCut: []string{"acme/app"}, Reset: reset},
		"pulls-bot-fill-cut acme/app\n":    {PullBotFillCut: []string{"acme/app"}, Reset: reset},
		"commit-files-cut acme/app\n":      {FilesCut: []string{"acme/app"}, Reset: reset},
	} {
		if got := r.Render(); got != head+line {
			t.Errorf("want\n%q\ngot\n%q", head+line, got)
		}
	}
}

// TestAFileThatIsNoReportIsRefused: another first line, another status, a
// cut line that lacks a field or has a bad date, and any other line are
// ErrReport.
func TestAFileThatIsNoReportIsRefused(t *testing.T) {
	head := "# forsgren collect report v1\n"
	for name, text := range map[string]string{
		"empty":           "",
		"another file":    "repository,reach\n",
		"no status":       head,
		"bad status":      head + "done\n",
		"bad reset":       head + "incomplete resets=soon\n",
		"short cut":       head + "complete\ncut acme/app kept=none\n",
		"wrong key":       head + "complete\ncut acme/app since=none recent=read issues=unread progress=yes\n",
		"bad date":        head + "complete\ncut acme/app kept=June recent=read issues=unread progress=yes\n",
		"another line":    head + "complete\nnote hello\n",
		"short failure":   head + "complete\nfailed acme/web\n",
		"short pulls":     head + "complete\npulls-cut\n",
		"an empty line":   head + "complete\n\nfailed acme/web error\n",
		"long pulls":      head + "complete\npulls-cut acme/app kept=none\n",
		"short backfill":  head + "complete\nbackfill-cut\n",
		"long backfill":   head + "complete\nbackfill-cut acme/app kept=none\n",
		"short pushes":    head + "complete\npushes-cut\n",
		"long pushes":     head + "complete\npushes-cut acme/app kept=none\n",
		"short pull fill": head + "complete\npull-commits-fill-cut\n",
		"long pull fill":  head + "complete\npull-commits-fill-cut acme/app kept=none\n",
		"short push fill": head + "complete\npush-commits-fill-cut\n",
		"long push fill":  head + "complete\npush-commits-fill-cut acme/app kept=none\n",
		"short bot fill":  head + "complete\npulls-bot-fill-cut\n",
		"long bot fill":   head + "complete\npulls-bot-fill-cut acme/app kept=none\n",
		"short files cut": head + "complete\ncommit-files-cut\n",
		"long files cut":  head + "complete\ncommit-files-cut acme/app kept=none\n",
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := ParseReport(text); !errors.Is(err, ErrReport) {
				t.Errorf("want ErrReport, got %v", err)
			}
		})
	}
}

// TestAReportFileThatIsMissingIsAnError: ReadReport leaves "unknown" to its
// caller.
func TestAReportFileThatIsMissingIsAnError(t *testing.T) {
	if _, err := ReadReport(historyPath(t)); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want a missing file, got %v", err)
	}
}

// wantReport fails unless the run's report is want, line for line.
func wantReport(t *testing.T, g *gitHub, want Report) {
	t.Helper()
	if got := g.report.Render(); got != want.Render() {
		t.Errorf("want the report\n%s\ngot\n%s", want.Render(), got)
	}
}

// wantCutRuns fails unless cut_runs.csv holds a row for acme/app exactly
// when want says so.
func wantCutRuns(t *testing.T, path string, want bool) {
	t.Helper()
	marks, err := history.LoadCutRuns(cutRunsFileOf(path))
	if _, has := marks["acme/app"]; err != nil || has != want {
		t.Errorf("want a cut_runs.csv row for acme/app %v, got %v (%v)", want, marks, err)
	}
}

// cutRunsFileOf is cut_runs.csv next to the history at path.
func cutRunsFileOf(path string) string { return filepath.Join(filepath.Dir(path), CutRunsFile) }

// TestTheReportNamesWhatACutKept: the cut in the middle of day 3 keeps days
// 1 and 2: the report says the read mark moved to day 2, the recent read was
// read whole, the repository progressed, and when the budget resets; and a
// repository that progressed leaves no cut_runs.csv row.
func TestTheReportNamesWhatACutKept(t *testing.T) {
	g, path := busyGitHub(t)
	g.allow = 11
	g.collect(t, shopWithChunks(), path, github.DefaultMaxPages)
	wantReport(t, g, Report{Cuts: []Cut{{"acme/app", ago(102), RecentRead, ProgressYes}}, Reset: g.resetAt})
	wantCutRuns(t, path, false)
}

// TestARepositoryThatKeepsNothingEveryRunIsNotProgressing (decision #239): the
// first run that keeps no day notes it in cut_runs.csv and says progress no;
// the next one says stalled and keeps the first date; a run that completes
// the repository takes the row away and the report says complete.
func TestARepositoryThatKeepsNothingEveryRunIsNotProgressing(t *testing.T) {
	g, path := boundaryGitHub(t)
	g.allow = 1
	g.collect(t, shopWithChunks(), path, github.DefaultMaxPages)
	cut := Cut{"acme/app", time.Time{}, RecentRead, ProgressNo}
	wantReport(t, g, Report{Cuts: []Cut{cut}, Reset: g.resetAt})
	wantCutRuns(t, path, true)
	g.collect(t, shopWithChunks(), path, github.DefaultMaxPages)
	cut.Progress = ProgressStalled
	wantReport(t, g, Report{Cuts: []Cut{cut}, Reset: g.resetAt})
	wantCutRuns(t, path, true)
	g.allow = 0
	g.collect(t, shopWithChunks(), path, github.DefaultMaxPages)
	wantReport(t, g, Report{})
	wantCutRuns(t, path, false)
}

// TestTheReportSaysWhatBecameOfTheRecentRead: a cut recent read that keeps its
// whole days says kept, one that cannot (the next window would not reach what
// was not read) says discarded.
func TestTheReportSaysWhatBecameOfTheRecentRead(t *testing.T) {
	for name, c := range map[string]struct {
		offset time.Duration
		cut    Cut
	}{
		"kept":      {Lookback, Cut{"acme/app", time.Time{}, RecentKept, ProgressYes}},
		"discarded": {Lookback + time.Second, Cut{"acme/app", time.Time{}, RecentDiscarded, ProgressNo}},
	} {
		t.Run(name, func(t *testing.T) {
			g, path := lookbackGitHub(t, ago(20).Add(c.offset))
			g.allow = 2
			g.collect(t, shopWithChunks(), path, github.DefaultMaxPages)
			wantReport(t, g, Report{Cuts: []Cut{c.cut}, Reset: g.resetAt})
		})
	}
}

// TestACutInTheIssueReadIsReportedWithItsDeployments: the deployments are read
// whole, so the recent read is read and the repository progressed.
func TestACutInTheIssueReadIsReportedWithItsDeployments(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(deployment(storedOne, busySha(storedOne), "deploy", ago(5).Format(time.RFC3339)))
	g.bodies[statusesPath("1005")] = list(status(1, "success", ago(5).Format(time.RFC3339)))
	g.allow = 3
	g.collect(t, shopWithChunks(), historyPath(t), github.DefaultMaxPages)
	wantReport(t, g, Report{Cuts: []Cut{{"acme/app", ago(100), RecentRead, ProgressYes}}, Reset: g.resetAt})
}

// TestARateLimitFailureIsInTheReportByWhichLimit: a repository that failed on
// GitHub's primary or secondary limit, or on something else, is a failed line
// with the word for it, and the run stays complete: nothing was cut short.
func TestARateLimitFailureIsInTheReportByWhichLimit(t *testing.T) {
	for name, c := range map[string]struct {
		set  func(g *gitHub)
		kind string
	}{
		"primary": {func(g *gitHub) {
			g.status[deploymentsPath] = http.StatusForbidden
			g.left[deploymentsPath] = 0
		}, FailedPrimary},
		"secondary": {func(g *gitHub) {
			g.status[deploymentsPath] = http.StatusTooManyRequests
			g.limited[deploymentsPath] = true
		}, FailedSecondary},
		"other": {func(g *gitHub) { g.status[deploymentsPath] = http.StatusBadGateway }, FailedOther},
	} {
		t.Run(name, func(t *testing.T) {
			g := newGitHub(t)
			g.bodies[deploymentsPath] = list()
			c.set(g)
			g.collect(t, shopWithChunks(), historyPath(t), github.DefaultMaxPages)
			wantReport(t, g, Report{Failed: []Failed{{"acme/app", c.kind}}})
		})
	}
}

// TestACutRunsFileThatCannotBeReadRefusesTheRun: like the other marks, a
// malformed cut_runs.csv is an error naming it, before GitHub is asked.
func TestACutRunsFileThatCannotBeReadRefusesTheRun(t *testing.T) {
	g := newGitHub(t)
	path := historyPath(t)
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(cutRunsFileOf(path), []byte("not a mark file\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	r := g.collect(t, shopWithChunks(), path, github.DefaultMaxPages)
	if !errors.Is(r.err, history.ErrMalformed) || !strings.Contains(r.err.Error(), CutRunsFile) {
		t.Errorf("want ErrMalformed naming %s, got %v", CutRunsFile, r.err)
	}
}

// TestAReportFileReadsBack: ReadReport reads what Render wrote.
func TestAReportFileReadsBack(t *testing.T) {
	path := filepath.Join(t.TempDir(), "report")
	if err := os.WriteFile(path, []byte(sampleText), 0o600); err != nil {
		t.Fatal(err)
	}
	if got, err := ReadReport(path); err != nil || got.Render() != sampleText {
		t.Errorf("want the sample report, got %v (%v)", got, err)
	}
}

// TestARunNeedsNoReport: without Options.Report a cut repository and a failed
// one are still named on stderr and counted, as before.
func TestARunNeedsNoReport(t *testing.T) {
	g := newGitHub(t)
	cfg := threeRepositories(g)
	g.noReport = true
	g.left["/repos/acme/app/deployments"] = 80
	g.status["/repos/acme/web/deployments"] = http.StatusBadGateway
	r := g.collect(t, cfg, historyPath(t), github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) || !strings.Contains(r.stderr, "cut short: acme/app") {
		t.Errorf("want a failure and acme/app cut short, got %v (stderr %q)", r.err, r.stderr)
	}
}

// TestAnUnmatchedServiceAloneLeavesTheReportComplete (forsgren#515, decision
// #517): the run is whole, the lines are there to read back.
func TestAnUnmatchedServiceAloneLeavesTheReportComplete(t *testing.T) {
	r := Report{ServiceUnmatched: []UnmatchedService{{"acme/app", 43, ServiceUnknown, "Web shop"}}}
	want := "# forsgren collect report v1\ncomplete\nfailure-service acme/app 43 unknown Web+shop\n"
	if got := r.Render(); got != want {
		t.Errorf("want %q, got %q", want, got)
	}
	back, err := ParseReport(want)
	if err != nil || len(back.ServiceUnmatched) != 1 || back.ServiceUnmatched[0] != r.ServiceUnmatched[0] {
		t.Errorf("want the line read back, got %+v, %v", back, err)
	}
}
