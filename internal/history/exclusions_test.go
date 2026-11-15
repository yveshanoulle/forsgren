package history

import (
	"reflect"
	"testing"
	"time"
)

// cutOff is the before of the exclusions of these tests.
var cutOff = time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC)

// deployedAs is a deployment id of repository's task, created at at.
func deployedAs(id int64, repository, task string, at time.Time) Record {
	return Record{Repository: repository, Kind: KindEnvironment, Name: "production", ID: id, CreatedAt: at,
		State: StateSuccess, Task: task}
}

// commitOf is a commit of the deployment id of repository.
func commitOf(id int64, repository string) Commit {
	return Commit{Repository: repository, Kind: KindEnvironment, DeploymentID: id}
}

// excludable are deployments of acme/app's task upload before and at cutOff,
// the first a failure, one with the repository in another case, and of another task and another
// repository; with their commits and one of a deployment that is not stored.
func excludable() ([]Record, []Commit) {
	before := cutOff.Add(-time.Second)
	failed := deployedAs(1, "acme/app", "upload", before)
	failed.State = StateFailure
	records := []Record{
		failed, deployedAs(2, "acme/app", "upload", cutOff),
		deployedAs(3, "acme/app", "deploy", before), deployedAs(4, "acme/web", "upload", before),
		deployedAs(5, "Acme/App", "upload", before),
	}
	commits := []Commit{commitOf(1, "acme/app"), commitOf(2, "acme/app"), commitOf(3, "acme/app"),
		commitOf(5, "acme/app"), commitOf(9, "acme/app")}
	return records, commits
}

// TestWithoutExcludedLeavesOutTheTaskBeforeItsTimeWithItsCommits
// (forsgren#667): the deployments of the repository (ignoring case) and task
// created before Before are gone with their commits, in order; the one at
// Before, the other task, the other repository and a commit of a deployment
// that is not stored stay.
func TestWithoutExcludedLeavesOutTheTaskBeforeItsTimeWithItsCommits(t *testing.T) {
	records, commits := excludable()
	gotRecords, gotCommits := WithoutExcluded(records, commits,
		[]Exclusion{{Repository: "acme/app", Task: "upload", Before: cutOff}})
	if want := []Record{records[1], records[2], records[3]}; !reflect.DeepEqual(gotRecords, want) {
		t.Errorf("want deployments 2, 3 and 4, got %+v", gotRecords)
	}
	if want := []Commit{commits[1], commits[2], commits[4]}; !reflect.DeepEqual(gotCommits, want) {
		t.Errorf("want the commits of 2, 3 and the unstored 9, got %+v", gotCommits)
	}
}

// TestWithoutExcludedWithoutBeforeLeavesOutEveryDeploymentOfTheTask: a zero
// Before takes back the task's deployments whatever their time.
func TestWithoutExcludedWithoutBeforeLeavesOutEveryDeploymentOfTheTask(t *testing.T) {
	records, commits := excludable()
	gotRecords, _ := WithoutExcluded(records, commits, []Exclusion{{Repository: "acme/app", Task: "upload"}})
	if want := []Record{records[2], records[3]}; !reflect.DeepEqual(gotRecords, want) {
		t.Errorf("want deployments 3 and 4, got %+v", gotRecords)
	}
}

// TestUnmatchedAreTheExclusionsOfATaskTheRepositoryNeverStored: an exclusion
// whose repository (ignoring case) stored its task at any time matches, even
// with a Before no deployment is older than; the others are unmatched, in
// order.
func TestUnmatchedAreTheExclusionsOfATaskTheRepositoryNeverStored(t *testing.T) {
	records, _ := excludable()
	exclusions := []Exclusion{
		{Repository: "ACME/app", Task: "upload", Before: cutOff.Add(-time.Hour)},
		{Repository: "acme/app", Task: "uplaod"},
		{Repository: "acme/web", Task: "deploy"},
	}
	if got := Unmatched(records, exclusions); !reflect.DeepEqual(got, exclusions[1:]) {
		t.Errorf("want the typo and the other repository's task, got %+v", got)
	}
}
