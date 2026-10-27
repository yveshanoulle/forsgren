package page

import "testing"

// TestLegendSaysPushedCommitsFromDeployedCommits (forsgren#513): Volume names
// four numbers, and the legend tells Commits (pushed to main) from Deployed
// commits (delivered by deployments of the window), each commit counted once.
func TestLegendSaysPushedCommitsFromDeployedCommits(t *testing.T) {
	wantAll(t, "legend.html", rendered(t, "legend.html", calculated()),
		"Volume shows four numbers.",
		"Commits is the number of commits the pushes of the window brought to the main branch",
		"Deployed commits is the number of distinct commits that the deployments of the window delivered. "+
			"A commit counts once, at its first deployment in the window, however many deployments or services carry it.",
		"Commits are pushed commits and Deployed commits are deployed commits:")
}
