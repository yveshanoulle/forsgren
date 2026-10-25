package metrics

// NoData says whether a project has no data in the DORA window
// (forsgren#394, step 3, decisions #433 and #442): no deployed commit, no
// final deployment (a failed one included), no push and no merged pull
// request, a bot's included. Any one of them keeps the project's row a data
// row, a single measure without a value showing its dash.
func NoData(volume DeploymentVolume, deploy DeployMeasures, push PushMeasures, lead MainlineLeadTime) bool {
	return volume.Count == 0 && volume.Final == 0 && deploy.Commits == 0 && push.Pushes == 0 &&
		lead.PullRequests == 0 && lead.Bots == 0
}
