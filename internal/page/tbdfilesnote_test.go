package page

import (
	"strings"
	"testing"
)

// Note 8 (forsgren#496, step 5): a service row whose commits are not all read
// yet marks its Time to deploy and Commits per deployment cells, and the Notes
// list says what the mark means.

// filesReadingData is subRowsData whose service API has 3 commits with no
// stored files yet.
func filesReadingData(all bool) Data {
	data := inFigures(subRowsData(), all)
	data.TbdMetrics[1].FilesReading = true
	data.TbdMetrics[1].Deploy.Unread = 3
	return data
}

// apiRowReading is apiRow with the note 8 on the first cell of its Time to
// deploy and its Commits per deployment.
func apiRowReading(all bool) string {
	row := strings.Replace(apiRow(all), "<td class=\"num\">3</td>", notedTd(notedCell{"3", []int{8}}), 1)
	if all {
		row = strings.Replace(row, "<td class=\"num\">&lt; 1 m</td>", notedTd(notedCell{"&lt; 1 m", []int{8}}), 1)
		return strings.Replace(row, "<td class=\"num\">0.0</td>", notedTd(notedCell{"0.0", []int{8}}), 1)
	}
	row = strings.Replace(row, "<td class=\"num\">1 h</td>", notedTd(notedCell{"1 h", []int{8}}), 1)
	return strings.Replace(row, "<td class=\"num\">2.0</td>", notedTd(notedCell{"2.0", []int{8}}), 1)
}

// TestAServiceStillReadingItsFilesMarksItsDeployCells: the mean cell, or the
// median cell where it is alone, of both groups carries (8).
func TestAServiceStillReadingItsFilesMarksItsDeployCells(t *testing.T) {
	for _, all := range []bool{false, true} {
		wantAll(t, "reading", rendered(t, "tbd.html", filesReadingData(all)), apiRowReading(all))
	}
}

// TestNoteEightIsListedWithTheServiceAndItsCommits: the Notes list names the
// kind by its number and text, then the service and how many commits are left
// out.
func TestNoteEightIsListedWithTheServiceAndItsCommits(t *testing.T) {
	wantAll(t, "notes", rendered(t, "tbd.html", filesReadingData(false)),
		`<li id="tbd-note-8">(8) Files still being read: commits whose changed files forsgren has not read yet `+
			`are left out: Acme Shop: API 3</li>`)
}

// TestNoteEightGoesOnceNothingIsUnread: without the flag no cell carries (8)
// and the Notes list has no such line.
func TestNoteEightGoesOnceNothingIsUnread(t *testing.T) {
	for _, all := range []bool{false, true} {
		got := rendered(t, "tbd.html", inFigures(subRowsData(), all))
		wantNone(t, "read", got, "tbd-note-8", "(8)", "Files still being read")
	}
}
