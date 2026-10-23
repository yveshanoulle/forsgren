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

// pullCommit is one item of GitHub's answer, the fields FirstCommitTime
// reads: the SHA, for an error only, and the git author date.
type pullCommit struct {
	SHA    string `json:"sha"`
	Commit struct {
		Author struct {
			Date time.Time `json:"date"`
		} `json:"author"`
	} `json:"commit"`
}

// FirstCommitTime is the first commit time of pull request number of repo
// (forsgren#255, step 2), for Mainline Lead Time, merged time minus first
// commit time: the earliest git author date (commit.author.date, when the
// commit was made, never the committer date, which a rebase or a merge
// button moves) of its commits, in UTC. GET
// /repos/{owner}/{repo}/pulls/{number}/commits, 100 per page, every page up
// to the limit. It says whether the answer is cut: at the page limit, or
// with 250 commits or more read, GitHub's cap for this list, where the first
// commit may be left out. A 403 is ErrAccess and ErrPullRequestsDenied
// (explainDenied), a rate limit stays ErrRateLimit. No commit, or a commit
// with no author date, is ErrAnswer and ErrNoCommitDate naming the pull
// request; a page that cannot be read is ErrAnswer alone (decision #313).
func (c *Client) FirstCommitTime(ctx context.Context, repo string, number int64) (time.Time, bool, error) {
	t, err := c.endpoint(repo, url.Values{}, "pulls", strconv.FormatInt(number, 10), "commits")
	if err != nil {
		return time.Time{}, false, err
	}
	r := firstCommitReader{number: number}
	truncated, err := c.list(ctx, t, r.page)
	if err != nil {
		return time.Time{}, false, explainDenied(repo, t, err)
	}
	return r.result(t, truncated)
}

// firstCommitReader gathers the pages of one pull request's commits: how
// many were read and the earliest author date among them.
type firstCommitReader struct {
	number int64
	read   int
	first  time.Time
}

// page reads one page and asks for the next while pages are not empty.
func (r *firstCommitReader) page(body []byte) (bool, error) {
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
		if r.read == 0 || authored.Before(r.first) {
			r.first = authored.UTC()
		}
		r.read++
	}
	return len(page) > 0, nil
}

// result is the earliest author date read, cut when the pages were or when
// GitHub's cap was reached; a pull request with no commit is ErrAnswer and
// ErrNoCommitDate.
func (r *firstCommitReader) result(t target, truncated bool) (time.Time, bool, error) {
	if r.read == 0 {
		return time.Time{}, false, fmt.Errorf("%s: %w for %s: %w: pull request %d has no commits",
			t.repo, ErrAnswer, t.path(), ErrNoCommitDate, r.number)
	}
	return r.first, truncated || r.read >= pullCommitsCap, nil
}
