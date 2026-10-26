package github

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"strconv"
	"time"
)

// pullCommitsCap is the most commits GitHub lists for one pull request
// (GET pulls/{n}/commits, GitHub's REST reference): a list that long may
// have left commits out, the first one among them.
const pullCommitsCap = 250

// PullCommit is one commit of a pull request's commit list (forsgren#463,
// step 5): its SHA, the login of GitHub's top-level author object, empty when
// it is null (never the name or email of commit.author), and the git author
// date in UTC.
type PullCommit struct {
	SHA        string
	Author     string
	AuthoredAt time.Time
}

// pullCommit is one item of GitHub's answer, the fields PullCommits reads.
type pullCommit struct {
	SHA    string `json:"sha"`
	Author *struct {
		Login string `json:"login"`
	} `json:"author"`
	Commit struct {
		Author struct {
			Date time.Time `json:"date"`
		} `json:"author"`
	} `json:"commit"`
}

// login is the login of the commit's GitHub author, empty when it is null.
func (pc pullCommit) login() string {
	if pc.Author == nil {
		return ""
	}
	return pc.Author.Login
}

// PullCommits are the commits of pull request number of repo (forsgren#255,
// step 2, for PR Lead Time, merged time minus first commit time, whose first
// commit time collect takes as the earliest of them), in the list's
// order, each with its git author date (commit.author.date, when the commit
// was made, never the committer date, which a rebase or a merge button
// moves) in UTC and the login of its GitHub author. GET
// /repos/{owner}/{repo}/pulls/{number}/commits, 100 per page, every page up
// to the limit. It says whether the answer is cut: at the page limit, or
// with 250 commits or more read, GitHub's cap for this list, where the first
// commit may be left out. A 403 is ErrAccess and ErrPullRequestsDenied
// (explainDenied), a rate limit stays ErrRateLimit. No commit, or a commit
// with no author date, is ErrAnswer and ErrNoCommitDate naming the pull
// request; a page that cannot be read is ErrAnswer alone (decision #313).
func (c *Client) PullCommits(ctx context.Context, repo string, number int64) ([]PullCommit, bool, error) {
	t, err := c.endpoint(repo, url.Values{}, "pulls", strconv.FormatInt(number, 10), "commits")
	if err != nil {
		return nil, false, err
	}
	r := pullCommitReader{number: number}
	truncated, err := c.list(ctx, t, r.page)
	if err != nil {
		return nil, false, c.explainDenied(repo, t, err)
	}
	return r.result(t, truncated)
}

// pullCommitReader gathers the pages of one pull request's commits.
type pullCommitReader struct {
	number  int64
	commits []PullCommit
}

// page reads one page and asks for the next while pages are not empty.
func (r *pullCommitReader) page(body []byte) (bool, error) {
	var page []pullCommit
	if err := json.Unmarshal(body, &page); err != nil {
		return false, err
	}
	for _, pc := range page {
		authored := pc.Commit.Author.Date
		if authored.IsZero() {
			return false, fmt.Errorf("%w: commit %q of pull request %d has no author date", ErrNoCommitDate, pc.SHA,
				r.number)
		}
		r.commits = append(r.commits, PullCommit{SHA: pc.SHA, Author: pc.login(), AuthoredAt: authored.UTC()})
	}
	return len(page) > 0, nil
}

// result is the commits read, cut when the pages were or when GitHub's cap
// was reached; a pull request with no commit is ErrAnswer and
// ErrNoCommitDate.
func (r *pullCommitReader) result(t target, truncated bool) ([]PullCommit, bool, error) {
	if len(r.commits) == 0 {
		return nil, false, fmt.Errorf("%s: %w for %s: %w: pull request %d has no commits",
			t.repo, ErrAnswer, t.path(), ErrNoCommitDate, r.number)
	}
	return r.commits, truncated || len(r.commits) >= pullCommitsCap, nil
}
