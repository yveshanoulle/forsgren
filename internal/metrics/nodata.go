package metrics

// NoData says whether a project has no data in the DORA window
// (forsgren#394, step 3, decisions #433 and #442): no deployed commit, no
// final deployment (a failed one included), no push and no merged pull
// request, a bot's included. Any one of them keeps the project's row a data
// row, a single measure without a value showing its dash.
func NoData(volume DeploymentVolume, deploy DeployMeasures, push PushMeasures, lead PRLeadTime) bool {
	return volume.Count == 0 && volume.Final == 0 && deploy.Commits == 0 && push.Pushes == 0 &&
		lead.PullRequests == 0 && lead.Bots == 0
}

// ServiceNoData says whether a service has no data in the DORA window
// (forsgren#422, step 3, decision #451, A): no final deployment, a failed one
// included, and no deployed commit. Pushes and pull requests name no service,
// so they do not count.
func ServiceNoData(volume DeploymentVolume, deploy DeployMeasures) bool {
	return volume.Count == 0 && volume.Final == 0 && deploy.Commits == 0
}
