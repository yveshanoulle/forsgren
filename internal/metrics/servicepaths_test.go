package metrics

import (
	"fmt"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// The service rows with paths (forsgren#496, step 4, decision #497 A): a
// deployment of a service with paths counts only the commits that touch one
// of them; a service without paths is Per repository on the page.

// pathsProjects is one project whose repository acme/app has two services:
// deploy-api with paths, deploy-admin without.
func pathsProjects(paths ...string) []config.Project {
	return []config.Project{{Name: "Acme Shop", Repositories: []config.Repository{{
		Name:     "acme/app",
		Services: map[string]string{"deploy-api": "API", "deploy-admin": "ADMIN"},
		Paths:    map[string][]string{"deploy-api": paths},
	}}}}
}

// chainCommit is the commit sha of the deployment id of acme/app, deployed an
// hour ago, authored an hour before that, on the first-parent chain after
// parent.
func chainCommit(id int64, sha, parent string) history.Commit {
	c := shippedBy("acme/app", id, time.Hour, time.Hour)
	c.SHA, c.Parents = sha, []string{parent}
	return c
}

// filesOf are the stored files of the commit sha of acme/app; none given is
// the marker line of a commit that was read and changes no file.
func filesOf(sha string, paths ...string) []history.CommitFile {
	if len(paths) == 0 {
		paths = []string{""}
	}
	var out []history.CommitFile
	for _, p := range paths {
		out = append(out, history.CommitFile{Repository: "acme/app", SHA: sha, Path: p})
	}
	return out
}

// pathsData is one deploy-api deployment (1) with the chain c1..c6, one
// deploy-admin deployment (2) with the commit d1, and the stored files of
// each: c1 changes api/x.go (in a folder of the service), c2 web/a.go (in
// none), c3 go.mod (a file of the service), c4 renames web/new.go from
// api/old.go, c5 is read and changes no file, c6 changes apiary/x.go (a
// folder that merely starts like api/); d1 changes web/a.go.
func pathsData() Data {
	commits := []history.Commit{
		chainCommit(1, "c1", "root"), chainCommit(1, "c2", "c1"), chainCommit(1, "c3", "c2"),
		chainCommit(1, "c4", "c3"), chainCommit(1, "c5", "c4"), chainCommit(1, "c6", "c5"),
		chainCommit(2, "d1", "root"),
	}
	var files []history.CommitFile
	for sha, paths := range map[string][]string{
		"c1": {"api/x.go"}, "c2": {"web/a.go"}, "c3": {"go.mod"}, "c4": {"web/new.go", "api/old.go"},
		"c5": nil, "c6": {"apiary/x.go"}, "d1": {"web/a.go"},
	} {
		files = append(files, filesOf(sha, paths...)...)
	}
	return Data{
		Records: []history.Record{
			appDeployment(1, "deploy-api", history.StateSuccess, time.Hour),
			appDeployment(2, "deploy-admin", history.StateSuccess, time.Hour),
		},
		Commits: commits, CommitFiles: files,
	}
}

// serviceFigures are the figures of a service row these tests compare: the
// commits timed, the deployed commits, the deployments counted per deployment
// and the two flags.
type serviceFigures struct {
	timed, deployed, deployments int
	reading, perRepository       bool
}

func pathFiguresOf(r TbdRow) serviceFigures {
	return serviceFigures{r.Deploy.Commits, r.DeployedCommits, r.Deploy.PerDeployment.Count,
		r.FilesReading, r.DeployPerRepository}
}

func apiRow(t *testing.T, projects []config.Project, data Data) TbdRow {
	t.Helper()
	return tbdRowNamed(t, TbdRows(projects, data, now, nil), "API")
}

// TestAServiceWithPathsCountsOnlyTheCommitsThatTouchThem: of the six commits
// of the deployment, the ones changing api/x.go (the folder), go.mod (the
// file) and, by its previous name, api/old.go count: Time to deploy per
// commit has three commits, Commits per deployment is 3, and the service's
// deployed commits are 3. The commits of a rename's new name only, of no file,
// and of a folder that merely starts like the path count for nothing.
func TestAServiceWithPathsCountsOnlyTheCommitsThatTouchThem(t *testing.T) {
	row := apiRow(t, pathsProjects("api/", "go.mod"), pathsData())
	if row.Deploy.Commits != 3 || row.Deploy.TimeToDeploy.Count != 3 {
		t.Errorf("want 3 commits timed, got %d (%d in the spread)", row.Deploy.Commits, row.Deploy.TimeToDeploy.Count)
	}
	if row.Deploy.PerDeployment.Count != 1 || row.Deploy.PerDeployment.Mean != 3 {
		t.Errorf("want one deployment of 3 commits, got %+v", row.Deploy.PerDeployment)
	}
	if row.DeployedCommits != 3 {
		t.Errorf("want 3 deployed commits, got %d", row.DeployedCommits)
	}
}

// TestAPathMatchesAsAFolderPrefixOrAnExactFile: each case is one commit
// changing one file, against the service's paths api/ and go.mod.
func TestAPathMatchesAsAFolderPrefixOrAnExactFile(t *testing.T) {
	for file, want := range map[string]int{
		"api/x.go": 1, "api/deep/er/x.go": 1, "go.mod": 1,
		"apiary/x.go": 0, "api": 0, "go.mod.bak": 0, "sub/go.mod": 0, "Api/x.go": 0, "docs/api/x.go": 0,
	} {
		data := pathsData()
		data.Commits = []history.Commit{chainCommit(1, "c1", "root")}
		data.CommitFiles = filesOf("c1", file)
		if got := apiRow(t, pathsProjects("api/", "go.mod"), data).DeployedCommits; got != want {
			t.Errorf("file %q: want %d deployed commits, got %d", file, want, got)
		}
	}
}

// TestTheFilesOfAnotherRepositoryAreNotTheCommitsOwn: the stored files
// are the commit's of its own repository, compared ignoring case.
func TestTheFilesOfAnotherRepositoryAreNotTheCommitsOwn(t *testing.T) {
	data := pathsData()
	data.Commits = []history.Commit{chainCommit(1, "c1", "root")}
	other := filesOf("c1", "api/x.go")
	other[0].Repository = "acme/other"
	data.CommitFiles = other
	row := apiRow(t, pathsProjects("api/"), data)
	if got, want := pathFiguresOf(row), (serviceFigures{reading: true}); got != want {
		t.Errorf("want no deployed commit and the files still being read, got %+v", got)
	}
	data.CommitFiles = filesOf("c1", "api/x.go")
	data.CommitFiles[0].Repository = "ACME/App"
	if got := apiRow(t, pathsProjects("api/"), data).DeployedCommits; got != 1 {
		t.Errorf("want the repository compared ignoring case, got %d deployed commits", got)
	}
}

// TestACommitWithoutStoredFilesIsLeftOutAndFlagged (decision of this step): a
// commit whose files are not read yet is no figure of the service, and the
// row says the files are still being read; a deployment with such a commit is
// left out of Commits per deployment, since its count would be a part.
func TestACommitWithoutStoredFilesIsLeftOutAndFlagged(t *testing.T) {
	data := pathsData()
	data.Commits = []history.Commit{chainCommit(1, "c1", "root"), chainCommit(1, "c2", "c1")}
	data.CommitFiles = filesOf("c1", "api/x.go")
	row := apiRow(t, pathsProjects("api/"), data)
	if !row.FilesReading {
		t.Errorf("want the row to say the files are still being read")
	}
	if got, want := pathFiguresOf(row), (serviceFigures{timed: 1, deployed: 1, reading: true}); got != want {
		t.Errorf("want 1 commit timed and deployed (the unread one left out), no deployment counted, got %+v", got)
	}
}

// TestOnceItsFilesAreReadACommitIsNoLongerFlagged: with the files of both
// commits stored the row is not waiting, and the deployment has the one commit
// that touches the path.
func TestOnceItsFilesAreReadACommitIsNoLongerFlagged(t *testing.T) {
	data := pathsData()
	data.Commits = []history.Commit{chainCommit(1, "c1", "root"), chainCommit(1, "c2", "c1")}
	data.CommitFiles = append(filesOf("c1", "api/x.go"), filesOf("c2", "web/a.go")...)
	if row := apiRow(t, pathsProjects("api/"), data); row.FilesReading || row.Deploy.PerDeployment.Mean != 1 {
		t.Errorf("want nothing left to read and 1 commit in the deployment, got %v, %+v",
			row.FilesReading, row.Deploy.PerDeployment)
	}
}

// TestAServiceWithoutPathsIsPerRepository: the service deploy-admin has no
// paths, so its deploy figures are the repository's: the row says so, keeps
// its own Deployments, and is not waiting for files.
func TestAServiceWithoutPathsIsPerRepository(t *testing.T) {
	data := pathsData()
	data.CommitFiles = nil
	rows := TbdRows(pathsProjects("api/"), data, now, nil)
	admin, api := tbdRowNamed(t, rows, "ADMIN"), tbdRowNamed(t, rows, "API")
	if !admin.DeployPerRepository || admin.FilesReading {
		t.Errorf("want ADMIN per repository and not waiting for files, got %v, %v",
			admin.DeployPerRepository, admin.FilesReading)
	}
	if admin.Volume.Count != 1 || admin.Deploy.Commits != 1 {
		t.Errorf("want ADMIN's own deployment and commit, got %d, %d", admin.Volume.Count, admin.Deploy.Commits)
	}
	if api.DeployPerRepository {
		t.Errorf("want API, which has paths, not per repository")
	}
}

// TestTotalAndLabelRowsKeepEveryCommitOfTheRepository (decision #497 A): the
// commits outside every service's paths still count at repository level, in
// the total row and in a repository's label row, which are never per
// repository.
func TestTotalAndLabelRowsKeepEveryCommitOfTheRepository(t *testing.T) {
	projects := pathsProjects("api/")
	projects[0].Repositories[0].Label = "App"
	rows := TbdRows(projects, pathsData(), now, nil)
	for _, name := range []string{"Acme Shop", "App"} {
		row := tbdRowNamed(t, rows, name)
		if got, want := pathFiguresOf(row), (serviceFigures{timed: 7, deployed: 7, deployments: 2}); got != want {
			t.Errorf("%s: want the 7 commits and no service flag, got %+v", name, got)
		}
	}
}

// TestAServiceWithPathsKeepsItsDeploymentsWhenNoCommitTouchesThem: a
// deployment whose commits all lie outside the paths is a deployment of 0
// commits, not a missing one.
func TestAServiceWithPathsKeepsItsDeploymentsWhenNoCommitTouchesThem(t *testing.T) {
	row := apiRow(t, pathsProjects("ios/"), pathsData())
	if got, want := pathFiguresOf(row), (serviceFigures{deployments: 1}); got != want {
		t.Errorf("want one deployment of 0 commits and no commit timed, got %+v", got)
	}
}

// TestDeployedCommitsOfTwoDeploymentsAreTheirDistinctCommits: two deployments of 3
// and 1 touching commits, none shared, are 4 deployed commits.
func TestDeployedCommitsOfTwoDeploymentsAreTheirDistinctCommits(t *testing.T) {
	data := pathsData()
	data.Records = append(data.Records, appDeployment(3, "deploy-api", history.StateSuccess, 2*time.Hour))
	extra := shippedBy("acme/app", 3, 2*time.Hour, time.Hour)
	extra.SHA, extra.Parents = "e1", []string{"root"}
	data.Commits = append(data.Commits, extra)
	data.CommitFiles = append(data.CommitFiles, filesOf("e1", fmt.Sprintf("api/%d.go", 1))...)
	row := apiRow(t, pathsProjects("api/", "go.mod"), data)
	if row.DeployedCommits != 4 {
		t.Errorf("want 4 deployed commits, got %d", row.DeployedCommits)
	}
}

// sharedCommitData is the commit c1 (api/x.go) shipped by deploy-api (1) and
// deploy-admin (2) alike, and c2 (web/a.go) by deploy-api alone.
func sharedCommitData() Data {
	data := pathsData()
	data.Commits = []history.Commit{
		chainCommit(1, "c1", "root"), chainCommit(1, "c2", "c1"), chainCommit(2, "c1", "root"),
	}
	data.CommitFiles = append(filesOf("c1", "api/x.go"), filesOf("c2", "web/a.go")...)
	return data
}

// TestACommitShippedByTwoDeploymentsOfAServiceIsDeployedOnce (forsgren#513):
// c1 is in deployments 1 and 3 of deploy-api, a commit counts once, at its
// first deployment, whatever the number of deployments that carry it.
func TestACommitShippedByTwoDeploymentsOfAServiceIsDeployedOnce(t *testing.T) {
	data := sharedCommitData()
	data.Commits = []history.Commit{chainCommit(1, "c1", "root"), chainCommit(3, "c1", "root")}
	data.Records = append(data.Records, appDeployment(3, "deploy-api", history.StateSuccess, 2*time.Hour))
	if got := apiRow(t, pathsProjects("api/"), data).DeployedCommits; got != 1 {
		t.Errorf("want 1 deployed commit, got %d", got)
	}
}

// TestACommitShippedByTwoServicesIsDeployedOnceInTheTotalAndOnceInEach
// (forsgren#513): the total and the repository label count c1 once, each
// service row counts it once.
func TestACommitShippedByTwoServicesIsDeployedOnceInTheTotalAndOnceInEach(t *testing.T) {
	projects := pathsProjects("api/")
	projects[0].Repositories[0].Label = "App"
	projects[0].Repositories[0].Paths["deploy-admin"] = []string{"api/"}
	rows := TbdRows(projects, sharedCommitData(), now, nil)
	for name, want := range map[string]int{"Acme Shop": 2, "App": 2, "API": 1, "ADMIN": 1} {
		if got := tbdRowNamed(t, rows, name).DeployedCommits; got != want {
			t.Errorf("%s: want %d deployed commits, got %d", name, want, got)
		}
	}
}
