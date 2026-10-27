package metrics

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// The cells of the TBD page's new groups (forsgren#397, step 5): numbers only,
// a dash where a value is not shown.

// TestDurationSpreadCells: durations in shortDuration's words; the median is
// a dash below two times and the p90 below ten, the mean a dash for none.
func TestDurationSpreadCells(t *testing.T) {
	m := time.Minute
	for name, c := range map[string]struct {
		in   DurationSpread
		want [3]string
	}{
		"none": {DurationSpread{}, [3]string{"-", "-", "-"}},
		"one":  {DurationSpread{Count: 1, Mean: 7 * m}, [3]string{"7 m", "-", "-"}},
		"two":  {DurationSpread{Count: 2, Mean: 15 * m, Median: 15 * m}, [3]string{"15 m", "15 m", "-"}},
		"ten": {DurationSpread{Count: 10, Mean: 90 * m, Median: 3 * time.Hour, P90: 2 * day},
			[3]string{"1 h 30", "3 h", "2 d"}},
		"a clock": {DurationSpread{Count: 3, Mean: 0, Median: 0}, [3]string{"< 1 m", "< 1 m", "-"}},
	} {
		got := [3]string{c.in.MeanCell(), c.in.MedianCell(), c.in.P90Cell()}
		if got != c.want {
			t.Errorf("%s: want %v, got %v", name, c.want, got)
		}
	}
}

// TestPushMeasuresCells: the volume, the shares like 99%, dashes without a
// commit.
func TestPushMeasuresCells(t *testing.T) {
	m := PushMeasures{Pushes: 12, Commits: 200, PullRequests: 20, Direct: 180, UnknownAuthors: 199, Bots: 4}
	got := [6]string{m.CommitsCell(), m.PushesCell(), m.DirectCell(), m.PullRequestCell(), m.UnknownAuthorCell(),
		m.BotCell()}
	if want := [6]string{"200", "12", "90%", "10%", "99%", "2.0%"}; got != want {
		t.Errorf("want %v, got %v", want, got)
	}
	none := PushMeasures{Pushes: 3}
	got = [6]string{none.CommitsCell(), none.PushesCell(), none.DirectCell(), none.PullRequestCell(),
		none.UnknownAuthorCell(), none.BotCell()}
	if want := [6]string{"0", "3", "-", "-", "-", "-"}; got != want {
		t.Errorf("without a commit: want %v, got %v", want, got)
	}
}

// TestShareCellsShowTwoSignificantDigitsRoundedDown (forsgren#477): from 10% a
// whole percent, from 1% one decimal always shown, under 1% two decimals, 0
// as 0%, each from the counts, never from a rounded figure, at every edge of
// a band.
func TestShareCellsShowTwoSignificantDigitsRoundedDown(t *testing.T) {
	for _, c := range []struct {
		part, whole int
		want        string
	}{
		{0, 1722, "0%"},
		{1, 20000, "< 0.01%"},
		{1, 10000, "0.01%"},
		{11, 1722, "0.63%"},
		{99, 10000, "0.99%"},
		{999, 100000, "0.99%"},
		{1, 100, "1.0%"},
		{13, 1000, "1.3%"},
		{3, 100, "3.0%"},
		{999, 10000, "9.9%"},
		{99, 1000, "9.9%"},
		{1, 10, "10%"},
		{19, 100, "19%"},
		{199, 1000, "19%"},
		{9999, 10000, "99%"},
		{100, 100, "100%"},
	} {
		m := PushMeasures{Commits: c.whole, Direct: c.part, PullRequests: c.part, UnknownAuthors: c.part, Bots: c.part}
		got := [4]string{m.DirectCell(), m.PullRequestCell(), m.UnknownAuthorCell(), m.BotCell()}
		if want := [4]string{c.want, c.want, c.want, c.want}; got != want {
			t.Errorf("%d of %d: want %s, got %v", c.part, c.whole, c.want, got)
		}
	}
}

// TestPushMeasuresStatesTakeThePushCellsAndNeverShowNumbers: a project not
// readable says so, one not collected says that, with a dash for the volume.
func TestPushMeasuresStatesTakeThePushCellsAndNeverShowNumbers(t *testing.T) {
	for name, c := range map[string]struct {
		in    PushMeasures
		state string
	}{
		"fine":          {PushMeasures{Pushes: 2, Commits: 5}, ""},
		"not readable":  {PushMeasures{NotReadable: true, Pushes: 2, Commits: 5}, "Push activity not readable"},
		"not collected": {PushMeasures{Uncollected: true}, "Pushes not collected yet"},
	} {
		if c.in.State() != c.state {
			t.Errorf("%s: want the state %q, got %q", name, c.state, c.in.State())
		}
		if c.state != "" && (c.in.CommitsCell() != "-" || c.in.PushesCell() != "-") {
			t.Errorf("%s: want dashes for the volume, got %q, %q", name, c.in.CommitsCell(), c.in.PushesCell())
		}
	}
}

// release and workflow are made-up repositories measured by a release and by
// workflow runs.
func projectOf(name string, kinds ...config.DeploymentKind) config.Project {
	p := config.Project{Name: name}
	for i, k := range kinds {
		p.Repositories = append(p.Repositories, config.Repository{Name: "acme/r" + name + string(rune('a'+i)),
			Deployment: config.Deployment{Kind: k}})
	}
	return p
}

// TestDeploymentVolumesAreTheSuccessesOfTheWindowAsANumber (forsgren#397
// ruling): the Deployments cell is the successful deployments of the DORA
// window, a bare number for every project, releases included (forsgren#403:
// 87, never "87 releases").
func TestDeploymentVolumesAreTheSuccessesOfTheWindowAsANumber(t *testing.T) {
	ps := []config.Project{
		projectOf("Rel", config.Release), projectOf("Mix", config.Release, config.Workflow),
		projectOf("Env", config.Environment), projectOf("One", config.Release),
	}
	rec := func(repository string, n int) []history.Record {
		out := make([]history.Record, n)
		for i := range out {
			out[i] = deployed(repository, history.StateSuccess, time.Duration(i+1)*time.Hour)
		}
		return out
	}
	var records []history.Record
	records = append(records, rec(ps[0].Repositories[0].Name, 2)...)
	records = append(records, rec(ps[1].Repositories[0].Name, 3)...)
	records = append(records, rec(ps[2].Repositories[0].Name, 4)...)
	records = append(records, rec(ps[3].Repositories[0].Name, 1)...)
	records = append(records, deployed(ps[0].Repositories[0].Name, history.StateSuccess, 40*day))
	got := DeploymentVolumes(ps, Data{Records: records}, now)
	cells := [4]string{got[0].Cell(), got[1].Cell(), got[2].Cell(), got[3].Cell()}
	if want := [4]string{"2", "3", "4", "1"}; cells != want {
		t.Errorf("want %v, got %v", want, cells)
	}
	if got[0].Project != "Rel" {
		t.Errorf("want the project's name, got %+v", got[0])
	}
}
