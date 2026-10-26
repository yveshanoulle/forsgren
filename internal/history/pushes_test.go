package history

import (
	"path/filepath"
	"testing"
	"time"
)

const (
	pushesHead = "# forsgren pushes v1\nrepository,pushed_at,before,after,kind,bot,commits\n"
	pushBefore = "1111111111111111111111111111111111111111"
	pushAfter  = "2222222222222222222222222222222222222222"
	pushLine1  = "acme/app,2026-09-02T10:00:00Z," + pushBefore + "," + pushAfter + ",push,false,3\n"
)

// push is a push of acme/app to main at hour hours of 2026-09-02, by a
// person, that added 3 commits; its after SHA is pushAfter.
func push(hours int) Push {
	return Push{Repository: "acme/app", PushedAt: time.Date(2026, 9, 2, hours, 0, 0, 0, time.UTC),
		Before: pushBefore, After: pushAfter, Kind: "push", Bot: ByHuman, Commits: 3}
}

// wantPushes fails unless the pushes at path are want, in file order.
func wantPushes(t *testing.T, path string, want []Push) {
	t.Helper()
	wantLoaded(t, path, LoadPushes, want)
}

// TestAPushIsWrittenOnceByRepositoryAfterAndTime (forsgren#397, step 2):
// data/pushes.csv is created, directory included, with its version and
// column lines; a push already held (repository ignoring case, after SHA and
// time) is not written again, whatever else it says, so the first line stays.
func TestAPushIsWrittenOnceByRepositoryAfterAndTime(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data", "pushes.csv")
	if n, err := AppendPushes(path, []Push{push(10)}); err != nil || n != 1 {
		t.Fatalf("want 1 line written, got %d, %v", n, err)
	}
	again := push(10)
	again.Repository, again.Commits, again.Kind = "ACME/app", 5, "pr_merge"
	if n, err := AppendPushes(path, []Push{again, push(11)}); err != nil || n != 1 {
		t.Errorf("want the held push skipped and the one of another time written, got %d, %v", n, err)
	}
	wantFile(t, path, pushesHead+pushLine1+
		"acme/app,2026-09-02T11:00:00Z,"+pushBefore+","+pushAfter+",push,false,3\n")
	wantPushes(t, path, []Push{push(10), push(11)})
}

// TestAPushKeepsAnUnknownBotAndNoCommitCount: the bot column is empty for
// unknown, the commits column empty when the count is not known (never 0);
// the kinds force_push and pr_merge are kept.
func TestAPushKeepsAnUnknownBotAndNoCommitCount(t *testing.T) {
	path := filepath.Join(t.TempDir(), "pushes.csv")
	a, b := push(10), push(11)
	a.Bot, a.Commits, a.Kind = BotUnknown, 0, "force_push"
	b.Bot, b.Kind = ByBot, "pr_merge"
	if n, err := AppendPushes(path, []Push{a, b}); err != nil || n != 2 {
		t.Fatalf("want 2 lines written, got %d, %v", n, err)
	}
	wantFile(t, path, pushesHead+
		"acme/app,2026-09-02T10:00:00Z,"+pushBefore+","+pushAfter+",force_push,,\n"+
		"acme/app,2026-09-02T11:00:00Z,"+pushBefore+","+pushAfter+",pr_merge,true,3\n")
	wantPushes(t, path, []Push{a, b})
}

// TestNewPushesAreWrittenInTimeOrder: given out of order, new lines go in
// pushed time order.
func TestNewPushesAreWrittenInTimeOrder(t *testing.T) {
	path := filepath.Join(t.TempDir(), "pushes.csv")
	if n, err := AppendPushes(path, []Push{push(12), push(10), push(11)}); err != nil || n != 3 {
		t.Fatalf("want 3 lines written, got %d, %v", n, err)
	}
	wantPushes(t, path, []Push{push(10), push(11), push(12)})
}

// TestAPushThatCannotBeStoredIsRefused: each broken field is refused, naming
// it.
func TestAPushThatCannotBeStoredIsRefused(t *testing.T) {
	for name, c := range map[string]struct {
		spoil func(*Push)
		word  string
	}{
		"repository": {func(p *Push) { p.Repository = "app" }, "repository"},
		"time":       {func(p *Push) { p.PushedAt = time.Time{} }, "pushed_at"},
		"fraction":   {func(p *Push) { p.PushedAt = p.PushedAt.Add(time.Millisecond) }, "pushed_at"},
		"before":     {func(p *Push) { p.Before = "abc" }, "before"},
		"after":      {func(p *Push) { p.After = "" }, "after"},
		"kind":       {func(p *Push) { p.Kind = "branch_creation" }, "kind"},
		"commits":    {func(p *Push) { p.Commits = -1 }, "commits"},
	} {
		t.Run(name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "pushes.csv")
			p := push(10)
			c.spoil(&p)
			n, err := AppendPushes(path, []Push{p})
			if n != 0 || !refusedFor(err, c.word) {
				t.Errorf("want %s refused, got %d, %v", c.word, n, err)
			}
		})
	}
}

// TestAMalformedPushesFileIsRefusedOnRead: a bad commits column names its
// line.
func TestAMalformedPushesFileIsRefusedOnRead(t *testing.T) {
	path := filepath.Join(t.TempDir(), "pushes.csv")
	writeAt(t, path, pushesHead+"acme/app,2026-09-02T10:00:00Z,"+pushBefore+","+pushAfter+",push,false,many\n")
	if _, err := LoadPushes(path); !malformedOn(err, 3, "commits") {
		t.Errorf("want line 3 refused for commits, got %v", err)
	}
}

// TestAMalformedTimeOrBotOfAPushesFileIsRefusedOnRead: each names its column
// and its line.
func TestAMalformedTimeOrBotOfAPushesFileIsRefusedOnRead(t *testing.T) {
	for column, line := range map[string]string{
		"pushed_at": "acme/app,yesterday," + pushBefore + "," + pushAfter + ",push,false,3\n",
		"bot":       "acme/app,2026-09-02T10:00:00Z," + pushBefore + "," + pushAfter + ",push,maybe,3\n",
	} {
		path := filepath.Join(t.TempDir(), "pushes.csv")
		writeAt(t, path, pushesHead+line)
		if _, err := LoadPushes(path); !malformedOn(err, 3, column) {
			t.Errorf("want line 3 refused for %s, got %v", column, err)
		}
	}
}
