package collect

import (
	"path/filepath"
	"slices"
	"strconv"
	"strings"
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

// cutDeployments are the deployments of the case whose read is cut off at
// the page limit: the list ends at 250 days, as the one page it reads does.
var cutDeployments = []int{5, 150, 250}

// chunkGitHub is a fake GitHub that lists the deployments of tc: the five of
// chunkDeployments, or, for a read cut off, cutDeployments on a list GitHub
// says goes on.
func chunkGitHub(t *testing.T, tc chunkCase) *gitHub {
	t.Helper()
	g := newGitHub(t)
	ages := chunkDeployments
	if tc.cut {
		ages = cutDeployments
		g.paged[deploymentsPath] = true
	}
	var listed []string
	for _, age := range ages {
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
	cut       bool  // the read of the older chunk stops at the page limit (one page)
}

var chunkCases = []chunkCase{
	{"first run reads one chunk", nil, 0, []int{5}, 100, false},
	{"a later run adds the next older chunk", []int{5}, 100, []int{5, 150}, 200, false},
	{"a fully read history reads no older chunk", []int{5}, 365, []int{5}, 365, false},
	{"the last chunk stops at history_days", []int{5}, 300, []int{5, 320}, 365, false},
	{"history without reach.csv starts at its oldest deployment", []int{5, 150}, 0, []int{5, 150, 250}, 250, false},
	{"a read cut off at the page limit moves reach to the oldest date read", []int{5}, 200, []int{5, 250}, 250, true},
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
			seedChunk(t, path, reachFile, tc)
			cfg := shop(production)
			cfg.HistoryDays, cfg.HistoryChunkDays = 365, 100
			r := chunkGitHub(t, tc).collect(t, cfg, path, tc.maxPages())
			wantChunk(t, path, reachFile, tc)
			wantCutWarning(t, r, tc.cut)
		})
	}
}

// seedChunk writes the history and reach.csv that tc starts from.
func seedChunk(t *testing.T, path, reachFile string, tc chunkCase) {
	t.Helper()
	storeAges(t, path, tc.stored)
	if tc.reachAge == 0 {
		return
	}
	if err := history.SaveReach(reachFile, history.Reach{"acme/app": ago(tc.reachAge)}); err != nil {
		t.Fatal(err)
	}
}

// maxPages is the page limit of tc's run: one page when its read is cut off.
func (tc chunkCase) maxPages() int {
	if tc.cut {
		return 1
	}
	return github.DefaultMaxPages
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

// wantCutWarning fails unless stderr says that older deployments were not
// read exactly when the read was cut off at the page limit.
func wantCutWarning(t *testing.T, r result, cut bool) {
	t.Helper()
	if got := strings.Contains(r.stderr, "older deployments were not read"); got != cut {
		t.Errorf("want the page-limit warning %v, got %v (stderr %q)", cut, got, r.stderr)
	}
}
