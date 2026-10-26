package github

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"time"
)

// Commit is one commit of a comparison (forsgren#16, step 2): its SHA and
// its author date (commit.author.date, the git author date, not the
// committer date, which a rebase or a merge button moves) and its author's
// GitHub login.
//
// Author is the login of the top-level author object of GitHub's answer, the
// account GitHub links the commit to, a bot as GitHub names it
// (dependabot[bot]); empty when that object is null, a commit whose email
// GitHub links to no account (forsgren#273, decision 274). It is never read
// from commit.author, which holds the name and the email as git records them:
// neither is read or stored.
//
// Parents are the SHAs of the commit's parents in GitHub's order, the first
// parent first: the line a merge was made on, then the line it brought in;
// none for a root commit (forsgren#254). CommittedAt is the git committer
// date (commit.committer.date) in UTC, when the commit was made where it is
// now (a rebase, a merge button); zero when GitHub gives none, which its
// schema allows. Following first parents with the committer date is how
// mainline commits and their landing are told apart from the branch commits
// a merge brought in.
type Commit struct {
	SHA         string
	AuthoredAt  time.Time
	Author      string
	Parents     []string
	CommittedAt time.Time
}

// The statuses of a comparison GitHub documents.
const (
	statusAhead     = "ahead"
	statusIdentical = "identical"
	statusBehind    = "behind"
	statusDiverged  = "diverged"
)

// comparison is one page of GitHub's answer, the fields Compare reads.
type comparison struct {
	Status       string         `json:"status"`
	TotalCommits int            `json:"total_commits"`
	Commits      []answerCommit `json:"commits"`
}

// answerCommit is one commit of GitHub's answer, the fields Compare reads.
// A null committer, or a null date, leaves the date zero.
type answerCommit struct {
	commitHead
	Commit struct {
		Author struct {
			Date time.Time `json:"date"`
		} `json:"author"`
		Committer struct {
			Date time.Time `json:"date"`
		} `json:"committer"`
	} `json:"commit"`
	Parents []struct {
		SHA string `json:"sha"`
	} `json:"parents"`
}

// Compare lists the commits after base up to and including head, oldest
// first, as GitHub orders them: GET /repos/{owner}/{repo}/compare/
// {base}...{head}, 100 per page, following Link rel="next". It says whether
// the list is cut: at the page limit, or shorter than GitHub's
// total_commits.
//
//   - base and head must each be 40 lower-case hex digits (ErrCommitSHA),
//     checked before any URL is made; the same SHA twice is no commits and
//     no request.
//   - a head behind its base, or diverged from it, is ErrNotAncestor,
//     naming both SHAs, never an empty list.
//   - a 404 or 422 is a commit GitHub does not have (ErrMissingCommit),
//     naming both SHAs, not the token's access.
//
// The status codes, total_commits and the page order are GitHub's REST
// reference, pinned against made-up answers only, not checked against
// live GitHub (docs/data-files.md, Collecting deployments).
func (c *Client) Compare(ctx context.Context, repo, base, head string) ([]Commit, bool, error) {
	s := span{repo: repo, base: base, head: head}
	if err := s.check(); err != nil || base == head {
		return nil, false, err
	}
	t, err := c.endpoint(repo, url.Values{}, "compare", base+"..."+head)
	if err != nil {
		return nil, false, err
	}
	var r comparisonReader
	truncated, err := c.list(ctx, t, r.page)
	if err != nil {
		return nil, false, s.missing(t, err)
	}
	return r.result(s, truncated)
}

// span is a comparison: the repository and its two ends.
type span struct{ repo, base, head string }

// check refuses a base or head that is not a 40-hex SHA.
func (s span) check() error {
	for _, sha := range []string{s.base, s.head} {
		if len(sha) != 40 || !isSHA(sha) {
			return fmt.Errorf("%s: %w: %q", s.repo, ErrCommitSHA, sha)
		}
	}
	return nil
}

// comparisonReader gathers the pages of one comparison: the first page's
// status and total, and the commits of every page.
type comparisonReader struct {
	status  string
	total   int
	commits []Commit
}

// page reads one page. A head that is not ahead stops the list, which
// result then refuses.
func (r *comparisonReader) page(body []byte) (bool, error) {
	var page comparison
	if err := json.Unmarshal(body, &page); err != nil {
		return false, err
	}
	if !isStatus(page.Status) {
		return false, fmt.Errorf("status %q is not one GitHub documents", page.Status)
	}
	if r.status == "" {
		r.status, r.total = page.Status, page.TotalCommits
	}
	if page.Status != statusAhead {
		return false, nil
	}
	return len(page.Commits) > 0, r.add(page)
}

// add keeps the commits of one page; each needs a SHA and an author date,
// and every parent a SHA.
func (r *comparisonReader) add(page comparison) error {
	for _, pc := range page.Commits {
		if !isSHA(pc.SHA) || pc.Commit.Author.Date.IsZero() {
			return fmt.Errorf("commit %q has no SHA or no author date", pc.SHA)
		}
		parents, err := pc.parents()
		if err != nil {
			return err
		}
		r.commits = append(r.commits, Commit{SHA: pc.SHA, AuthoredAt: pc.Commit.Author.Date.UTC(),
			Author: pc.login(), Parents: parents, CommittedAt: pc.Commit.Committer.Date.UTC()})
	}
	return nil
}

// commitHead is what a commit of GitHub's answers (a comparison, a pull
// request's commit list) carries first: its SHA and the top-level author
// object, the account GitHub links the commit to, null when it links none.
type commitHead struct {
	SHA    string `json:"sha"`
	Author *struct {
		Login string `json:"login"`
	} `json:"author"`
}

// login is the login of the commit's GitHub author, empty when it is null.
func (h commitHead) login() string {
	if h.Author == nil {
		return ""
	}
	return h.Author.Login
}

// parents is the SHAs of the commit's parents in GitHub's order, none for a
// root commit; a parent without a SHA refuses the answer.
func (pc answerCommit) parents() ([]string, error) {
	var shas []string
	for _, p := range pc.Parents {
		if !isSHA(p.SHA) {
			return nil, fmt.Errorf("commit %s has a parent %q that is no SHA", pc.SHA, p.SHA)
		}
		shas = append(shas, p.SHA)
	}
	return shas, nil
}

// result is the commits read, cut when the pages were or when fewer were
// read than GitHub's total; a head that is not ahead is ErrNotAncestor.
func (r *comparisonReader) result(s span, truncated bool) ([]Commit, bool, error) {
	if r.status != statusAhead && r.status != statusIdentical {
		return nil, false, fmt.Errorf("%s: %w: %s...%s is %s", s.repo, ErrNotAncestor, s.base, s.head, r.status)
	}
	return r.commits, truncated || len(r.commits) < r.total, nil
}

// isStatus says whether s is a status of a comparison.
func isStatus(s string) bool {
	switch s {
	case statusAhead, statusIdentical, statusBehind, statusDiverged:
		return true
	}
	return false
}

// missing names both SHAs when GitHub does not have one of them; any
// other error is the client's own.
func (s span) missing(t target, err error) error {
	missing, ok := errors.AsType[*answerError](err)
	if !ok || !isMissingRef(missing.code) {
		return err
	}
	return fmt.Errorf("%s: %w: %s or %s not found: %s for %s; was history rewritten?",
		t.repo, ErrMissingCommit, s.base, s.head, missing.status(), t.path())
}
