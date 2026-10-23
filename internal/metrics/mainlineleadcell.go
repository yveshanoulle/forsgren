package metrics

import (
	"fmt"
	"strconv"
	"strings"
	"time"
)

// notReadableCell is the cell of a project whose pull request read GitHub
// refused (forsgren#337, step 2).
const notReadableCell = "Pull requests not readable"

// Cell is the TBD page's Mainline Lead Time cell (forsgren#256, step 2): the
// mean, the deviation and the count of pull requests as the Mainline Interval
// writes them, the cut ones next to the count (decision #299), then the share
// merged within the reference in Yves's wording of decision #302, "3 h ± 1 h
// (4, 1 cut) · 50% of pull requests merged within 24 hours of their first
// commit"; then, with a cut one, "the mean is a lower bound", so the mean is
// never shown as exact, and the pull requests the created time stood in for
// (decision #300), "1 pull request timed by its created time"; "-" without a
// pull request; "Pull requests not readable" for a project collect was
// refused the pull request read of (forsgren#337, step 2), never a lead time
// of what was read nor the dash.
func (m MainlineLeadTime) Cell() string {
	if m.NotReadable {
		return notReadableCell
	}
	if !m.HasLeadTime() {
		return noNumber
	}
	parts := []string{
		fmt.Sprintf("%s ± %s (%s)", shortDuration(m.Mean), m.deviation(), m.counts()),
		fmt.Sprintf("%d%% of pull requests merged within %d hours of their first commit", m.WithinReferenceShare(),
			leadReference/time.Hour),
	}
	if m.Cut > 0 {
		parts = append(parts, "the mean is a lower bound")
	}
	if m.CreatedStandsIn > 0 {
		parts = append(parts, m.standInNote())
	}
	return strings.Join(parts, cellSeparator)
}

// deviation is the deviation written for the cell, a dash below two pull
// requests.
func (m MainlineLeadTime) deviation() string {
	if !m.HasDeviation() {
		return noNumber
	}
	return shortDuration(m.Deviation)
}

// counts is the count of pull requests, "4", and with cut ones "4, 1 cut".
func (m MainlineLeadTime) counts() string {
	if m.Cut == 0 {
		return strconv.Itoa(m.PullRequests)
	}
	return fmt.Sprintf("%d, %d cut", m.PullRequests, m.Cut)
}

// standInNote names the pull requests the created time stood in for.
func (m MainlineLeadTime) standInNote() string {
	if m.CreatedStandsIn == 1 {
		return "1 pull request timed by its created time"
	}
	return fmt.Sprintf("%d pull requests timed by their created time", m.CreatedStandsIn)
}
