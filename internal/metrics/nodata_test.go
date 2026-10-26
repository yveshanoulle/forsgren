package metrics

import "testing"

// TestNoDataNeedsAllFourAbsent (forsgren#394, step 3, decision #433): a
// project has no data in the DORA window only when it has no deployed commit,
// no deployment, no push and no merged pull request; any one of them alone
// keeps its row a data row.
func TestNoDataNeedsAllFourAbsent(t *testing.T) {
	for name, c := range map[string]struct {
		volume DeploymentVolume
		deploy DeployMeasures
		push   PushMeasures
		lead   PRLeadTime
		want   bool
	}{
		"all four absent":           {want: true},
		"a deployed commit alone":   {deploy: DeployMeasures{Commits: 1}, want: false},
		"a deployment alone":        {volume: DeploymentVolume{Count: 1}, want: false},
		"a failed deployment alone": {volume: DeploymentVolume{Final: 1}, want: false},
		"a push alone":              {push: PushMeasures{Pushes: 1}, want: false},
		"a merged human pull alone": {lead: PRLeadTime{PullRequests: 1}, want: false},
		"a merged bot pull alone":   {lead: PRLeadTime{Bots: 1}, want: false},
	} {
		if got := NoData(c.volume, c.deploy, c.push, c.lead); got != c.want {
			t.Errorf("%s: want %v, got %v", name, c.want, got)
		}
	}
}

// TestAServiceHasNoDataWithoutADeploymentOrADeployedCommit (forsgren#422, step
// 3, decision #451): a service has no data when it has no final deployment, a
// failed one included, and no deployed commit; a push or pull request of its
// repository does not count.
func TestAServiceHasNoDataWithoutADeploymentOrADeployedCommit(t *testing.T) {
	for name, c := range map[string]struct {
		volume DeploymentVolume
		deploy DeployMeasures
		want   bool
	}{
		"nothing":                   {want: true},
		"a deployed commit alone":   {deploy: DeployMeasures{Commits: 1}},
		"a deployment alone":        {volume: DeploymentVolume{Count: 1}},
		"a failed deployment alone": {volume: DeploymentVolume{Final: 1}},
	} {
		if got := ServiceNoData(c.volume, c.deploy); got != c.want {
			t.Errorf("%s: want %v, got %v", name, c.want, got)
		}
	}
}
