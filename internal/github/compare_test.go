package github

import (
	"context"
	"errors"
	"net/http"
	"net/url"
	"slices"
	"strconv"
	"strings"
	"testing"
)

const (
	shaBase     = "1111111111111111111111111111111111111111"
	shaMiddle   = "2222222222222222222222222222222222222222"
	shaHead     = "3333333333333333333333333333333333333333"
	shaLater    = "4444444444444444444444444444444444444444"
	comparePath = "/repos/acme/app/compare/" + shaBase + "..." + shaHead
)

// comparePage is a page of a comparison with status, total_commits and the
// commits of shas, each authored on 2026-09-03 at 07:00.
func comparePage(status string, total int, shas ...string) string {
	commits := make([]string, 0, len(shas))
	for _, sha := range shas {
		commits = append(commits, `{"sha": "`+sha+`", "commit": {"author": {"name": "Acme Dev", `+
			`"email": "dev@acme.example", "date": "2026-09-03T07:00:00Z"}, "message": "More"}}`)
	}
	return `{"status": "` + status + `", "ahead_by": ` + strconv.Itoa(total) + `, "behind_by": 0, ` +
		`"total_commits": ` + strconv.Itoa(total) + `, "commits": [` + strings.Join(commits, ", ") + `], "files": []}`
}

// compare runs Compare of base and head on acme/app.
func compare(c *Client, base, head string) ([]Commit, bool, error) {
	return c.Compare(context.Background(), "acme/app", base, head)
}

// compared is what one Compare returned.
type compared struct {
	commits   []Commit
	truncated bool
	err       error
}

// compareOf runs compare and keeps its three results together.
func compareOf(c *Client, base, head string) compared {
	commits, truncated, err := compare(c, base, head)
	return compared{commits, truncated, err}
}

// TestCompareReadsTheCommitsOldestFirst: GET .../compare/{base}...{head},
// 100 per page; each commit's SHA and its author date, not its committer
// date, in GitHub's order, oldest first.
func TestCompareReadsTheCommitsOldestFirst(t *testing.T) {
	f := newFake(t)
	f.on(comparePath, reply{body: fixture(t, "compare.json")})
	got, truncated, err := compare(f.client(t, DefaultMaxPages), shaBase, shaHead)
	if err != nil || truncated {
		t.Fatalf("want the commits, got truncated=%v, %v", truncated, err)
	}
	want := []Commit{{SHA: shaMiddle, AuthoredAt: at(1, 8, 0, 0)}, {SHA: shaHead, AuthoredAt: at(1, 9, 30, 0)}}
	if !slices.Equal(got, want) {
		t.Errorf("want %v, got %v", want, got)
	}
	wantQuery(t, f, url.Values{"per_page": {"100"}})
}

// TestCompareFollowsTheLinkNext: the comparison pages its commits; page 2
// comes after page 1, still oldest first.
func TestCompareFollowsTheLinkNext(t *testing.T) {
	f := newFake(t)
	f.on(comparePath, reply{header: next(comparePath, "2"), body: comparePage("ahead", 3, shaMiddle, shaHead)})
	f.onPage(comparePath, "2", reply{body: comparePage("ahead", 3, shaLater)})
	got, truncated, err := compare(f.client(t, DefaultMaxPages), shaBase, shaHead)
	if err != nil || truncated {
		t.Fatalf("want every page, got truncated=%v, %v", truncated, err)
	}
	if shas := commitSHAs(got); !slices.Equal(shas, []string{shaMiddle, shaHead, shaLater}) {
		t.Errorf("want the commits of both pages in order, got %v", shas)
	}
}

func commitSHAs(commits []Commit) []string {
	shas := make([]string, 0, len(commits))
	for _, c := range commits {
		shas = append(shas, c.SHA)
	}
	return shas
}

// wantCount fails unless Compare succeeded with n commits, cut or not as
// cut says.
func wantCount(t *testing.T, r compared, n int, cut bool) {
	t.Helper()
	if r.err != nil {
		t.Fatalf("want %d commits, got %v", n, r.err)
	}
	if len(r.commits) != n {
		t.Errorf("want %d commits, got %v", n, r.commits)
	}
	if r.truncated != cut {
		t.Errorf("want truncated=%v, got %v", cut, r.truncated)
	}
}

// TestCompareStopsAtThePageLimit: a very large comparison is cut, and the
// caller is told, as a cut list of deployments is.
func TestCompareStopsAtThePageLimit(t *testing.T) {
	f := newFake(t)
	f.on(comparePath, reply{header: next(comparePath, "2"), body: comparePage("ahead", 3, shaMiddle, shaHead)})
	r := compareOf(f.client(t, 1), shaBase, shaHead)
	wantCount(t, r, 2, true)
	if n := len(f.seen()); n != 1 {
		t.Errorf("want 1 request, got %d", n)
	}
}

