package github

import (
	"context"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"testing"
	"time"
)

const (
	deploymentsPath = "/repos/acme/app/deployments"
	statusesPath    = "/repos/acme/app/deployments/1003/statuses"
	runsPath        = "/repos/acme/app/actions/workflows/deploy.yml/runs"
	releasesPath    = "/repos/acme/app/releases"
	shaD            = "dddddddddddddddddddddddddddddddddddddddd"
)

func at(day, hour, minute, second int) time.Time {
	return time.Date(2026, 9, day, hour, minute, second, 0, time.UTC)
}

// wantQuery fails unless the one request the fake saw has every key of want
// with that value.
func wantQuery(t *testing.T, f *fakeGitHub, want url.Values) {
	t.Helper()
	seen := f.seen()
	if len(seen) != 1 {
		t.Fatalf("want 1 request, got %d", len(seen))
	}
	got := seen[0].URL.Query()
	for name := range want {
		if got.Get(name) != want.Get(name) {
			t.Errorf("want query %s=%q, got %q (query %q)", name, want.Get(name), got.Get(name), seen[0].URL.RawQuery)
		}
	}
}

// TestDeploymentsReadsOneEnvironment: GET /repos/{owner}/{repo}/deployments
// with the environment and 100 per page; id, sha, task and created_at read.
func TestDeploymentsReadsOneEnvironment(t *testing.T) {
	f := newFake(t)
	f.on(deploymentsPath, reply{body: fixture(t, "deployments.json")})
	got, truncated, err := f.client(t, DefaultMaxPages).Deployments(context.Background(), "acme/app", "prod east", since)
	if err != nil || truncated {
		t.Fatalf("want the deployments, got truncated=%v, %v", truncated, err)
	}
	want := []Deployment{
		{ID: 1003, SHA: "cccccccccccccccccccccccccccccccccccccccc", Task: "deploy", CreatedAt: at(20, 10, 0, 0)},
		{ID: 1002, SHA: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", Task: "deploy:migrations", CreatedAt: at(10, 8, 30, 0)},
		{ID: 1001, SHA: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", Task: "deploy", CreatedAt: at(1, 7, 0, 0)},
	}
	if !slices.Equal(got, want) {
		t.Errorf("want %v, got %v", want, got)
	}
	wantQuery(t, f, url.Values{"environment": {"prod east"}, "per_page": {"100"}})
}

// TestDeploymentStatusesReadsEveryStatus: GET .../deployments/{id}/statuses.
func TestDeploymentStatusesReadsEveryStatus(t *testing.T) {
	f := newFake(t)
	f.on(statusesPath, reply{body: fixture(t, "deployment-statuses.json")})
	got, err := f.client(t, DefaultMaxPages).DeploymentStatuses(context.Background(), "acme/app", 1003)
	if err != nil {
		t.Fatal(err)
	}
	want := []DeploymentStatus{
		{ID: 3, State: "inactive", CreatedAt: at(21, 9, 0, 0)},
		{ID: 2, State: "success", CreatedAt: at(20, 10, 5, 0)},
	}
	if !slices.Equal(got, want) {
		t.Errorf("want %v, got %v", want, got)
	}
	wantQuery(t, f, url.Values{"per_page": {"100"}})
}

// TestDefaultBranchReadsTheRepository: GET /repos/{owner}/{repo}.
func TestDefaultBranchReadsTheRepository(t *testing.T) {
	f := newFake(t)
	f.on("/repos/acme/app", reply{body: fixture(t, "repository.json")})
	got, err := f.client(t, DefaultMaxPages).DefaultBranch(context.Background(), "acme/app")
	if err != nil || got != "trunk" {
		t.Errorf("want trunk, got %q, %v", got, err)
	}
}

// TestARepositoryWithoutADefaultBranchIsRefused: the runs of no branch
// would be asked for every branch.
func TestARepositoryWithoutADefaultBranchIsRefused(t *testing.T) {
	f := newFake(t)
	f.on("/repos/acme/app", reply{body: `{"full_name": "acme/app", "default_branch": ""}`})
	_, err := f.client(t, DefaultMaxPages).DefaultBranch(context.Background(), "acme/app")
	wantError(t, err, ErrAnswer, "acme/app: ", "no default_branch")
}

// TestRunsReadsOneWorkflowOnOneBranch: GET
// .../actions/workflows/{file}/runs, filtered by branch and, a day early so
// no time zone loses a run, by creation date.
func TestRunsReadsOneWorkflowOnOneBranch(t *testing.T) {
	f := newFake(t)
	f.on(runsPath, reply{body: fixture(t, "workflow-runs.json")})
	c := f.client(t, DefaultMaxPages)
	got, truncated, err := c.Runs(context.Background(), "acme/app", "deploy.yml", "trunk", since)
	if err != nil || truncated {
		t.Fatalf("want the runs, got truncated=%v, %v", truncated, err)
	}
	finished := Run{ID: 5002, HeadSHA: shaD, HeadBranch: "trunk", Status: "completed", Conclusion: "success",
		CreatedAt: at(15, 12, 0, 0), RunStartedAt: at(15, 12, 0, 5)}
	going := Run{ID: 5001, HeadSHA: "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", HeadBranch: "trunk", Status: "in_progress",
		CreatedAt: at(14, 12, 0, 0), RunStartedAt: at(14, 12, 0, 7)}
	finished.HeadRepository.FullName, going.HeadRepository.FullName = "acme/app", "acme/app"
	if want := []Run{finished, going}; !slices.Equal(got, want) {
		t.Errorf("want %+v, got %+v", want, got)
	}
	wantQuery(t, f, url.Values{"branch": {"trunk"}, "created": {">=2026-07-31"}, "per_page": {"100"}})
}

// TestReleasesKeepsADraftWithoutATime: GET /repos/{owner}/{repo}/releases;
// a draft has no published_at and is not dropped here.
func TestReleasesKeepsADraftWithoutATime(t *testing.T) {
	f := newFake(t)
	f.on(releasesPath, reply{body: fixture(t, "releases.json")})
	got, truncated, err := f.client(t, DefaultMaxPages).Releases(context.Background(), "acme/app", since)
	if err != nil || truncated {
		t.Fatalf("want the releases, got truncated=%v, %v", truncated, err)
	}
	want := []Release{
		{ID: 9003, TagName: "v1.3.0", Draft: true},
		{ID: 9002, TagName: "v1.2.0", PublishedAt: at(18, 9, 30, 0)},
		{ID: 9001, TagName: "v1.2.0-rc.1", Prerelease: true, PublishedAt: at(12, 9, 10, 0)},
	}
	if !slices.Equal(got, want) {
		t.Errorf("want %v, got %v", want, got)
	}
}

// TestTagCommitAsksForTheSHAOnly: GET .../commits/tags/{tag} with the sha
// media type answers the commit's SHA as plain text, an annotated tag
// resolved to its commit.
func TestTagCommitAsksForTheSHAOnly(t *testing.T) {
	f := newFake(t)
	f.on("/repos/acme/app/commits/tags/v1.2.0", reply{body: shaD})
	got, err := f.client(t, DefaultMaxPages).TagCommit(context.Background(), "acme/app", "v1.2.0")
	if err != nil || got != shaD {
		t.Fatalf("want %s, got %q, %v", shaD, got, err)
	}
	if accept := f.seen()[0].Header.Get("Accept"); accept != "application/vnd.github.sha" {
		t.Errorf("want Accept application/vnd.github.sha, got %q", accept)
	}
}

// TestTagCommitRefusesAnAnswerThatIsNotASHA: the answer is stored as a
// commit, so anything but a SHA is refused by name.
func TestTagCommitRefusesAnAnswerThatIsNotASHA(t *testing.T) {
	f := newFake(t)
	f.on("/repos/acme/app/commits/tags/v1.2.0", reply{body: `{"sha":"` + shaD + `"}`})
	_, err := f.client(t, DefaultMaxPages).TagCommit(context.Background(), "acme/app", "v1.2.0")
	wantError(t, err, ErrAnswer, "acme/app", "tag v1.2.0")
}

// TestAMissingTagIsNamedNotTheToken: commits/tags/{tag} answers 404 or 422
// for a tag that is not there (deleted after its release was published);
// collect reads the releases with the same token just before, so the error
// names the tag and not the token's access (forsgren#12, step 8). A 403 is
// still the token's.
func TestAMissingTagIsNamedNotTheToken(t *testing.T) {
	tagPath := "/repos/acme/app/commits/tags/v1.2.0"
	for code, status := range map[int]string{404: "404 Not Found", 422: "422 Unprocessable Entity"} {
		f := newFake(t)
		f.on(tagPath, reply{status: code, body: `{"message":"No commit found for SHA: v1.2.0"}`})
		_, err := f.client(t, DefaultMaxPages).TagCommit(context.Background(), "acme/app", "v1.2.0")
		if err == nil {
			t.Fatalf("%d: want an error, got none", code)
		}
		for _, part := range []string{"acme/app: ", "tag v1.2.0 not found", status, tagPath, "deleted"} {
			if !strings.Contains(err.Error(), part) {
				t.Errorf("%d: want %q in the error %q", code, part, err)
			}
		}
		if strings.Contains(err.Error(), "FORSGREN_TOKEN") {
			t.Errorf("%d: want the tag named, not the token, got %q", code, err)
		}
	}
	f := newFake(t)
	f.on(tagPath, reply{status: 403})
	_, err := f.client(t, DefaultMaxPages).TagCommit(context.Background(), "acme/app", "v1.2.0")
	wantError(t, err, ErrAccess, "check FORSGREN_TOKEN's access to acme/app")
}

// TestAnUnknownPathIsGitHubsNotFound: the fake answers a path it does not
// know as GitHub does, 404, which reaches the caller as an access error.
func TestAnUnknownPathIsGitHubsNotFound(t *testing.T) {
	f := newFake(t)
	_, _, err := f.client(t, DefaultMaxPages).Releases(context.Background(), "acme/app", since)
	wantError(t, err, ErrAccess, "404 Not Found", releasesPath)
	if got := f.seen(); len(got) != 1 || got[0].Method != http.MethodGet {
		t.Errorf("want one GET, got %d requests", len(got))
	}
}

// TestLatestReleaseAsksForTheLatestOne (forsgren#40, step 4): GET
// .../releases/latest answers the latest published release.
func TestLatestReleaseAsksForTheLatestOne(t *testing.T) {
	f := newFake(t)
	f.on("/repos/acme/app/releases/latest",
		reply{body: `{"id": 7, "tag_name": "v1.2.0", "published_at": "2026-10-04T08:00:00Z"}`})
	got, err := f.client(t, DefaultMaxPages).LatestRelease(context.Background(), "acme/app")
	if err != nil {
		t.Fatal(err)
	}
	published := time.Date(2026, 10, 4, 8, 0, 0, 0, time.UTC)
	if want := (Release{ID: 7, TagName: "v1.2.0", PublishedAt: published}); got != want {
		t.Errorf("want %+v, got %+v", want, got)
	}
}

// TestAClientWithoutATokenSendsNoAuthorization (forsgren#40, step 4): a
// public repository is read with no token, and never with an empty Bearer.
func TestAClientWithoutATokenSendsNoAuthorization(t *testing.T) {
	f := newFake(t)
	f.on("/repos/acme/app/releases/latest", reply{body: `{"id": 7, "tag_name": "v1.2.0"}`})
	c, err := New(f.srv.URL, "", DefaultMaxPages)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := c.LatestRelease(context.Background(), "acme/app"); err != nil {
		t.Fatal(err)
	}
	if auth := f.seen()[0].Header.Get("Authorization"); auth != "" {
		t.Errorf("want no Authorization header, got %q", auth)
	}
}
