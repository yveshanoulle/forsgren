package main

import (
	"bytes"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
	"github.com/yveshanoulle/forsgren/internal/page"
)

// The stored deployments a repository excludes (forsgren#667): a task of
// acme/ios-app that recorded test-platform uploads as production deployments.

// uploadTask is the task of the deployments these tests exclude.
const uploadTask = "beta-upload"

// uploaded is a deployment of acme/ios-app's uploadTask in state, created at
// the UTC time at.
func uploaded(id int64, state history.State, at string) history.Record {
	r := shipped(id, "acme/ios-app", state, at)
	r.Task = uploadTask
	return r
}

// withExclusions is validConfig with lines as the exclude list of
// acme/ios-app; no lines is no exclude key.
func withExclusions(lines string) string {
	if lines == "" {
		return validConfig
	}
	line := "        deployment: workflow=testflight.yml\n"
	return strings.Replace(validConfig, line, line+"        exclude:\n"+lines, 1)
}

// allOfUploads is the exclusion of every deployment of uploadTask.
const allOfUploads = "          - task: " + uploadTask + "\n"

// stored is what a test stores: deployments and their commits.
type stored struct {
	records []history.Record
	commits []history.Commit
}

// plus is s with more's records and commits after its own.
func (s stored) plus(more stored) stored {
	return stored{append(slices.Clone(s.records), more.records...), append(slices.Clone(s.commits), more.commits...)}
}

// acmeStored is acmeHistory with acmeCommits: deployments of another task than
// uploadTask, which every exclusion here must keep.
func acmeStored() stored { return stored{acmeHistory(), acmeCommits()} }

// renderedData is the page data render makes at renderNow for validConfig with
// the exclude lines, over s, every repository read back to October 2025, and
// what it wrote on stderr.
func renderedData(t *testing.T, lines string, s stored) (page.Data, string) {
	t.Helper()
	data := writeData(t, s.records, s.commits)
	writeReach(t, data, time.Date(2025, time.October, 1, 0, 0, 0, 0, time.UTC))
	var stderr bytes.Buffer
	o := renderOptions{out: t.TempDir(), config: writeConfig(t, withExclusions(lines)), data: data}
	got, err := pageData(o, renderNow, &stderr)
	if err != nil {
		t.Fatal(err)
	}
	return got, stderr.String()
}

// figure is one metric of the page data.
type figure func(page.Data) any

// acmeShop is Acme Shop's total row, the project of acme/ios-app.
func acmeShop(d page.Data) page.Row { return d.Rows[0] }

// wantLeftOut fails unless excluding lines from kept plus extra gives the
// figure of kept alone: extra must change the figure without the exclusion,
// or the test proves nothing.
func (kept stored) wantLeftOut(t *testing.T, of figure, extra stored, lines string) {
	t.Helper()
	want, _ := renderedData(t, "", kept)
	counted, _ := renderedData(t, "", kept.plus(extra))
	if reflect.DeepEqual(of(counted), of(want)) {
		t.Fatalf("want the extra deployments to change the figure, or this test proves nothing: %+v", of(want))
	}
	got, _ := renderedData(t, lines, kept.plus(extra))
	if !reflect.DeepEqual(of(got), of(want)) {
		t.Errorf("want the excluded deployments left out\n got: %+v\nwant: %+v", of(got), of(want))
	}
}

// uploads are three successful uploads in the DORA window, one stored with
// its repository in another case.
func uploads() stored {
	ok := history.StateSuccess
	other := uploaded(303, ok, "2026-09-22T10:00:00Z")
	other.Repository = "Acme/iOS-App"
	return stored{records: []history.Record{
		uploaded(301, ok, "2026-09-20T10:00:00Z"), uploaded(302, ok, "2026-09-21T10:00:00Z"), other}}
}

// TestExcludedDeploymentsLeaveDeploymentFrequency: every deployment of an
// excluded task is out of the deployment frequency, and the deployments of
// the other task, and of the same task in another repository, stay.
func TestExcludedDeploymentsLeaveDeploymentFrequency(t *testing.T) {
	pinNow(t)
	elsewhere := shipped(304, "acme/api", history.StateSuccess, "2026-09-23T10:00:00Z")
	elsewhere.Task = uploadTask
	kept := acmeStored().plus(stored{records: []history.Record{elsewhere}})
	kept.wantLeftOut(t, func(d page.Data) any { return acmeShop(d).Frequency }, uploads(), allOfUploads)
}

