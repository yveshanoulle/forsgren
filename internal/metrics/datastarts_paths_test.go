package metrics

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// The Commits of a service or rule row (forsgren#589, step 5, Yves's
// rulings): with paths, the oldest author date over its deployed commits that
// touch its paths and the pushed commits that touch them, marked as earlier
// data not yet read while a repository of the row has its pushed commits'
// files still being read; without paths, Per repository.

// apiWithPushes is the API row of startsData with acme/app's pushed commits:
// p1, authored 22 September, touches api/; p2, authored 1 September, touches
// docs/ only; p3, authored 2 September, has no files read yet. The deployed
// c1 of 18 September is no longer the oldest only when a pushed commit that
// touches api/ is older. mark sets the push files mark.
func apiWithPushes(t *testing.T, mark history.Reach) DataRow {
	t.Helper()
	data, events := startsData()
	data.PushCommits = []history.PushCommit{
		{Repository: "acme/app", After: "a9", SHA: "p1", AuthoredAt: utc(time.September, 22, 8, 0)},
		{Repository: "acme/app", After: "a9", SHA: "p2", AuthoredAt: utc(time.September, 1, 8, 0)},
		{Repository: "acme/app", After: "a9", SHA: "p3", AuthoredAt: utc(time.September, 2, 8, 0)},
		{Repository: "acme/web", After: "a7", SHA: "p4", AuthoredAt: utc(time.August, 1, 8, 0)},
	}
	data.Commits[0].AuthoredAt = utc(time.September, 23, 8, 0)
	data.CommitFiles = append(data.CommitFiles,
		history.CommitFile{Repository: "ACME/App", SHA: "p1", Path: "api/z.go"},
		history.CommitFile{Repository: "acme/app", SHA: "p2", Path: "docs/api.md"},
		history.CommitFile{Repository: "acme/web", SHA: "p4", Path: "api/w.go"})
	data.PushFilesFilled = mark
	return startsRow(t, DataStartsOf(weekProjects(), data, events, now), "API")
}

// TestAServiceRowWithPathsCountsThePushedCommitsThatTouchThem: the pushed p1
// that touches api/ is older than the deployed c1, so it is the API's
// Commits; p2 (other paths), p3 (unread) and acme/web's p4 do not count, and
// with the push files mark the date is not marked.
func TestAServiceRowWithPathsCountsThePushedCommitsThatTouchThem(t *testing.T) {
	api := apiWithPushes(t, history.Reach{"Acme/App": utc(time.October, 1, 0, 0)})
	wantStart(t, "API commits", api.Commits, utc(time.September, 22, 8, 0))
	if api.Commits.Cut {
		t.Errorf("want the API's commits not marked with every pushed commit read, got %+v", api.Commits)
	}
}

// TestAServiceRowWithPathsCountsOnlyTheDeployedCommitsThatTouchThem: c2,
// deployed by the API's deployment but touching admin/ only, does not count,
// though it is the API's oldest deployed commit.
func TestAServiceRowWithPathsCountsOnlyTheDeployedCommitsThatTouchThem(t *testing.T) {
	data, events := startsData()
	data.Commits[1].DeploymentID, data.Commits[1].AuthoredAt = 1, utc(time.September, 10, 8, 0)
	api := startsRow(t, DataStartsOf(weekProjects(), data, events, now), "API")
	wantStart(t, "API commits", api.Commits, utc(time.September, 18, 8, 0))
}

// TestAServiceRowIsMarkedWhileItsPushedCommitsAreBeingRead: without the push
// files mark of acme/app, the API's Commits says earlier data is not yet read.
func TestAServiceRowIsMarkedWhileItsPushedCommitsAreBeingRead(t *testing.T) {
	api := apiWithPushes(t, nil)
	wantStart(t, "API commits", api.Commits, utc(time.September, 22, 8, 0))
	if !api.Commits.Cut {
		t.Errorf("want the API's commits marked while pushed commits are being read, got %+v", api.Commits)
	}
}

// TestAServiceRowWithoutPathsHasItsCommitsPerRepository: ADMIN has no paths,
// so no commit can be told to be its own.
func TestAServiceRowWithoutPathsHasItsCommitsPerRepository(t *testing.T) {
	data, events := startsData()
	admin := startsRow(t, DataStartsOf(weekProjects(), data, events, now), "ADMIN")
	if !admin.Commits.PerRepository || admin.Commits.Stored() {
		t.Errorf("want ADMIN's commits Per repository, got %+v", admin.Commits)
	}
}
