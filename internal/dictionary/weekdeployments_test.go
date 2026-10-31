package dictionary

import "testing"

// TestTheDeploymentsEntrySaysTheWeekPageCountsFailedToo (forsgren#601): the
// Week page counts its Deployments and Deploys shares over the successful plus
// the failed deployments, other states left out, while every other page
// counts the successful ones, so the entry says both.
func TestTheDeploymentsEntrySaysTheWeekPageCountsFailedToo(t *testing.T) {
	e := entryNamed(t, "Deployments")
	for _, phrase := range unsaid(e.Definition, []string{"the successful deployments.",
		"on the week page", "successful and the failed", "another way are left out"}) {
		t.Errorf("want the definition to say %q, got %q", phrase, e.Definition)
	}
}
