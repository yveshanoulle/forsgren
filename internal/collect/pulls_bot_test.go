package collect

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/github"
)

// Whether a bot account opened each stored pull request (forsgren#345, step
// 1).

const (
	// botUser is Dependabot as GitHub names a pull request's author.
	botUser = `{"login": "dependabot[bot]", "type": "Bot"}`
	// pullsHeaderV1 is the pulls file's header before the bot column.
	pullsHeaderV1 = "# forsgren pulls v1\nrepository,number,created_at,merged_at,merge_commit,updated_at," +
		"first_commit_at,first_commit_cut,created_stands_in\n"
)

// TestCollectStoresWhetherABotOpenedEachPullRequest (forsgren#345): GitHub's
// account type of the author decides the bot column, true for "Bot" and
// false for a person; a pull request GitHub names no author for is stored
// with the column empty, unknown, never as a person's. No login is stored.
func TestCollectStoresWhetherABotOpenedEachPullRequest(t *testing.T) {
	g := pullsOnly(t, pull15, pull14, pull12)
	g.bodies[pullsPath] = list(pull15.jsonBy("null"), pull14.jsonBy(botUser), pull12.json())
	path := historyPath(t)
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	data := dataOf(path)
	data.want(t, "pulls.csv", pullsHeader+pull12.lineBy("2026-09-21T10:00:00Z", false, "false")+
		pull14.lineBy("2026-09-23T10:00:00Z", false, "true")+pull15.lineBy("2026-09-24T10:00:00Z", false, ""))
	wantNoLogin(t, filepath.Join(string(data), "pulls.csv"))
}

// TestCollectStoresAnAuthorOfAnotherTypeAsUnknown (forsgren#345, Yves's
// answer on #349, Option B): only the account type "User" is a person; an
// Organization, a Mannequin or a user GitHub gives no type for is stored with
// the bot column empty, unknown, never as a person's, and the pull request is
// stored all the same.
func TestCollectStoresAnAuthorOfAnotherTypeAsUnknown(t *testing.T) {
	g := pullsOnly(t, pull15, pull14, pull12)
	g.bodies[pullsPath] = list(pull15.jsonBy(`{"login": "someone", "type": "Organization"}`),
		pull14.jsonBy(`{"login": "someone", "type": "Mannequin"}`), pull12.jsonBy(`{"login": "someone"}`))
	path := historyPath(t)
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	dataOf(path).want(t, "pulls.csv", pullsHeader+pull12.lineBy("2026-09-21T10:00:00Z", false, "")+
		pull14.lineBy("2026-09-23T10:00:00Z", false, "")+pull15.lineBy("2026-09-24T10:00:00Z", false, ""))
}

// wantNoLogin fails unless the file at path names neither login of the
// fake's pull requests.
func wantNoLogin(t *testing.T, path string) {
	t.Helper()
	raw, err := os.ReadFile(filepath.Clean(path))
	if err != nil {
		t.Fatal(err)
	}
	for _, login := range []string{"someone", "dependabot"} {
		if strings.Contains(string(raw), login) {
			t.Errorf("want no login %q stored, got %q", login, raw)
		}
	}
}

// TestCollectUpgradesAV1PullsFileKeepingUnknownAsUnknown (forsgren#345, as
// forsgren#273 upgraded the commits): the first run that appends to a v1
// file rewrites it once as v2; a line stored before the bot column keeps it
// empty, its author not known, and the new pull request has its own.
func TestCollectUpgradesAV1PullsFileKeepingUnknownAsUnknown(t *testing.T) {
	v1Line := strings.TrimSuffix(pull12.lineBy("2026-09-21T10:00:00Z", false, ""), ",\n") + "\n"
	g := pullsOnly(t, pull14)
	g.bodies[pullsPath] = list(pull14.jsonBy(botUser))
	path := historyPath(t)
	data := dataOf(path)
	data.write(t, "pulls.csv", pullsHeaderV1+v1Line)
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	data.want(t, "pulls.csv", pullsHeader+pull12.lineBy("2026-09-21T10:00:00Z", false, "")+
		pull14.lineBy("2026-09-23T10:00:00Z", false, "true"))
}