// TestCompareCountsFewerCommitsThanTheTotalAsCut: GitHub says how many
// commits the comparison has; fewer read is a cut list, never a whole one.
func TestCompareCountsFewerCommitsThanTheTotalAsCut(t *testing.T) {
	f := newFake(t)
	f.on(comparePath, reply{body: comparePage("ahead", 5, shaMiddle, shaHead)})
	r := compareOf(f.client(t, DefaultMaxPages), shaBase, shaHead)
	wantCount(t, r, 2, true)
}

// TestCompareOfACommitWithItselfIsEmpty: nothing between them, no request.
func TestCompareOfACommitWithItselfIsEmpty(t *testing.T) {
	f := newFake(t)
	r := compareOf(f.client(t, DefaultMaxPages), shaHead, shaHead)
	wantCount(t, r, 0, false)
	if n := len(f.seen()); n != 0 {
		t.Errorf("want no request, got %d", n)
	}
}

// TestCompareRefusesABaseThatIsNotAnAncestor: a head behind its base, or
// diverged from it (a force-push, a deployment of another branch), has no
// commits "since the previous deployment"; an error naming both SHAs, never
// an empty list.
func TestCompareRefusesABaseThatIsNotAnAncestor(t *testing.T) {
	for _, status := range []string{"behind", "diverged"} {
		t.Run(status, func(t *testing.T) {
			f := newFake(t)
			f.on(comparePath, reply{body: comparePage(status, 1, shaMiddle)})
			got, _, err := compare(f.client(t, DefaultMaxPages), shaBase, shaHead)
			wantError(t, err, ErrNotAncestor, "acme/app: ", shaBase, shaHead, status)
			if got != nil {
				t.Errorf("want no commits, got %v", got)
			}
		})
	}
}

// TestCompareNamesAMissingCommitNotTheToken: GitHub answers 404 for a SHA it
// does not have (history rewritten); the repository was read with the same
// token, so the error names the commits, not the token's access.
func TestCompareNamesAMissingCommitNotTheToken(t *testing.T) {
	f := newFake(t)
	f.on(comparePath, reply{status: http.StatusNotFound, body: `{"message":"Not Found"}`})
	_, _, err := compare(f.client(t, DefaultMaxPages), shaBase, shaHead)
	wantError(t, err, ErrMissingCommit, "acme/app: ", shaBase, shaHead, "404 Not Found")
	if strings.Contains(err.Error(), "FORSGREN_TOKEN") {
		t.Errorf("want the commits named, not the token, got %q", err)
	}
	f.on(comparePath, reply{status: http.StatusForbidden})
	_, _, err = compare(f.client(t, DefaultMaxPages), shaBase, shaHead)
	wantError(t, err, ErrAccess, "check FORSGREN_TOKEN's access to acme/app")
}

// TestCompareChecksTheSHAsBeforeAnyRequest: only 40 lower-case hex digits
// become part of a URL.
func TestCompareChecksTheSHAsBeforeAnyRequest(t *testing.T) {
	for _, sha := range []string{
		"", "main", "abc", strings.ToUpper(shaD), shaHead + "0", "../../x", shaHead + shaHead[:24],
	} {
		f := newFake(t)
		c := f.client(t, DefaultMaxPages)
		for _, pair := range [][2]string{{sha, shaHead}, {shaBase, sha}} {
			_, _, err := compare(c, pair[0], pair[1])
			if !errors.Is(err, ErrCommitSHA) || !strings.Contains(err.Error(), "acme/app") {
				t.Errorf("%q: want ErrCommitSHA naming acme/app, got %v", sha, err)
			}
		}
		if n := len(f.seen()); n != 0 {
			t.Errorf("%q: want no request, got %d", sha, n)
		}
	}
}

// TestCompareRefusesAnAnswerItCannotStore: a commit without a SHA or an
// author date, or a status GitHub does not document, is refused by the
// repository's name.
func TestCompareRefusesAnAnswerItCannotStore(t *testing.T) {
	page := comparePage("ahead", 1, shaMiddle)
	for name, body := range map[string]string{
		"no SHA":         strings.Replace(page, shaMiddle, "", 1),
		"no author date": strings.Replace(page, `"date": "2026-09-03T07:00:00Z"`, `"date": null`, 1),
		"unknown status": comparePage("sideways", 1, shaMiddle),
		"not JSON":       `{"status": "ahead", "commits": [`,
	} {
		t.Run(name, func(t *testing.T) {
			f := newFake(t)
			f.on(comparePath, reply{body: body})
			_, _, err := compare(f.client(t, DefaultMaxPages), shaBase, shaHead)
			wantError(t, err, ErrAnswer, "acme/app: ", comparePath)
		})
	}
}