// uploadsWithCommits are two uploads in the DORA window with three commits
// each authored three days before, so their lead times outweigh the 17
// minutes of acmeCommits.
func uploadsWithCommits() stored {
	var s stored
	for i, at := range []string{"2026-09-24T10:00:00Z", "2026-09-25T10:00:00Z"} {
		id := int64(311 + i)
		s.records = append(s.records, uploaded(id, history.StateSuccess, at))
		deployed, _ := time.Parse(time.RFC3339, at)
		for h := range 3 {
			authored := deployed.Add(-72*time.Hour - time.Duration(h)*time.Hour).Format(time.RFC3339)
			s.commits = append(s.commits, shippedWith("acme/ios-app", id, authored, at))
		}
	}
	return s
}

// TestExcludedDeploymentsLeaveLeadTime: the commits of an excluded deployment
// are out of the lead time for changes; those of the other task stay.
func TestExcludedDeploymentsLeaveLeadTime(t *testing.T) {
	pinNow(t)
	acmeStored().wantLeftOut(t, func(d page.Data) any { return acmeShop(d).LeadTime }, uploadsWithCommits(), allOfUploads)
}

// failedUpload is one failed upload in the DORA window.
func failedUpload() stored {
	return stored{records: []history.Record{uploaded(321, history.StateFailure, "2026-09-25T10:00:00Z")}}
}

// TestExcludedDeploymentsLeaveChangeFailRate: a failed deployment of an
// excluded task is neither a deployment nor a failure of the change fail
// rate; the other task's failed deployment stays.
func TestExcludedDeploymentsLeaveChangeFailRate(t *testing.T) {
	pinNow(t)
	acmeStored().wantLeftOut(t, func(d page.Data) any { return acmeShop(d).ChangeFail }, failedUpload(), allOfUploads)
}

// recoveredUpload is a failed upload in the DORA window and the successful one
// two hours later that recovers it.
func recoveredUpload() stored {
	return stored{records: []history.Record{uploaded(331, history.StateFailure, "2026-09-23T10:00:00Z"),
		uploaded(332, history.StateSuccess, "2026-09-23T12:00:00Z")}}
}

// TestExcludedDeploymentsLeaveRecoveryTime: recovery time reads the
// deployments, so a recovery between two excluded deployments is out of it;
// the other task's open run of failures stays.
func TestExcludedDeploymentsLeaveRecoveryTime(t *testing.T) {
	pinNow(t)
	acmeStored().wantLeftOut(t, func(d page.Data) any { return acmeShop(d).Recovery }, recoveredUpload(), allOfUploads)
}

// TestBeforeKeepsTheLaterDeploymentsOfTheTask: with before, only the task's
// deployments created before it are left out; one created at before or later
// counts, in every metric and in History.
func TestBeforeKeepsTheLaterDeploymentsOfTheTask(t *testing.T) {
	pinNow(t)
	ok := history.StateSuccess
	later := stored{records: []history.Record{uploaded(342, ok, "2026-09-21T00:00:00Z"),
		uploaded(343, ok, "2026-09-26T10:00:00Z")}}
	earlier := stored{records: []history.Record{uploaded(341, ok, "2026-09-20T23:59:59Z")}}
	lines := allOfUploads + "            before: 2026-09-21T00:00:00Z\n"
	alone, _ := renderedData(t, "", acmeStored())
	withLater, _ := renderedData(t, "", acmeStored().plus(later))
	if reflect.DeepEqual(acmeShop(alone).Frequency, acmeShop(withLater).Frequency) {
		t.Fatal("want the later uploads to change the frequency, or this test proves nothing")
	}
	acmeStored().plus(later).wantLeftOut(t, func(d page.Data) any { return []any{acmeShop(d).Row, d.History} }, earlier,
		lines)
}

// TestAnExclusionOfAnUnknownTaskWarns: an exclusion whose task no stored
// deployment of its repository has (a typo, or a task of another repository)
// is one warning line on stderr naming the repository and the task, and the
// render goes on; one that matches warns nothing.
func TestAnExclusionOfAnUnknownTaskWarns(t *testing.T) {
	pinNow(t)
	_, stderr := renderedData(t, "          - task: beta-uplaod\n", acmeStored().plus(uploads()))
	want := `render: warning: repository "acme/ios-app": exclude task "beta-uplaod" matches no stored deployment` +
		"; it excludes nothing\n"
	if stderr != want {
		t.Errorf("want the one warning\n%q\ngot\n%q", want, stderr)
	}
	if _, stderr := renderedData(t, allOfUploads, acmeStored().plus(uploads())); stderr != "" {
		t.Errorf("want no warning for a task that is stored, got %q", stderr)
	}
}

// TestExcludedDeploymentsLeaveHistory: the History page counts no excluded
// deployment in any period, and the other task's deployments stay.
func TestExcludedDeploymentsLeaveHistory(t *testing.T) {
	pinNow(t)
	all := uploads().plus(failedUpload()).plus(recoveredUpload())
	acmeStored().wantLeftOut(t, func(d page.Data) any { return d.History }, all, allOfUploads)
}
