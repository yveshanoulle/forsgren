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
		lead   MainlineLeadTime
		want   bool
	}{
		"all four absent":           {want: true},
		"a deployed commit alone":   {deploy: DeployMeasures{Commits: 1}, want: false},
		"a deployment alone":        {volume: DeploymentVolume{Count: 1}, want: false},
		"a failed deployment alone": {volume: DeploymentVolume{Final: 1}, want: false},
		"a push alone":              {push: PushMeasures{Pushes: 1}, want: false},
		"a merged human pull alone": {lead: MainlineLeadTime{PullRequests: 1}, want: false},
		"a merged bot pull alone":   {lead: MainlineLeadTime{Bots: 1}, want: false},
	} {
		if got := NoData(c.volume, c.deploy, c.push, c.lead); got != c.want {
			t.Errorf("%s: want %v, got %v", name, c.want, got)
		}
	}
}
