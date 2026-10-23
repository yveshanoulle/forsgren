package history

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Whether a bot account opened a pull request (forsgren#345, step 1).

const (
	// pullsHeadV1 and pullsLineV1 are pullsLine1 as the pulls format v1 wrote
	// it, before the bot column.
	pullsHeadV1 = "# forsgren pulls v1\nrepository,number,created_at,merged_at,merge_commit,updated_at," +
		"first_commit_at,first_commit_cut,created_stands_in\n"
	pullsLineV1 = "acme/app,45,2026-09-01T08:00:00Z,2026-09-02T10:00:00Z," + mergeSHA +
		",2026-09-03T12:00:00Z,2026-08-31T07:00:00Z,false,false\n"
	// pullsLineUnknown is pullsLineV1 in the pulls format v2: its bot column
	// empty, the author's account type not known.
	pullsLineUnknown = "acme/app,45,2026-09-01T08:00:00Z,2026-09-02T10:00:00Z," + mergeSHA +
		",2026-09-03T12:00:00Z,2026-08-31T07:00:00Z,false,false,\n"
)

// pullBy is pull with its bot status.
func pullBy(number int64, hours int, bot BotStatus) PullRequest {
	p := pull(number, hours)
	p.Bot = bot
	return p
}

// v1Pulls writes a pulls file in the format v1 with the lines and returns its
// path.
func v1Pulls(t *testing.T, lines ...string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "pulls.csv")
	writeAt(t, path, pullsHeadV1+strings.Join(lines, ""))
	return path
}

// writeAt writes content to the file at path.
func writeAt(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}

// TestThePullsFileKeepsWhoOpenedEachPullRequest (forsgren#345): a person's
// pull request is bot false, a bot's true, and one whose author's account
// type is not known has the column empty: three states read back as they
// were written, an unknown one never read as a person's.
func TestThePullsFileKeepsWhoOpenedEachPullRequest(t *testing.T) {
	path := filepath.Join(t.TempDir(), "pulls.csv")
	in := []PullRequest{pullBy(45, 10, ByHuman), pullBy(46, 11, ByBot), pullBy(47, 12, BotUnknown)}
	if n, err := AppendPullRequests(path, in); err != nil || n != 3 {
		t.Fatalf("want 3 lines written, got %d, %v", n, err)
	}
	wantFile(t, path, pullsHead+pullsLine1+
		"acme/app,46,2026-09-01T08:00:00Z,2026-09-02T11:00:00Z,"+mergeSHA+
		",2026-09-03T12:00:00Z,2026-08-31T07:00:00Z,false,false,true\n"+
		"acme/app,47,2026-09-01T08:00:00Z,2026-09-02T12:00:00Z,"+mergeSHA+
		",2026-09-03T12:00:00Z,2026-08-31T07:00:00Z,false,false,\n")
	wantPulls(t, path, in)
}

// TestLoadPullRequestsReadsAV1FileWithBotStatusUnknown (forsgren#345): a
// file written before the bot column is read as it is, every pull request's
// bot status unknown, never a person's, and the file is left untouched.
func TestLoadPullRequestsReadsAV1FileWithBotStatusUnknown(t *testing.T) {
	path := v1Pulls(t, pullsLineV1)
	wantPulls(t, path, []PullRequest{pullBy(45, 10, BotUnknown)})
	wantFile(t, path, pullsHeadV1+pullsLineV1)
}

// TestAppendPullRequestsUpgradesAV1FileToV2 (forsgren#345, as forsgren#273
// upgraded the commits): the first append to a v1 file rewrites it once as
// v2, the old line kept with its bot column empty (unknown stays unknown),
// then the new pull requests with theirs; no temporary file is left behind.
func TestAppendPullRequestsUpgradesAV1FileToV2(t *testing.T) {
	path := v1Pulls(t, pullsLineV1)
	if n, err := AppendPullRequests(path, []PullRequest{pullBy(46, 11, ByBot)}); err != nil || n != 1 {
		t.Fatalf("want 1 line written, got %d, %v", n, err)
	}
	wantFile(t, path, pullsHead+pullsLineUnknown+
		"acme/app,46,2026-09-01T08:00:00Z,2026-09-02T11:00:00Z,"+mergeSHA+
		",2026-09-03T12:00:00Z,2026-08-31T07:00:00Z,false,false,true\n")
	wantAlone(t, path)
	wantPulls(t, path, []PullRequest{pullBy(45, 10, BotUnknown), pullBy(46, 11, ByBot)})
}

// TestAppendPullRequestsWithNothingNewStillUpgradesAV1File (forsgren#345):
// the file is v2 after one collect run, whether or not it stored a pull
// request; the held line stays unknown, though the record given says a
// person opened it: the first line stays.
func TestAppendPullRequestsWithNothingNewStillUpgradesAV1File(t *testing.T) {
	path := v1Pulls(t, pullsLineV1)
	if n, err := AppendPullRequests(path, []PullRequest{pull(45, 10)}); err != nil || n != 0 {
		t.Fatalf("want nothing stored, got %d, %v", n, err)
	}
	wantFile(t, path, pullsHead+pullsLineUnknown)
}

// TestAV1PullsLineInAV2FileIsRefused (forsgren#345): a v2 file's lines have
// ten columns; a line of nine is malformed, named by its number, not read as
// unknown.
func TestAV1PullsLineInAV2FileIsRefused(t *testing.T) {
	path := filepath.Join(t.TempDir(), "pulls.csv")
	writeAt(t, path, pullsHead+pullsLine1+pullsLineV1)
	if _, err := LoadPullRequests(path); !malformedOn(err, 4, "10 comma-separated") {
		t.Errorf("want a MalformedError on line 4 naming the 10 columns, got %v", err)
	}
}

// TestABotStatusThatIsNoneOfTheThreeIsRefused (forsgren#345): a record
// whose bot status is not unknown, a person or a bot is ErrInvalidRecord
// naming the column, and nothing is written.
func TestABotStatusThatIsNoneOfTheThreeIsRefused(t *testing.T) {
	path := filepath.Join(t.TempDir(), "pulls.csv")
	_, err := AppendPullRequests(path, []PullRequest{pullBy(45, 10, BotStatus(7))})
	if !refusedFor(err, "record 1: ", "bot") {
		t.Errorf("want ErrInvalidRecord for record 1 naming bot, got %v", err)
	}
	if _, err := os.Stat(path); !notExist(err) {
		t.Errorf("want nothing written, got %v", err)
	}
}
