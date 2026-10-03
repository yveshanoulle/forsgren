package page

import (
	"bytes"
	"flag"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// -update rewrites the golden files from the current output. Use it only
// after reading the diff the failing golden test printed.
var update = flag.Bool("update", false, "rewrite testdata/*.golden.html")

func TestPlaceholderMatchesGolden(t *testing.T) {
	checkGolden(t, "testdata/index.golden.html", Placeholder("0.0.5"))
}

// TestNoProjectsPageMatchesGolden (forsgren#12): the page of an installation
// whose config lists no projects says so, besides its version.
func TestNoProjectsPageMatchesGolden(t *testing.T) {
	data := Placeholder("0.0.5")
	data.NoProjects = true
	checkGolden(t, "testdata/index.no-projects.golden.html", data)
}

// acmeProjects is the page data of two projects counted back from
// 2026-10-03 12:00 UTC: Acme Shop with deployments, the lead time shop, the
// recovery time recovery and the change fail rate changeFail, Acme Tools
// with no deployment.
func acmeProjects(shop metrics.LeadTime, recovery metrics.Recovery, changeFail metrics.ChangeFailRate) Data {
	data := Placeholder("0.0.5")
	data.AsOf = "2026-10-03 12:00"
	latest := time.Date(2026, 10, 1, 9, 30, 0, 0, time.UTC)
	shop.Project, recovery.Project, changeFail.Project = "Acme Shop", "Acme Shop", "Acme Shop"
	frequency := metrics.Frequency{Project: "Acme Shop", Last7: 3, Last30: 12, Latest: latest, Band: metrics.DailyToWeekly}
	data.Projects = []Project{
		{Frequency: frequency, LeadTime: shop, Recovery: recovery, ChangeFail: changeFail},
		{Frequency: metrics.Frequency{Project: "Acme Tools"}, LeadTime: metrics.LeadTime{Project: "Acme Tools"}},
	}
	return data
}

// unrecovered is Acme Shop's recovery time in acmeProjects' pages: one
// failure, not recovered yet.
var unrecovered = metrics.Recovery{Unrecovered: 1}

// oneFailed is Acme Shop's change fail rate in acmeProjects' pages: 1
// failed deployment of 13 (forsgren#18).
var oneFailed = metrics.ChangeFailRate{Deployments: 13, FailedDeployments: 1, Failed: 1, Band: metrics.ZeroPercent}

// TestFrequencyPageMatchesGolden (forsgren#12, step 7): with projects the
// page shows a section per project, in the given order, with its numbers,
// its latest date and its band, or "No deployments recorded yet"; a project
// with deployments but no commit in the window says "No lead time yet"
// (forsgren#16, step 5).
func TestFrequencyPageMatchesGolden(t *testing.T) {
	checkGolden(t, "testdata/index.frequency.golden.html", acmeProjects(metrics.LeadTime{}, unrecovered, oneFailed))
}

// TestLeadTimePageMatchesGolden (forsgren#16, step 5): a project's section
// shows its lead time for changes, the band with the median, the count and
// the period, next to its deployment frequency.
func TestLeadTimePageMatchesGolden(t *testing.T) {
	shop := metrics.LeadTime{Commits: 3, Median: 17 * time.Minute, Band: metrics.LessThanOneHour}
	checkGolden(t, "testdata/index.leadtime.golden.html", acmeProjects(shop, unrecovered, oneFailed))
}

// TestRecoveryPageMatchesGolden (forsgren#17): a project's section shows
// its failed deployment recovery time, the band with the median, the count,
// the period and the failures not recovered yet, after its lead time; the
// bands paragraph covers the recovery bands.
func TestRecoveryPageMatchesGolden(t *testing.T) {
	recovery := metrics.Recovery{Recoveries: 2, Median: 3 * time.Hour, Band: metrics.LessThanOneDay, Unrecovered: 1}
	threeFailed := metrics.ChangeFailRate{Deployments: 15, FailedDeployments: 3, Failed: 3, Band: metrics.TwentyPercent}
	checkGolden(t, "testdata/index.recovery.golden.html", acmeProjects(metrics.LeadTime{}, recovery, threeFailed))
}

// TestChangeFailPageMatchesGolden (forsgren#18): a project's section shows
// its change fail rate, the band with the rate, the deployments and both
// counts, after its recovery time; the bands paragraph covers the change
// fail rate bands.
func TestChangeFailPageMatchesGolden(t *testing.T) {
	changeFail := metrics.ChangeFailRate{
		Deployments: 13, FailedDeployments: 1, FailureIssues: 2, Failed: 2, Band: metrics.TwentyPercent,
	}
	checkGolden(t, "testdata/index.changefail.golden.html", acmeProjects(metrics.LeadTime{}, unrecovered, changeFail))
}

// TestNoDataPageMatchesGolden: projects with no deployment recorded yet
// each say so.
func TestNoDataPageMatchesGolden(t *testing.T) {
	data := Placeholder("0.0.5")
	data.AsOf = "2026-10-03 12:00"
	data.Projects = []Project{
		{Frequency: metrics.Frequency{Project: "Acme Shop"}, LeadTime: metrics.LeadTime{Project: "Acme Shop"}},
		{Frequency: metrics.Frequency{Project: "Acme Tools"}, LeadTime: metrics.LeadTime{Project: "Acme Tools"}},
	}
	checkGolden(t, "testdata/index.no-data.golden.html", data)
}

// checkGolden renders index.html with data and compares it with the golden
// file, rewriting it first under -update.
func checkGolden(t *testing.T, golden string, data Data) {
	t.Helper()
	var got bytes.Buffer
	if err := Render(&got, "index.html", data); err != nil {
		t.Fatalf("Render: %v", err)
	}
	if *update {
		if err := os.WriteFile(golden, got.Bytes(), 0o600); err != nil {
			t.Fatalf("update golden: %v", err)
		}
	}
	want, err := os.ReadFile(filepath.Clean(golden))
	if err != nil {
		t.Fatalf("read golden: %v", err)
	}
	if !bytes.Equal(got.Bytes(), want) {
		t.Errorf("index.html differs from %s\n--- got ---\n%s\n--- want ---\n%s", golden, got.String(), want)
	}
}

func TestRenderEscapesFields(t *testing.T) {
	var got bytes.Buffer
	data := Data{Title: "forsgren", Message: `<script>alert("x")</script>`}
	if err := Render(&got, "index.html", data); err != nil {
		t.Fatalf("Render: %v", err)
	}
	if strings.Contains(got.String(), "<script>") {
		t.Errorf("a <script> in a field reached the page unescaped:\n%s", got.String())
	}
	if !strings.Contains(got.String(), "&lt;script&gt;") {
		t.Errorf("want the field escaped as &lt;script&gt;, got:\n%s", got.String())
	}
}

func TestRenderUnknownPage(t *testing.T) {
	err := Render(&bytes.Buffer{}, "missing.html", Placeholder("0.0.5"))
	if err == nil || !strings.Contains(err.Error(), "missing.html") {
		t.Errorf("want an error naming missing.html, got %v", err)
	}
}

func TestWriteSiteWritesOnePageAndStyles(t *testing.T) {
	dir := t.TempDir()
	n, err := WriteSite(dir, Placeholder("0.0.5"))
	if err != nil {
		t.Fatalf("WriteSite: %v", err)
	}
	if n != 1 {
		t.Errorf("want 1 page written, got %d", n)
	}
	for _, name := range []string{"index.html", "styles.css"} {
		if _, err := os.Stat(filepath.Join(dir, name)); err != nil {
			t.Errorf("want %s in the site: %v", name, err)
		}
	}
}

func TestWriteSiteFailsWhenDirIsAFile(t *testing.T) {
	file := filepath.Join(t.TempDir(), "not-a-dir")
	if err := os.WriteFile(file, []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	if n, err := WriteSite(file, Placeholder("0.0.5")); err == nil {
		t.Errorf("want an error when the output is a regular file, got %d pages", n)
	}
}
