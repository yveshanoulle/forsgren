package metrics

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// The deployment measures next to the push measures (forsgren#397, step 4).

// shopDeployMeasures is DeployMeasuresOf for Acme Shop of data.
func shopDeployMeasures(data Data) DeployMeasures { return DeployMeasuresOf(projects, data, now)[0] }

// TestDeployMeasuresTimeEveryCommitOfTheFirstParentChainAndCountPerDeployment:
// over trunkData's five commits of a first-parent chain, the pull request's
// merge commit included (it is its own share now, not left out as for the
// direct column): d1 and d2 20 min, m 0, and the legacy deployment's l1 and
// l2 40 and 60 min at their author date, named; the branch commit p1 is off
// the chain. So 0, 20, 20, 40, 60 min: mean 28 min, median 20 min, no p90
// under ten. The first deployment brought 2 commits to the chain and the pull
// request's 1; the legacy deployment, of unknown lineage, is left out and
// counted apart: mean and median 1.5.
func TestDeployMeasuresTimeEveryCommitOfTheFirstParentChainAndCountPerDeployment(t *testing.T) {
	m := time.Minute
	want := DeployMeasures{Project: "Acme Shop", Commits: 5, ByAuthorDate: 2,
		TimeToDeploy: DurationSpread{Count: 5, Mean: 28 * m, Median: 20 * m},
		Deployments:  2, Legacy: 1, PerDeployment: CountSpread{Count: 2, Mean: 1.5, Median: 1.5}}
	if got := shopDeployMeasures(trunkData()); got != want {
		t.Errorf("want %+v, got %+v", want, got)
	}
}

// TestDeployMeasuresTimeACommitAtItsFirstDeploymentOnly: the same commit
// shipped by two deployments is timed at the earlier one and counted once;
// each deployment brought one commit.
func TestDeployMeasuresTimeACommitAtItsFirstDeploymentOnly(t *testing.T) {
	first := trunkCommit(1, "c1", 3*time.Hour, 30*time.Minute, "base")
	later := first
	later.DeploymentID, later.DeployedAt = 2, now.Add(-time.Hour)
	want := DeployMeasures{Project: "Acme Shop", Commits: 1,
		TimeToDeploy: DurationSpread{Count: 1, Mean: 30 * time.Minute},
		Deployments:  2, PerDeployment: CountSpread{Count: 2, Mean: 1, Median: 1}}
	if got := shopDeployMeasures(Data{Commits: []history.Commit{later, first}}); got != want {
		t.Errorf("want %+v, got %+v", want, got)
	}
}

// TestDeployMeasuresCountTheDeploymentsOfTheWindowOnly: a deployment older
// than the DORA window is left out of both measures.
func TestDeployMeasuresCountTheDeploymentsOfTheWindowOnly(t *testing.T) {
	old := trunkCommit(1, "c1", 31*24*time.Hour, time.Minute, "base")
	got := shopDeployMeasures(Data{Commits: []history.Commit{old}})
	if got != (DeployMeasures{Project: "Acme Shop"}) {
		t.Errorf("want nothing, got %+v", got)
	}
}

// TestDeployMeasuresStartFromTenForAP90: ten deployments of one commit each,
// 1 to 10 minutes old when deployed: p90 is the 9th, 9 min, median 5 min 30 s;
// commits per deployment all 1.
func TestDeployMeasuresStartFromTenForAP90(t *testing.T) {
	var commits []history.Commit
	for i := 1; i <= 10; i++ {
		sha := string(rune('a' + i))
		commits = append(commits, trunkCommit(int64(i), sha, time.Hour, time.Duration(i)*time.Minute, "base"))
	}
	want := DeployMeasures{Project: "Acme Shop", Commits: 10,
		TimeToDeploy: DurationSpread{Count: 10, Mean: 5*time.Minute + 30*time.Second,
			Median: 5*time.Minute + 30*time.Second, P90: 9 * time.Minute},
		Deployments: 10, PerDeployment: CountSpread{Count: 10, Mean: 1, Median: 1, P90: 1}}
	if got := shopDeployMeasures(Data{Commits: commits}); got != want {
		t.Errorf("want %+v, got %+v", want, got)
	}
}

// TestDeployMeasuresGiveEveryProjectARow: acme/cli is Acme Tools'.
func TestDeployMeasuresGiveEveryProjectARow(t *testing.T) {
	c := trunkCommit(1, "c1", time.Hour, time.Minute, "base")
	c.Repository = "ACME/cli"
	got := DeployMeasuresOf(projects, Data{Commits: []history.Commit{c}}, now)
	if len(got) != 2 || [2]int{got[0].Commits, got[1].Commits} != [2]int{0, 1} || got[1].Project != "Acme Tools" {
		t.Errorf("want the commit in Acme Tools alone, got %+v", got)
	}
}
