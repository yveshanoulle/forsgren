package metrics

// The cells of the numbers view (forsgren#46): each metric's number only,
// no band; "-" where there is no number.

// NumberCell is the successful deployments of the last 30 days, 0 if none.
func (f Frequency) NumberCell() string { return "" }

// NumberCell is the median as a duration, "-" without commits.
func (l LeadTime) NumberCell() string { return "" }

// NumberCell is the median as a duration, "-" without a completed recovery.
func (r Recovery) NumberCell() string { return "" }

// NumberCell is the rate in whole percent, "-" without deployments.
func (r ChangeFailRate) NumberCell() string { return "" }

// NumberCell is the rate in whole percent, "-" without successful
// deployments.
func (r ReworkRate) NumberCell() string { return "" }
