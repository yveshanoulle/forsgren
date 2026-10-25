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

// Cell is the TBD page's Mainline Lead Time cell (forsgren#256, step 2), of
// the human pull requests only (forsgren#345, step 2): the mean, the
// deviation and the count of pull requests, the cut ones next to the count
// (decision #299, written per #432 without brackets of its own: "3 h ± 1 h ·
// 4 (1 cut)"), then the share merged within the reference with its counts
// (Yves's wording of decision #302 and of #343), "50% (2 of 4) pull requests
// merged within 24 hours of their first commit"; without a human pull request,
// a dash (forsgren#390, step 2). What it does not say in words are notes
// (forsgren#394, step 2): the mean is a lower bound with a cut one, the
// created time stood in for some (decision #300), and the bot pull requests
// are not counted (#341). "Pull requests not readable" for a project collect
// was refused the pull request read of (forsgren#337, step 2), never a lead
// time of what was read nor anything else.
func (m MainlineLeadTime) Cell() NotedCell {
	if m.NotReadable {
		return NotedCell{Value: notReadableCell}
	}
	return NotedCell{Value: strings.Join(m.counted(), cellSeparator), Notes: m.Notes()}
}

// Notes are the kinds of note on the cell, with their counts.
func (m MainlineLeadTime) Notes() []Note {
	var notes []Note
	if m.HasLeadTime() {
		notes = appendNote(notes, NoteLowerBound, m.Cut)
		notes = appendNote(notes, NoteCreatedTime, m.CreatedStandsIn)
	}
	return appendNote(notes, NoteBotsNotCounted, m.Bots)
}

// appendNote adds a note of kind for count pull requests when there are any.
func appendNote(notes []Note, kind NoteKind, count int) []Note {
	if count == 0 {
		return notes
	}
	return append(notes, Note{Kind: kind, Count: count})
}

// counted are the cell's parts on the human pull requests: the lead time and
// the share, or a dash without one.
func (m MainlineLeadTime) counted() []string {
	if !m.HasLeadTime() {
		return []string{noNumber}
	}
	return []string{
		fmt.Sprintf("%s ± %s%s%s", tbdDuration(m.Mean), m.deviation(), cellSeparator, m.counts()),
		fmt.Sprintf("%d%% (%d of %d) pull requests merged within %d hours of their first commit",
			m.WithinReferenceShare(), m.WithinReference, m.PullRequests, leadReference/time.Hour),
	}
}

// deviation is the deviation written for the cell, a dash below two pull
// requests.
func (m MainlineLeadTime) deviation() string {
	if !m.HasDeviation() {
		return noNumber
	}
	return tbdDuration(m.Deviation)
}

// counts is the count of pull requests, "4", and with cut ones "4 (1 cut)".
func (m MainlineLeadTime) counts() string {
	if m.Cut == 0 {
		return strconv.Itoa(m.PullRequests)
	}
	return fmt.Sprintf("%d (%d cut)", m.PullRequests, m.Cut)
}
