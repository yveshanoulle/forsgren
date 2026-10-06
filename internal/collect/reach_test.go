package collect

import (
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// shopWithChunks is the shop of the chunked-read tests: history_days 365 in
// chunks of 100.
func shopWithChunks() config.Config {
	cfg := shop(production)
	cfg.HistoryDays, cfg.HistoryChunkDays = 365, 100
	return cfg
}

// reachFileOf is the reach.csv next to the history at path.
func reachFileOf(path string) string { return filepath.Join(filepath.Dir(path), "reach.csv") }

// TestAReachFileThatCannotBeReadRefusesTheRun (forsgren#57): a reach.csv that
// is not in the format is an error naming it, before GitHub is asked
// anything.
func TestAReachFileThatCannotBeReadRefusesTheRun(t *testing.T) {
	path := historyPath(t)
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(reachFileOf(path), []byte("not a reach file\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	g := chunkGitHub(t, chunkCase{})
	r := g.collect(t, shopWithChunks(), path, github.DefaultMaxPages)
	if !errors.Is(r.err, history.ErrMalformed) || !strings.Contains(r.err.Error(), "reach.csv") {
		t.Errorf("want ErrMalformed naming reach.csv, got %v", r.err)
	}
	if got := g.seen("/"); len(got) != 0 {
		t.Errorf("want GitHub asked nothing, got %v", got)
	}
}

// TestAReachThatCannotBeSavedFailsTheRun (forsgren#57): the deployments are
// stored, and the run's error names reach.csv, like any other history write.
func TestAReachThatCannotBeSavedFailsTheRun(t *testing.T) {
	path := historyPath(t)
	if err := os.MkdirAll(filepath.Join(filepath.Dir(path), "reach.csv.tmp"), 0o750); err != nil {
		t.Fatal(err)
	}
	r := chunkGitHub(t, chunkCase{}).collect(t, shopWithChunks(), path, github.DefaultMaxPages)
	if r.err == nil || !strings.Contains(r.err.Error(), "reach.csv") {
		t.Errorf("want an error naming reach.csv, got %v", r.err)
	}
	if got := storedAges(t, path); !slices.Equal(got, []int{5}) {
		t.Errorf("want the deployment 5 days old stored, got %v", got)
	}
}

// TestAnOlderChunkThatFailsLeavesTheReach (forsgren#57): the older chunk's
// deployment has no statuses on GitHub, so the repository fails, and its
// reach stays where it was.
func TestAnOlderChunkThatFailsLeavesTheReach(t *testing.T) {
	tc := chunkCase{stored: []int{5}, reachAge: 100}
	g := chunkGitHub(t, tc)
	delete(g.bodies, statusesPath("1150"))
	path := historyPath(t)
	seedChunk(t, path, reachFileOf(path), tc)
	r := g.collect(t, shopWithChunks(), path, github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) {
		t.Errorf("want ErrFailed, got %v", r.err)
	}
	reach, err := history.LoadReach(reachFileOf(path))
	if want := ago(100); err != nil || !reach["acme/app"].Equal(want) {
		t.Errorf("want the reach of acme/app still at %s, got %v, %v", want, reach, err)
	}
}
