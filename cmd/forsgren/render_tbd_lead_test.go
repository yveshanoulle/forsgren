package main

import (
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// mergeSHA is the merge commit of the made-up pull requests.
const mergeSHA = "0123456789abcdef0123456789abcdef01234567"

// mergedPull is a made-up merged pull request: its repository and number,
// when its first commit was authored (empty: the created time, an hour before
// the merge, stands in), when it was merged, whether its commit list was cut,
// and who opened it (forsgren#345).
type mergedPull struct {
	repository    string
	number        int64
	first, merged string
	cut           bool
	bot           history.BotStatus
}

// stored is m as data/pulls.csv holds it, created when its first commit was
// authored.
func (m mergedPull) stored(t *testing.T) history.PullRequest {
	t.Helper()
	p := history.PullRequest{Repository: m.repository, Number: m.number, MergedAt: utcAt(t, m.merged),
		MergeCommit: mergeSHA, UpdatedAt: utcAt(t, m.merged), FirstCommitCut: m.cut, Bot: m.bot}
	if m.first == "" {
		p.CreatedAt, p.CreatedStandsIn = p.MergedAt.Add(-time.Hour), true
		return p
	}
	p.FirstCommitAt = utcAt(t, m.first)
	p.CreatedAt = p.FirstCommitAt
	return p
}

// acmePulls are Acme Shop's merged pull requests: in the 30 days, of people,
// 2 hours (acme/api), 30 hours with a cut commit list (Acme/API, the case
// ignored) and 1 hour from the created time (acme/ios-app), and, not counted
// in the lead time (forsgren#345, step 2), one of a bot and one of unknown
// author; one merged before the window is not counted at all. Acme Tools has
// none.
func acmePulls(t *testing.T) []history.PullRequest {
	pulls := []mergedPull{
		{"acme/api", 1, "2026-10-01T08:00:00Z", "2026-10-01T10:00:00Z", false, history.ByHuman},
		{"Acme/API", 2, "2026-09-29T06:00:00Z", "2026-09-30T12:00:00Z", true, history.ByHuman},
		{"acme/ios-app", 3, "", "2026-09-28T12:00:00Z", false, history.ByHuman},
		{"acme/api", 4, "2026-07-31T12:00:00Z", "2026-08-01T12:00:00Z", false, history.ByHuman},
		{"acme/api", 5, "2026-09-20T12:00:00Z", "2026-10-02T12:00:00Z", false, history.ByBot},
		{"acme/ios-app", 6, "2026-09-25T12:00:00Z", "2026-10-02T11:00:00Z", false, history.BotUnknown},
	}
	stored := make([]history.PullRequest, len(pulls))
	for i, p := range pulls {
		stored[i] = p.stored(t)
	}
	return stored
}

// writePulls stores pulls in data/pulls.csv beside the history at data; none
// writes the file with its header lines only.
func writePulls(t *testing.T, data string, pulls []history.PullRequest) {
	t.Helper()
	if _, err := history.AppendPullRequests(filepath.Join(filepath.Dir(data), "pulls.csv"), pulls); err != nil {
		t.Fatal(err)
	}
}

// noHumanPulls is the Mainline Lead Time cell of a project without a human
// pull request in the window, a dash (forsgren#390, step 2).
const noHumanPulls = "-"

// projectCells are the cells of a project's TBD row before its pull requests
// cell: its Mainline Interval cells and its time to deploy cells (forsgren#418).
type projectCells struct{ interval, deploy string }

// leadRow is the middle of a project's TBD row: the Mainline Interval cells,
// the time to main (the push state without pushes), the time to deploy cells
// and the pull requests cell lead (forsgren#418: the order of the groups).
func leadRow(row projectCells, lead string) string {
	return row.interval + "\n            " + pushesNotCollected(3) + "\n            " + row.deploy +
		"\n            " + leadTd(lead) + "\n"
}

// leadTd is the pull requests cell of lead as the template writes it; a lead
// starting with {3,4} has the notes 3 and 4 (forsgren#394, step 2).
func leadTd(lead string) string {
	rest, noted := strings.CutPrefix(lead, "{")
	if !noted {
		return "<td>" + lead + "</td>"
	}
	list, value, _ := strings.Cut(rest, "}")
	cell := notedCell{value: value}
	for _, n := range strings.Split(list, ",") {
		number, _ := strconv.Atoi(n)
		cell.numbers = append(cell.numbers, number)
	}
	return notedTd(cell)
}

// notedCell is a cell with notes: its value and the numbers of its notes.
type notedCell struct {
	value   string
	numbers []int
}

// notedTd is the cell as the template writes it: described by each note's
// line, the marker (N) after the value with a visually hidden "note" before
// it (forsgren#394, step 2).
func notedTd(c notedCell) string {
	ids, marks := make([]string, len(c.numbers)), ""
	for i, n := range c.numbers {
		ids[i] = "tbd-note-" + strconv.Itoa(n)
		marks += ` <span class="visually-hidden">note</span> (` + strconv.Itoa(n) + `)`
	}
	return `<td aria-describedby="` + strings.Join(ids, " ") + `">` + c.value + marks + `</td>`
}

// pushesNotCollected is the state cell of a push group n columns wide, with
// no pushes.csv beside the history.
func pushesNotCollected(n int) string {
	return "<td colspan=\"" + strconv.Itoa(n) + "\">Pushes not collected yet</td>"
}

// developersRow is the end of a project's TBD row without pushes: the shares
// state cell, then its Developers cell.
func developersRow(developers string) string {
	return pushesNotCollected(4) + "\n            " + tdRow(developers)
}

// TestRenderShowsTheMainlineLeadTimeOfEachProject (forsgren#256, step 2): with
// data/pulls.csv beside --data, tbd.html shows each project's Mainline Lead
// Time next to its Mainline Interval: Acme Shop's human lead times of 2, 30
// and 1 hours have a mean of 11 h and a sample deviation of sqrt(271) h, 2 of
// the 3 within 24 hours, the cut one making the mean a lower bound, the one of
// the created time named, then the bot's named as
// not counted (forsgren#345, step 2); Acme Tools has no pull request, so the
// no-human sentence.
func TestRenderShowsTheMainlineLeadTimeOfEachProject(t *testing.T) {
	pinNow(t)
	data := writeData(t, acmeHistory(), acmeCommits())
	writePulls(t, data, acmePulls(t))
	got := tbdSiteOf(t, validConfig, data)
	wantIn(t, got, "<th scope=\"colgroup\" colspan=\"1\">PR Lead Time</th>",
		leadRow(shopRow, "{3,4,5}11 h ± 16 h 27 · 3 (1 cut) · 66% (2 of 3) pull requests merged within 24 hours of "+
			"their first commit"),
		leadRow(noRow, noHumanPulls))
}

// TestRenderTbdPageBeforeThePullRequestsAreCollected (forsgren#256, step 2):
// without data/pulls.csv every Mainline Lead Time cell says the pull requests
// have not been collected yet; with the file and no pull request in the
// window, the one collect writes when there was none to store, each cell is
// the no-human sentence (forsgren#345, step 2).
func TestRenderTbdPageBeforeThePullRequestsAreCollected(t *testing.T) {
	pinNow(t)
	const notYet = "No pull requests have been collected yet"
	data := writeData(t, acmeHistory(), acmeCommits())
	wantIn(t, tbdSiteOf(t, validConfig, data), leadRow(shopRow, notYet), leadRow(noRow, notYet))
	writePulls(t, data, nil)
	got := tbdSiteOf(t, validConfig, data)
	wantIn(t, got, leadRow(shopRow, noHumanPulls))
	if strings.Contains(got, notYet) {
		t.Errorf("want no %q with pulls.csv, got:\n%s", notYet, got)
	}
}

// TestRenderRefusesABadPullsFile (forsgren#256, step 2): a malformed or
// unknown-version pulls file fails render with its own message, naming it,
// and writes nothing, as the other data files do.
func TestRenderRefusesABadPullsFile(t *testing.T) {
	head := "# forsgren pulls v1\nrepository,number,created_at,merged_at,merge_commit,updated_at," +
		"first_commit_at,first_commit_cut,created_stands_in\n"
	wantBadFileRefused(t, "pulls.csv", map[string]badFile{
		"unknown version": {"# forsgren pulls v3\n", "unknown history format version"},
		"malformed line":  {head + "acme/api,7\n", "line 3: malformed history"},
	})
}

// wantIn fails unless every want is in the page got.
func wantIn(t *testing.T, got string, wants ...string) {
	t.Helper()
	for _, want := range wants {
		if !strings.Contains(got, want) {
			t.Errorf("want %q in tbd.html, got:\n%s", want, got)
		}
	}
}
