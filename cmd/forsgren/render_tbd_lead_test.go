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
// the merge, stands in), when it was merged, and whether its commit list was
// cut.
type mergedPull struct {
	repository    string
	number        int64
	first, merged string
	cut           bool
}

// stored is m as data/pulls.csv holds it, created when its first commit was
// authored.
func (m mergedPull) stored(t *testing.T) history.PullRequest {
	t.Helper()
	p := history.PullRequest{Repository: m.repository, Number: m.number, MergedAt: utcAt(t, m.merged),
		MergeCommit: mergeSHA, UpdatedAt: utcAt(t, m.merged), FirstCommitCut: m.cut}
	if m.first == "" {
		p.CreatedAt, p.CreatedStandsIn = p.MergedAt.Add(-time.Hour), true
		return p
	}
	p.FirstCommitAt = utcAt(t, m.first)
	p.CreatedAt = p.FirstCommitAt
	return p
}

// acmePulls are Acme Shop's merged pull requests: in the 30 days, 2 hours
// (acme/api), 30 hours with a cut commit list (Acme/API, the case ignored)
// and 1 hour from the created time (acme/ios-app); one merged before the
// window is not counted. Acme Tools has none.
func acmePulls(t *testing.T) []history.PullRequest {
	pulls := []mergedPull{
		{"acme/api", 1, "2026-10-01T08:00:00Z", "2026-10-01T10:00:00Z", false},
		{"Acme/API", 2, "2026-09-29T06:00:00Z", "2026-09-30T12:00:00Z", true},
		{"acme/ios-app", 3, "", "2026-09-28T12:00:00Z", false},
		{"acme/api", 4, "2026-07-31T12:00:00Z", "2026-08-01T12:00:00Z", false},
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

// leadRow is the end of a project's TBD row from its Mainline Interval cell:
// interval, then the Mainline Lead Time cell lead.
func leadRow(interval, lead string) string { return interval + "\n            <td>" + lead + "</td>\n" }

// TestRenderShowsTheMainlineLeadTimeOfEachProject (forsgren#256, step 2): with
// data/pulls.csv beside --data, tbd.html shows each project's Mainline Lead
// Time next to its Mainline Interval: Acme Shop's lead times of 2, 30 and 1
// hours have a mean of 11 h and a sample deviation of sqrt(271) h, 2 of the 3
// within 24 hours, the cut one making the mean a lower bound, and the one of
// the created time named; Acme Tools has no pull request, so "-".
func TestRenderShowsTheMainlineLeadTimeOfEachProject(t *testing.T) {
	pinNow(t)
	data := writeData(t, acmeHistory(), acmeCommits())
	writePulls(t, data, acmePulls(t))
	got := tbdSiteOf(t, validConfig, data)
	wantIn(t, got, "<th scope=\"col\">Mainline Lead Time</th>",
		leadRow(shopCell, "11 h ± 16 h 27 min (3, 1 cut) · 66% of pull requests merged within 24 hours of their "+
			"first commit · the mean is a lower bound · 1 pull request timed by its created time"),
		"<th scope=\"row\">Acme Tools</th>\n            "+leadRow("<td>-</td>", "-"))
}

// TestRenderTbdPageBeforeThePullRequestsAreCollected (forsgren#256, step 2):
// without data/pulls.csv every Mainline Lead Time cell says the pull requests
// have not been collected yet; with the file and no pull request in the
// window, the one collect writes when there was none to store, each cell is
// "-".
func TestRenderTbdPageBeforeThePullRequestsAreCollected(t *testing.T) {
	pinNow(t)
	const notYet = "No pull requests have been collected yet"
	data := writeData(t, acmeHistory(), acmeCommits())
	wantIn(t, tbdSiteOf(t, validConfig, data), leadRow(shopCell, notYet),
		"<th scope=\"row\">Acme Tools</th>\n            "+leadRow("<td>-</td>", notYet))
	writePulls(t, data, nil)
	got := tbdSiteOf(t, validConfig, data)
	wantIn(t, got, leadRow(shopCell, "-"))
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
		"unknown version": {"# forsgren pulls v2\n", "unknown history format version"},
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
