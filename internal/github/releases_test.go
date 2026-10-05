package github

import (
	"context"
	"slices"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/update"
)

// TestPublishedReleasesListsTagsWithTheirCommits: GET /repos/{o}/{r}/releases
// answers the releases; each published one comes with the commit its tag
// points at, a draft with its flag and no commit (the fake has no commit for
// its tag, so asking for it would be a missing tag).
func TestPublishedReleasesListsTagsWithTheirCommits(t *testing.T) {
	f := newFake(t)
	f.on(releasesPath, reply{body: `[` +
		`{"id": 3, "tag_name": "v0.3.0", "draft": true, "prerelease": false},` +
		`{"id": 2, "tag_name": "v0.2.2", "draft": false, "prerelease": false},` +
		`{"id": 1, "tag_name": "v0.2.1", "draft": false, "prerelease": false}]`})
	f.on("/repos/acme/app/commits/tags/v0.2.2", reply{body: shaD})
	f.on("/repos/acme/app/commits/tags/v0.2.1", reply{body: shaBase})
	got, err := f.client(t, DefaultMaxPages).PublishedReleases(context.Background(), "acme/app")
	if err != nil {
		t.Fatal(err)
	}
	want := []update.Published{
		{Tag: "v0.3.0", Draft: true},
		{Tag: "v0.2.2", SHA: shaD},
		{Tag: "v0.2.1", SHA: shaBase},
	}
	if !slices.Equal(got, want) {
		t.Errorf("want %+v, got %+v", want, got)
	}
}

// TestPublishedReleasesNamesAMissingTag: a published release whose tag has no
// commit is the error of TagCommit, naming the tag, and no list.
func TestPublishedReleasesNamesAMissingTag(t *testing.T) {
	f := newFake(t)
	f.on(releasesPath, reply{body: `[{"id": 2, "tag_name": "v0.2.2", "draft": false, "prerelease": false}]`})
	got, err := f.client(t, DefaultMaxPages).PublishedReleases(context.Background(), "acme/app")
	wantError(t, err, ErrMissingTag, "acme/app: ", "tag v0.2.2 not found")
	if got != nil {
		t.Errorf("want no list, got %+v", got)
	}
}
