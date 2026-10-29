package page

import (
	"bytes"
	"flag"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// testVersion is the forsgren version the tests render pages as: fixed, so a
// release changes no test and no golden (forsgren#237); newerVersion is the
// next patch release after it, from which the newer-release examples derive.
const testVersion = "9.9.9"

func newerVersion() string {
	parts := strings.Split(testVersion, ".")
	patch, err := strconv.Atoi(parts[2])
	if err != nil {
		panic(err)
	}
	return parts[0] + "." + parts[1] + "." + strconv.Itoa(patch+1)
}

// -update rewrites the golden files from the current output. Use it only
// after reading the diff the failing golden test printed.
var update = flag.Bool("update", false, "rewrite testdata/*.golden.html")

// calculated is the placeholder page data, calculated at 2026-10-03 12:00
// UTC, that the golden pages start from.
// footerReport is the footer's last sentence of calculated(): the calculated-at
// time and the report period of the 30-day window (forsgren#542).
const footerReport = "Calculated at 2026-10-03 12:00 UTC Report Start 2026-09-03 12:00 Report End 2026-10-03 12:00</p>"

func calculated() Data {
	data := Placeholder(testVersion)
	data.AsOf = "2026-10-03 12:00"
	data.ReportStart, data.ReportEnd = "2026-09-03 12:00", "2026-10-03 12:00"
	return data
}

// acmeProjects is the page data of two projects counted back from
// 2026-10-03 12:00 UTC (forsgren#38: one table, a row per project): Acme
// Shop with deployments, the lead time shop, the recovery time recovery
// and the change fail rate changeFail; Acme Tools with one failed
// deployment and nothing else, the worst case, shown in full (Yves's ruling
// on decision #35).
func acmeProjects(shop metrics.LeadTime, recovery metrics.Recovery, changeFail metrics.ChangeFailRate,
	rework metrics.ReworkRate,
) Data {
	data := calculated()
	latest := time.Date(2026, 10, 1, 9, 30, 0, 0, time.UTC)
	frequency := metrics.Frequency{
		Project: "Acme Shop", Last7: 3, InWindow: 12, Last180: 12, WeekendInWindow: 3, Latest: latest,
		Band: metrics.DailyToWeekly,
	}
	data.Rows = Table([]metrics.Row{
		{Level: metrics.ProjectRow, Name: "Acme Shop", Frequency: frequency, LeadTime: shop, Recovery: recovery,
			ChangeFail: changeFail, Rework: rework},
		{Level: metrics.ProjectRow, Name: "Acme Tools", Frequency: metrics.Frequency{Band: metrics.LessThanSixMonthly},
			Recovery: metrics.Recovery{Unrecovered: 1}, ChangeFail: metrics.ChangeFailRate{
				Deployments: 1, FailedDeployments: 1, Failed: 1, Band: metrics.HundredPercent,
			}},
	})
	return data
}

// unrecovered is Acme Shop's recovery time in acmeProjects' pages: one
// failure, not recovered yet.
var unrecovered = metrics.Recovery{Unrecovered: 1}

// oneFailed is Acme Shop's change fail rate in acmeProjects' pages: 1
// failed deployment of 13 (forsgren#18).
var oneFailed = metrics.ChangeFailRate{Deployments: 13, FailedDeployments: 1, Failed: 1, Band: metrics.ZeroPercent}

// noRework is Acme Shop's deployment rework rate in acmeProjects' pages
// unless a test sets another (forsgren#39): none of its 12 successful
// deployments is rework.
var noRework = metrics.ReworkRate{Deployments: 12, Band: metrics.ZeroPercent}

// acmeTable is acmeProjects with Acme Shop's usual numbers: no lead time,
// unrecovered, oneFailed and noRework.
func acmeTable() Data {
	return acmeProjects(metrics.LeadTime{}, unrecovered, oneFailed, noRework)
}

// checkGolden renders index.html with data and compares it with the golden
// file, rewriting it first under -update.
func checkGolden(t *testing.T, golden string, data Data) {
	t.Helper()
	checkPageGolden(t, "index.html", golden, data)
}

// checkPageGolden is checkGolden for the named page.
func checkPageGolden(t *testing.T, name, golden string, data Data) {
	t.Helper()
	var got bytes.Buffer
	if err := Render(&got, name, data); err != nil {
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
		t.Errorf("%s differs from %s\n--- got ---\n%s\n--- want ---\n%s", name, golden, got.String(), want)
	}
}

// rendered is the page name rendered with data, less the links to the
// dictionary's entries the legend carries (entryLink, forsgren#370 step 3), so
// the wording tests read the sentences as written.
func rendered(t *testing.T, name string, data Data) string {
	t.Helper()
	var got bytes.Buffer
	if err := Render(&got, name, data); err != nil {
		t.Fatalf("Render %s: %v", name, err)
	}
	return entryLink.ReplaceAllString(got.String(), "$1")
}

// wantOnEveryPage fails for each page of PageNames, rendered with data, that
// lacks one of texts.
func wantOnEveryPage(t *testing.T, data Data, texts ...string) {
	t.Helper()
	for _, name := range PageNames() {
		wantAll(t, name, rendered(t, name, data), texts...)
	}
}

// wantOnNoPage fails for each page of PageNames, rendered with data, that
// holds one of texts.
func wantOnNoPage(t *testing.T, data Data, texts ...string) {
	t.Helper()
	for _, name := range PageNames() {
		wantNone(t, name, rendered(t, name, data), texts...)
	}
}
