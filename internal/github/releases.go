package github

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/yveshanoulle/forsgren/internal/update"
)

// PublishedReleases lists the releases of repo with the commit each tag
// points at: GET /repos/{owner}/{repo}/releases, the first page of 100 only,
// which is enough for the newest releases of forsgren, newest first. A draft
// and a prerelease are listed with their flags and no SHA; the tag of every
// other release is resolved to its commit by TagCommit.
func (c *Client) PublishedReleases(ctx context.Context, repo string) ([]update.Published, error) {
	t, err := c.endpoint(repo, nil, "releases")
	if err != nil {
		return nil, err
	}
	body, _, err := c.get(ctx, t, jsonMedia)
	if err != nil {
		return nil, err
	}
	var listed []listedRelease
	if err := json.Unmarshal(body, &listed); err != nil {
		return nil, fmt.Errorf("%s: %w for %s: %w", repo, ErrAnswer, t.path(), err)
	}
	return withCommits(listed, func(tag string) (string, error) { return c.TagCommit(ctx, repo, tag) })
}

// listedRelease is an item of GitHub's list of releases: the tag and the
// state PublishedRelease reads.
type listedRelease struct {
	TagName string `json:"tag_name"`
	releaseState
}

// withCommits makes the update.Published of each listed release, the commit
// of a published one asked of commit, whose error, which names the
// repository and the tag, is returned as it is.
func withCommits(listed []listedRelease, commit func(string) (string, error)) ([]update.Published, error) {
	releases := make([]update.Published, 0, len(listed))
	for _, r := range listed {
		p := update.Published{Tag: r.TagName, Draft: r.Draft, Prerelease: r.Prerelease}
		if r.published() {
			sha, err := commit(r.TagName)
			if err != nil {
				return nil, err
			}
			p.SHA = sha
		}
		releases = append(releases, p)
	}
	return releases, nil
}
