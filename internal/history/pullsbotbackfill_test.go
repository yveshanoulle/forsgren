package history

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// The fill of the bot status of the stored pull requests (forsgren#500).

// botLine is pullsLine1 with the bot column bot.
func botLine(number, bot string) string {
	return "acme/app," + number + ",2026-09-01T08:00:00Z,2026-09-02T10:00:00Z," + mergeSHA +
		",2026-09-03T12:00:00Z,2026-08-31T07:00:00Z,false,false," + bot + "\n"
}

// writePulls writes text as pulls.csv under a temporary directory.
func writePulls(t *testing.T, text string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "pulls.csv")
	writeAt(t, path, text)
	return path
}

// TestBackfillPullBotsSetsTheStatusOfAnUnknownPullRequestAlone: an unknown
// line gets the known status, a known one is not touched even when the map
// says otherwise, and every other column and the order stay.
func TestBackfillPullBotsSetsTheStatusOfAnUnknownPullRequestAlone(t *testing.T) {
	path := writePulls(t, pullsHead+botLine("45", "")+botLine("46", "")+botLine("47", "false")+botLine("48", ""))
	other := pullBy(46, 11, ByHuman)
	other.Repository = "Acme/App"
	known := []PullRequest{pullBy(45, 10, ByBot), other, pullBy(47, 12, ByBot), pullBy(48, 13, BotUnknown)}
	changed, err := BackfillPullBots(path, known)
	if err != nil || changed != 2 {
		t.Fatalf("want 2 lines changed, got %d, %v", changed, err)
	}
	wantFile(t, path, pullsHead+botLine("45", "true")+botLine("46", "false")+botLine("47", "false")+botLine("48", ""))
}

// TestBackfillPullBotsWritesNothingWhenNothingChanged: the file keeps its
// bytes, and its modification time, when no line changed.
func TestBackfillPullBotsWritesNothingWhenNothingChanged(t *testing.T) {
	path := writePulls(t, pullsHead+botLine("45", ""))
	old := time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC)
	if err := os.Chtimes(path, old, old); err != nil {
		t.Fatal(err)
	}
	changed, err := BackfillPullBots(path, []PullRequest{pullBy(45, 10, BotUnknown)})
	if err != nil || changed != 0 {
		t.Fatalf("want nothing changed, got %d, %v", changed, err)
	}
	info, err := os.Stat(path)
	if err != nil || !info.ModTime().Equal(old) {
		t.Errorf("want the file untouched (%v), got %v, %v", old, info, err)
	}
}

// TestBackfillPullBotsRewritesAV1FileOnceAsV2: a v1 file is written whole in
// the current version, unknown kept unknown, as the first append does.
func TestBackfillPullBotsRewritesAV1FileOnceAsV2(t *testing.T) {
	path := writePulls(t, pullsHeadV1+pullsLineV1)
	if changed, err := BackfillPullBots(path, nil); err != nil || changed != 0 {
		t.Fatalf("want nothing changed, got %d, %v", changed, err)
	}
	wantFile(t, path, pullsHead+pullsLineUnknown)
}

// TestBackfillPullBotsOfAMissingFileIsNothing: no file is created.
func TestBackfillPullBotsOfAMissingFileIsNothing(t *testing.T) {
	path := filepath.Join(t.TempDir(), "pulls.csv")
	known := []PullRequest{pullBy(45, 10, ByBot)}
	if changed, err := BackfillPullBots(path, known); err != nil || changed != 0 {
		t.Fatalf("want nothing changed, got %d, %v", changed, err)
	}
	if _, err := os.Stat(path); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("want no file created, got %v", err)
	}
}

// TestThePullsBotFilledMarkFileRoundTrips: one time per repository under its
// own version line; a missing file is empty.
func TestThePullsBotFilledMarkFileRoundTrips(t *testing.T) {
	path := filepath.Join(t.TempDir(), "pulls_bot_filled.csv")
	if got, err := LoadPullsBotFilled(path); err != nil || len(got) != 0 {
		t.Fatalf("want an empty mark for a missing file, got %v, %v", got, err)
	}
	at := time.Date(2026, 10, 27, 6, 0, 0, 0, time.UTC)
	if err := SavePullsBotFilled(path, Reach{"acme/app": at}); err != nil {
		t.Fatal(err)
	}
	wantFile(t, path, "# forsgren pulls bot filled v1\nrepository,filled_at\nacme/app,2026-10-27T06:00:00Z\n")
	got, err := LoadPullsBotFilled(path)
	if err != nil || !got["acme/app"].Equal(at) {
		t.Errorf("want acme/app at %v, got %v, %v", at, got, err)
	}
}
