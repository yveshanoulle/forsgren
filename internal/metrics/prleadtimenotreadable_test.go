package metrics

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// refusedAt is when collect was refused a pull request read in these tests.
var refusedAt = time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC)

// notReadableOf is, per project of projects in its order, whether its
// PR Lead Time is not readable with pulls and the refusals denied.
func notReadableOf(projects []config.Project, pulls []history.PullRequest, denied history.Reach) []bool {
	leads := PRLeadTimes(projects, Data{Pulls: pulls, PullsDenied: denied}, now)
	got := make([]bool, len(leads))
	for i, l := range leads {
		got[i] = l.NotReadable
	}
	return got
}

// TestPRLeadTimeIsNotReadableWhenARepositoryWasRefused (forsgren#337,
// step 2): a project with a repository whose pull request read collect was
// refused (data/pulls_denied.csv) is not readable as a whole, even with the
// merged pull requests of its other repositories (decision: one refused
// repository makes the whole cell not readable); the other projects are not
// touched; a refused repository whose earlier pull requests are stored is
// not readable all the same; a refusal of a repository no project lists any
// more is ignored; no refusal, nothing not readable.
func TestPRLeadTimeIsNotReadableWhenARepositoryWasRefused(t *testing.T) {
	pulls := append(shopPulls(5, 30), mergedPull("acme/cli", 9, time.Hour, time.Hour))
	cases := map[string]struct {
		denied history.Reach
		want   []bool
	}{
		"none":                 {nil, []bool{false, false}},
		"one of two refused":   {history.Reach{"acme/api": refusedAt}, []bool{true, false}},
		"the only one refused": {history.Reach{"acme/cli": refusedAt}, []bool{false, true}},
		"an unlisted one":      {history.Reach{"acme/gone": refusedAt}, []bool{false, false}},
		"every one refused": {history.Reach{"acme/app": refusedAt, "acme/api": refusedAt, "acme/cli": refusedAt},
			[]bool{true, true}},
		"its own pulls stored": {history.Reach{"acme/app": refusedAt}, []bool{true, false}},
	}
	for name, c := range cases {
		got := notReadableOf(projects, pulls, c.denied)
		if got[0] != c.want[0] || got[1] != c.want[1] {
			t.Errorf("%s: want not readable %v, got %v", name, c.want, got)
		}
	}
}

// TestPRLeadTimeComparesRefusedRepositoriesWithoutCase (forsgren#337,
// step 2, decision #339): pulls_denied.csv keys a repository in lower case,
// and the config may write it otherwise, so they are compared without case,
// whichever side has the capitals.
func TestPRLeadTimeComparesRefusedRepositoriesWithoutCase(t *testing.T) {
	mixed := []config.Project{{Name: "Acme Shop", Repositories: []config.Repository{{Name: "Acme/API"}}}}
	for name, denied := range map[string]history.Reach{
		"config in capitals": {"acme/api": refusedAt},
		"file in capitals":   {"ACME/api": refusedAt},
	} {
		if got := notReadableOf(mixed, nil, denied); !got[0] {
			t.Errorf("%s: want Acme Shop not readable, got %v", name, got)
		}
	}
}

// TestPRLeadTimeStateSaysNotReadable (forsgren#337, step 2): a project
// not readable has the state "Pull requests not readable", never a lead time of
// the repositories that were read nor the dash of no pull request.
func TestPRLeadTimeStateSaysNotReadable(t *testing.T) {
	const want = "Pull requests not readable"
	for name, lead := range map[string]PRLeadTime{
		"no pull request":    {NotReadable: true},
		"pull requests read": {NotReadable: true, PullRequests: 2, Mean: time.Hour, Median: time.Hour},
	} {
		if got := lead.State(); got != want {
			t.Errorf("%s: want %q, got %q", name, want, got)
		}
	}
}
