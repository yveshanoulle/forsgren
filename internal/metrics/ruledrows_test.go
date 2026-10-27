package metrics

import (
	"slices"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// The rows of a repository with several deployment rules (forsgren#498, step
// 3): each rule is its own service row, labelled by its label, over the
// deployments of its kind and name; paths come from the rule.

// ruledProjects is one project whose repository acme/site has two rules:
// releases (no paths) and the environment github-pages (with website/).
var ruledProjects = []config.Project{{Name: "Acme Site", Repositories: []config.Repository{{
	Name: "acme/site",
	Rules: []config.Rule{
		{Deployment: config.Deployment{Kind: config.Release}, Label: "Releases"},
		{Deployment: config.Deployment{Kind: config.Environment, Name: "github-pages"}, Label: "Site",
			Paths: []string{"website/"}},
	},
}}}}

// ruledRecord is a successful deployment of the repository with the kind and
// name, an hour ago.
func ruledRecord(repository string, kind history.Kind, name string, id int64) history.Record {
	r := deployed(repository, history.StateSuccess, time.Hour)
	r.Kind, r.Name, r.ID = kind, name, id
	return r
}

// ruledCommit is a commit authored two hours before the deployment id of kind
// of acme/site, on the first-parent chain after parent.
func ruledCommit(kind history.Kind, id int64, sha, parent string) history.Commit {
	c := shippedBy("acme/site", id, time.Hour, time.Hour)
	c.Kind, c.SHA, c.Parents = kind, sha, []string{parent}
	return c
}

// ruledData: two releases (IDs 1 and 2), one github-pages deployment (ID 1,
// the same ID as a release, since the IDs are GitHub's per kind), one
// deployment to another environment, and one github-pages deployment of
// another repository. The release 1 shipped r1, the pages deployment p1 (web/
// only) and p2 (website/x.html).
func ruledData() Data {
	return Data{
		Records: []history.Record{
			ruledRecord("acme/site", history.KindRelease, "", 1),
			ruledRecord("acme/site", history.KindRelease, "", 2),
			ruledRecord("ACME/Site", history.KindEnvironment, "github-pages", 1),
			ruledRecord("acme/site", history.KindEnvironment, "staging", 3),
			ruledRecord("acme/other", history.KindEnvironment, "github-pages", 4),
		},
		Commits: []history.Commit{
			ruledCommit(history.KindRelease, 1, "r1", "root"),
			ruledCommit(history.KindEnvironment, 1, "p1", "root"), ruledCommit(history.KindEnvironment, 1, "p2", "p1"),
		},
		CommitFiles: []history.CommitFile{
			{Repository: "acme/site", SHA: "r1", Path: "a.go"},
			{Repository: "acme/site", SHA: "p1", Path: "web/a.go"},
			{Repository: "acme/site", SHA: "p2", Path: "website/x.html"},
		},
	}
}

// TestEveryRuleIsItsOwnRowOverItsOwnDeployments: the rows are the total, then
// Releases and Site; Releases counts the two releases, Site the one
// deployment to github-pages of the repository (not the other repository's,
// not staging's), the total all four of the repository.
func TestEveryRuleIsItsOwnRowOverItsOwnDeployments(t *testing.T) {
	rows := Rows(ruledProjects, ruledData(), now)
	want := []heading{{ProjectRow, "Acme Site"}, {LabelRow, "Releases"}, {LabelRow, "Site"}}
	if got := headingsOf(rows); !slices.Equal(got, want) {
		t.Fatalf("want %v, got %v", want, got)
	}
	counts := []string{rows[0].Frequency.NumberCell(), rows[1].Frequency.NumberCell(), rows[2].Frequency.NumberCell()}
	if wantCounts := []string{"4", "2", "1"}; !slices.Equal(counts, wantCounts) {
		t.Errorf("want deployments %v in the total, Releases and Site, got %v", wantCounts, counts)
	}
}

// TestARuleTbdRowIsAServiceRowWithThePathsOfItsRule: Releases has no paths, so
// it is per repository with both its deployments; Site counts the commit that
// touches website/ only, not p1.
func TestARuleTbdRowIsAServiceRowWithThePathsOfItsRule(t *testing.T) {
	rows := TbdRows(ruledProjects, ruledData(), now, nil)
	want := map[string]ruleFigures{
		"Releases":  {true, 2, serviceFigures{timed: 1, deployed: 1, deployments: 1, perRepository: true}},
		"Site":      {true, 1, serviceFigures{timed: 1, deployed: 1, deployments: 1}},
		"Acme Site": {false, 4, serviceFigures{timed: 3, deployed: 3, deployments: 2}},
	}
	for name, w := range want {
		if got := ruleFiguresOf(tbdRowNamed(t, rows, name)); got != w {
			t.Errorf("%s: want %+v, got %+v", name, w, got)
		}
	}
}

// ruleFigures are what a rule's TBD row shows: whether it is a service row,
// its deployments and the figures of a service row.
type ruleFigures struct {
	service     bool
	volume      int
	serviceFigs serviceFigures
}

func ruleFiguresOf(r TbdRow) ruleFigures {
	return ruleFigures{r.Service && r.IntervalAbsent && r.PushAbsent, r.Volume.Count, pathFiguresOf(r)}
}

// TestARuleRowWaitsForTheFilesOfItsCommits: a commit of the Site rule with no
// stored file is flagged, as for a service.
func TestARuleRowWaitsForTheFilesOfItsCommits(t *testing.T) {
	data := ruledData()
	data.CommitFiles = data.CommitFiles[:2]
	if site := tbdRowNamed(t, TbdRows(ruledProjects, data, now, nil), "Site"); !site.FilesReading {
		t.Errorf("want Site to say its files are still being read")
	}
}

// TestARuleDataKeepsEverySettingOfItsParent: ofRule narrows the deployments,
// the commits and the failure issues, as ofTask does.
func TestARuleDataKeepsEverySettingOfItsParent(t *testing.T) {
	parent := Data{WorkingHours: 7, DoraDays: 90, BandDays: 180, Failures: []history.Failure{{Issue: 1}}}
	child := parent.ofRule("acme/site", config.Deployment{Kind: config.Release})
	if child.WorkingHours != 7 || child.DoraDays != 90 || child.BandDays != 180 || child.Failures != nil {
		t.Errorf("want the settings kept and no failure, got %+v", child)
	}
}

// TestARuleOfEachKindFindsItsDeployments: a workflow rule matches the
// deployments of that workflow file, not those of another file or of an
// environment of the same name.
func TestARuleOfEachKindFindsItsDeployments(t *testing.T) {
	data := Data{Records: []history.Record{
		ruledRecord("acme/site", history.KindWorkflow, "ship.yml", 1),
		ruledRecord("acme/site", history.KindWorkflow, "other.yml", 2),
		ruledRecord("acme/site", history.KindEnvironment, "ship.yml", 3),
	}}
	rule := config.Deployment{Kind: config.Workflow, Name: "ship.yml"}
	if got := data.ofRule("acme/site", rule).Records; len(got) != 1 || got[0].ID != 1 {
		t.Errorf("want the one run of ship.yml, got %+v", got)
	}
}
