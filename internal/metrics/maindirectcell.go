package metrics

import (
	"fmt"
	"strconv"
	"strings"
)

// Cell is the TBD page's direct cell (forsgren#390, step 2): the median time
// to main and the count of direct commits, "20 min (4)", then the note on the
// commits of deployments without a known lineage, timed by their author
// date, as the Mainline Interval words it; "-" without a direct commit.
func (m MainlineDirect) Cell() string {
	if !m.HasDirect() {
		return noNumber
	}
	parts := []string{fmt.Sprintf("%s (%d)", shortDuration(m.Median), m.Commits)}
	if note := (MainlineInterval{Commits: m.Commits, ByAuthorDate: m.ByAuthorDate}).Note(); note != "" {
		parts = append(parts, note)
	}
	return strings.Join(parts, cellSeparator)
}

// Cell is the TBD page's batch size cell (forsgren#390, step 2): the median
// number of commits per deployment and the count of deployments, "1.5 (45)",
// then the deployments left out for want of a known lineage, "3 deployments
// of unknown lineage not counted"; "-" without a deployment, the note still
// said.
func (b BatchSize) Cell() string {
	parts := []string{noNumber}
	if b.HasBatch() {
		parts[0] = fmt.Sprintf("%s (%d)", strconv.FormatFloat(b.Median, 'f', -1, 64), b.Deployments)
	}
	if b.Legacy > 0 {
		parts = append(parts, plural(b.Legacy, "deployment")+" of unknown lineage not counted")
	}
	return strings.Join(parts, cellSeparator)
}
