package installerdoc

import "testing"

// TestUpgraderTellsOfTheServiceLineOfFailureIssues (forsgren#515): when the
// installation has services or deployment rules, step 10 tells the person
// that their failure issues may now carry a service line, and that nothing in
// the config has to change.
func TestUpgraderTellsOfTheServiceLineOfFailureIssues(t *testing.T) {
	wantAll(t, "step 10", upgraderSection(t, "Step 10."),
		"when `forsgren.config.yml` has `services:` or `deployments:`",
		"failure issues may now carry a line `service: <label>`",
		"the label of a service or a deployment rule of the issue's repository as the page shows it",
		"counts in that row as well as in the total",
		"no change to `forsgren.config.yml` is needed")
}
