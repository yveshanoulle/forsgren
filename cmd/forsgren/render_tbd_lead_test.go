package main

import (
	"path/filepath"
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

// shopDirect and shopBatch are Acme Shop's direct and batch size cells over
// acmeCommits (forsgren#390, step 2): its three commits in the window are
// direct, two of them timed by author date because their deployment has no
// known lineage, and the one deployment with a known lineage brought one
// commit to the chain; Acme Tools has no commit, so a dash in both.
const (
	shopDirect = "<td>17 min (3) · Mostly estimated: 2 of 3 commits timed by author date.</td>"
	shopBatch  = "<td>1 (1) · 1 deployment of unknown lineage not counted</td>"
)

// leadRow is the end of a project's TBD row from its Mainline Interval cell:
// interval, its direct cell, the pull requests cell lead, its batch size cell.
func leadRow(interval, lead string) string {
	direct, batch := "<td>-</td>", "<td>-</td>"
	if interval == shopCell {
		direct, batch = shopDirect, shopBatch
	}
	return interval + "\n            " + direct + "\n            <td>" + lead + "</td>\n            " + batch + "\n"
}

// shopDirectUncollected is Acme Shop's direct cell while data/pulls.csv is
// absent (forsgren#390, step 3): the pull request merges among its commits
// cannot be told apart yet; Acme Tools has no direct commit, so no note.
const shopDirectUncollected = "<td>17 min (3) · Mostly estimated: 2 of 3 commits timed by author date." +
	" · pull request merges cannot be told apart yet</td>"

// uncollected is row, a leadRow, while the pull requests have not been
// collected.
var uncollected = strings.NewReplacer(shopDirect, shopDirectUncollected).Replace

// TestRenderShowsTheMainlineLeadTimeOfEachProject (forsgren#256, step 2): with
// data/pulls.csv beside --data, tbd.html shows each project's Mainline Lead
// Time next to its Mainline Interval: Acme Shop's human lead times of 2, 30
// and 1 hours have a mean of 11 h and a sample deviation of sqrt(271) h, 2 of
// the 3 within 24 hours, the cut one making the mean a lower bound, the one of
// the created time named, then the bot's and the unknown author's named as
// not counted (forsgren#345, step 2); Acme Tools has no pull request, so the
// no-human sentence.
func TestRenderShowsTheMainlineLeadTimeOfEachProject(t *testing.T) {
	pinNow(t)
	data := writeData(t, acmeHistory(), acmeCommits())
	writePulls(t, data, acmePulls(t))
	got := tbdSiteOf(t, validConfig, data)
	wantIn(t, got, "<th scope=\"colgroup\" colspan=\"3\">Mainline Lead Time</th>",
		leadRow(shopCell, "11 h ± 16 h 27 min (3, 1 cut) · 66% (2 of 3) pull requests merged within 24 hours of "+
			"their first commit · the mean is a lower bound · 1 pull request timed by its created time"+
			" · 1 bot pull request not counted · 1 pull request of unknown author not counted"),
		"<th scope=\"row\">Acme Tools</th>\n            "+leadRow("<td>-</td>", noHumanPulls))
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
	wantIn(t, tbdSiteOf(t, validConfig, data), uncollected(leadRow(shopCell, notYet)),
		"<th scope=\"row\">Acme Tools</th>\n            "+leadRow("<td>-</td>", notYet))
	writePulls(t, data, nil)
	got := tbdSiteOf(t, validConfig, data)
	wantIn(t, got, leadRow(shopCell, noHumanPulls))
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
