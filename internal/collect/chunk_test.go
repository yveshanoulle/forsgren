package collect

import (
	"path/filepath"
	"slices"
	"strconv"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// ago is the moment days days before now, the day's start.
func ago(days int) time.Time { return now.Add(-time.Duration(days) * 24 * time.Hour) }

// chunkDeployments are the deployments GitHub lists for acme/app in the
// chunked-read tests, newest first, 5, 150, 250, 320 and 400 days old, each
// with the ID 1000 plus its age and a successful status.
var chunkDeployments = []int{5, 150, 250, 320, 400}

// chunkGitHub is a fake GitHub that lists chunkDeployments.
func chunkGitHub(t *testing.T) *gitHub {
	t.Helper()
	g := newGitHub(t)
	var listed []string
	for _, age := range chunkDeployments {
		id := int64(1000 + age)
		created := ago(age).Format(time.RFC3339)
		listed = append(listed, deployment(id, shaA, "deploy", created))
		g.bodies[statusesPath(strconv.FormatInt(id, 10))] = list(status(id, "success", created))
	}
	g.bodies[deploymentsPath] = list(listed...)
	return g
}

// chunkCase is one run of the chunked read (forsgren#57): the deployments of
// the history and the reach.csv row before it (0 for none), and after it.
type chunkCase struct {
	name      string
	stored    []int // ages of the stored deployments
	reachAge  int   // 0: no reach.csv
	wantAges  []int // ages of the stored deployments after the run
	wantReach int   // age of the reach after the run
}

var chunkCases = []chunkCase{
	{"first run reads one chunk", nil, 0, []int{5}, 100},
	{"a later run adds the next older chunk", []int{5}, 100, []int{5, 150}, 200},
	{"a fully read history reads no older chunk", []int{5}, 365, []int{5}, 365},
	{"the last chunk stops at history_days", []int{5}, 300, []int{5, 320}, 365},
	{"history without reach.csv starts at its oldest deployment", []int{5, 150}, 0, []int{5, 150, 250}, 250},
}

// storeAges writes the deployments of the given ages to the history at path.
func storeAges(t *testing.T, path string, ages []int) {
	t.Helper()
	var records []history.Record
	for _, age := range ages {
		records = append(records, record(history.KindEnvironment, "production", int64(1000+age), shaA,
			ago(age), history.StateSuccess, "deploy"))
	}
	if _, err := history.Append(path, records); err != nil {
		t.Fatal(err)
	}
}

// storedAges are the ages of the deployments in the history at path.
func storedAges(t *testing.T, path string) []int {
	t.Helper()
	records, err := history.Load(path)
	if err != nil {
		t.Fatal(err)
	}
	var ages []int
	for _, r := range records {
		ages = append(ages, int(r.ID)-1000)
	}
	slices.Sort(ages)
	return ages
}

// TestEachRunReadsOneChunkOfHistory (forsgren#57): the first run of a
// repository reads history_chunk_days back and notes it in reach.csv; each
// later run reads what is new and one older chunk, until history_days is
// reached, the last chunk cut there.
func TestEachRunReadsOneChunkOfHistory(t *testing.T) {
	for _, tc := range chunkCases {
		t.Run(tc.name, func(t *testing.T) {
			path := historyPath(t)
			reachFile := filepath.Join(filepath.Dir(path), "reach.csv")
			storeAges(t, path, tc.stored)
			if tc.reachAge != 0 {
				if err := history.SaveReach(reachFile, history.Reach{"acme/app": ago(tc.reachAge)}); err != nil {
					t.Fatal(err)
				}
			}
			cfg := shop(production)
			cfg.HistoryDays, cfg.HistoryChunkDays = 365, 100
			chunkGitHub(t).collect(t, cfg, path, github.DefaultMaxPages)
			wantChunk(t, path, reachFile, tc)
		})
	}
}

// wantChunk fails unless the history and reach.csv are what tc wants.
func wantChunk(t *testing.T, path, reachFile string, tc chunkCase) {
	t.Helper()
	if got := storedAges(t, path); !slices.Equal(got, tc.wantAges) {
		t.Errorf("want the deployments %v days old stored, got %v", tc.wantAges, got)
	}
	reach, err := history.LoadReach(reachFile)
	if want := ago(tc.wantReach); err != nil || !reach["acme/app"].Equal(want) {
		t.Errorf("want the reach of acme/app at %s, got %v, %v", want, reach, err)
	}
}
