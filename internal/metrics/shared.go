package metrics

// What deployment frequency, lead time for changes and failed deployment
// recovery time share: the windows counted back from the render time, a
// repository's project, the band names and the text a band is shown with.

import (
	"fmt"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// day is one window day: 24 hours, counted back from the render time in UTC.
const day = 24 * time.Hour

// window is the last days days before the render time: at or after now
// minus that many days of 24 hours, and not after now, both ends included.
type window int

// The windows the page counts in.
const (
	last7   window = 7
	last30  window = 30
	last180 window = 180
)

// holds says whether at lies in w, seen at now.
func (w window) holds(at, now time.Time) bool {
	start := now.Add(-time.Duration(w) * day)
	return !at.Before(start) && !at.After(now)
}

// count is 1 when at lies in w, seen at now, else 0.
func (w window) count(at, now time.Time) int {
	if w.holds(at, now) {
		return 1
	}
	return 0
}

// String is w as the page says it, "the last 30 days".
func (w window) String() string { return fmt.Sprintf("the last %d days", int(w)) }

// projectIndex maps each configured repository, lower-case, to its
// project's index in the config.
type projectIndex map[string]int

// indexOf is the projectIndex of projects.
func indexOf(projects []config.Project) projectIndex {
	index := projectIndex{}
	for i, p := range projects {
		for _, r := range p.Repositories {
			index[strings.ToLower(r.Name)] = i
		}
	}
	return index
}

// of is the index of the project whose config lists repository, compared
// ignoring case as the config compares names; false when no project lists
// it any more.
func (p projectIndex) of(repository string) (int, bool) {
	i, ok := p[strings.ToLower(repository)]
	return i, ok
}

// bandName is names[b], the page's name of band b, or names[0], "No band",
// for a b outside the table.
func bandName[B ~int](b B, names []string) string {
	if b < 1 || int(b) >= len(names) {
		return names[0]
	}
	return names[b]
}

// bandText is how the page shows a band: the band, then what it was
// measured on in the window w, "<band> — <measure> in the last 30 days".
func bandText(band fmt.Stringer, measure string, w window) string {
	return fmt.Sprintf("%s — %s in %s", band, measure, w)
}

// plural is n with its unit, singular for one: "1 commit", "2 commits".
func plural(n int, unit string) string { return counted(n, unit, unit+"s") }

// counted is n with the singular one for 1 and the plural many otherwise,
// for a unit whose plural is not its singular plus s: "1 recovery", "2
// recoveries".
func counted(n int, one, many string) string {
	if n == 1 {
		return "1 " + one
	}
	return fmt.Sprintf("%d %s", n, many)
}
