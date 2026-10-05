package github

import (
	"context"
	"encoding/base64"
	"testing"
)

// fileRead is what FileAt answered, with the error as whether there was one.
type fileRead struct {
	content string
	found   bool
	failed  bool
}

// readFile is FileAt's answer for at in acme/data.
func readFile(c *Client, at FileRef) fileRead {
	content, found, err := c.FileAt(context.Background(), "acme/data", at)
	return fileRead{content: content, found: found, failed: err != nil}
}

// TestFileAtDecodesTheContentOfAFileAtARef: GET .../contents/{path}?ref=
// answers the content base64-encoded in lines of 60, which is decoded, and the
// ref is the query's.
func TestFileAtDecodesTheContentOfAFileAtARef(t *testing.T) {
	const want = "jobs:\n  metrics:\n    uses: yveshanoulle/forsgren/.github/workflows/metrics.yml@abc # v0.1.3\n"
	encoded := base64.StdEncoding.EncodeToString([]byte(want))
	f := newFake(t)
	f.on("/repos/acme/data/contents/.github/workflows/forsgren.yml",
		reply{body: `{"type": "file", "encoding": "base64", "content": "` + encoded[:60] + `\n` + encoded[60:] + `\n"}`})
	got := readFile(f.client(t, DefaultMaxPages), FileRef{Ref: baseCommit, Path: ".github/workflows/forsgren.yml"})
	if got != (fileRead{content: want, found: true}) {
		t.Fatalf("want %q found, got %+v", want, got)
	}
	if ref := f.seen()[0].URL.Query().Get("ref"); ref != baseCommit {
		t.Errorf("want ref %s, got %q", baseCommit, ref)
	}
}

// TestFileAtIsNotFoundForAFileThatIsNotThere: a 404 is no error, only found
// false; a 500 is one.
func TestFileAtIsNotFoundForAFileThatIsNotThere(t *testing.T) {
	f := newFake(t)
	at := FileRef{Ref: "main", Path: ".github/workflows/forsgren-update.yml"}
	if got := readFile(f.client(t, DefaultMaxPages), at); got != (fileRead{}) {
		t.Errorf("want not found and no error, got %+v", got)
	}
	f.on("/repos/acme/data/contents/"+at.Path, reply{status: 500, body: `{"message": "boom"}`})
	_, _, err := f.client(t, DefaultMaxPages).FileAt(context.Background(), "acme/data", at)
	wantError(t, err, ErrStatus, "acme/data: ")
}

// TestFileAtRefusesWhatItCannotRead: a name that is not one owner/name never
// becomes a request, and an answer that is no JSON or whose content is no
// base64 is an answer error naming the repository and the path.
func TestFileAtRefusesWhatItCannotRead(t *testing.T) {
	path := "/repos/acme/data/contents/forsgren.config.yml"
	at := FileRef{Ref: "main", Path: "forsgren.config.yml"}
	f := newFake(t)
	_, _, err := f.client(t, DefaultMaxPages).FileAt(context.Background(), "acme", at)
	wantError(t, err, ErrRepositoryName)
	for _, body := range []string{`{"content": 7}`, `{"content": "***"}`} {
		f.on(path, reply{body: body})
		_, _, err = f.client(t, DefaultMaxPages).FileAt(context.Background(), "acme/data", at)
		wantError(t, err, ErrAnswer, "acme/data: ", path)
	}
}
