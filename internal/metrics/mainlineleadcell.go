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

// noHumanPullsCell is the cell of a project without a human pull request
// merged in the window, Yves's wording on #342 (forsgren#345, step 2): no
// human pull request does not prove the changes went straight to the trunk.
const noHumanPullsCell = "No human pull requests in this period; changes may go directly to the trunk"

// Cell is the TBD page's Mainline Lead Time cell (forsgren#256, step 2), of
// the human pull requests only (forsgren#345, step 2): the mean, the
// deviation and the count of pull requests as the Mainline Interval writes
// them, the cut ones next to the count (decision #299), then the share merged
// within the reference with its counts (Yves's wording of decision #302 and
// of #343), "3 h ± 1 h (4, 1 cut) · 50% (2 of 4) pull requests merged within
// 24 hours of their first commit"; then, with a cut one, "the mean is a lower
// bound", so the mean is never shown as exact, and the pull requests the
// created time stood in for (decision #300), "1 pull request timed by its
// created time"; without a human pull request, noHumanPullsCell; last, either
// way, the bot pull requests and those of unknown author not counted, "3 bot
// pull requests not counted" (#341); "Pull requests not readable" for a
// project collect was refused the pull request read of (forsgren#337, step
// 2), never a lead time of what was read nor anything else.
func (m MainlineLeadTime) Cell() string {
	if m.NotReadable {
		return notReadableCell
	}
	return strings.Join(append(m.counted(), m.notCountedNotes()...), cellSeparator)
}

// counted are the cell's parts on the human pull requests: the lead time and
// its notes, or noHumanPullsCell without one.
func (m MainlineLeadTime) counted() []string {
	if !m.HasLeadTime() {
		return []string{noHumanPullsCell}
	}
	parts := []string{
		fmt.Sprintf("%s ± %s (%s)", shortDuration(m.Mean), m.deviation(), m.counts()),
		fmt.Sprintf("%d%% (%d of %d) pull requests merged within %d hours of their first commit",
			m.WithinReferenceShare(), m.WithinReference, m.PullRequests, leadReference/time.Hour),
	}
	if m.Cut > 0 {
		parts = append(parts, "the mean is a lower bound")
	}
	if m.CreatedStandsIn > 0 {
		parts = append(parts, m.standInNote())
	}
	return parts
}

// notCountedNotes name the bot pull requests and those of unknown author left
// out of the lead time, each only when there are any.
func (m MainlineLeadTime) notCountedNotes() []string {
	var notes []string
	if m.Bots > 0 {
		notes = append(notes, pullRequests(m.Bots, "bot pull request", "bot pull requests")+" not counted")
	}
	if m.UnknownAuthors > 0 {
		notes = append(notes, pullRequests(m.UnknownAuthors, "pull request", "pull requests")+
			" of unknown author not counted")
	}
	return notes
}

// pullRequests is n with the singular one or the plural many: "1 bot pull
// request", "3 bot pull requests".
func pullRequests(n int, one, many string) string {
	if n == 1 {
		return "1 " + one
	}
	return fmt.Sprintf("%d %s", n, many)
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
