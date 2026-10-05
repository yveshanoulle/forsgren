package github

import (
	"context"
	"encoding/base64"
	"testing"
)

// TestFileAtDecodesTheContentOfAFileAtARef: GET .../contents/{path}?ref=
// answers the content base64-encoded in lines of 60, which is decoded, and the
// ref is the query's.
func TestFileAtDecodesTheContentOfAFileAtARef(t *testing.T) {
	const want = "jobs:\n  metrics:\n    uses: yveshanoulle/forsgren/.github/workflows/metrics.yml@abc # v0.1.3\n"
	encoded := base64.StdEncoding.EncodeToString([]byte(want))
	f := newFake(t)
	f.on("/repos/acme/data/contents/.github/workflows/forsgren.yml",
		reply{body: `{"type": "file", "encoding": "base64", "content": "` + encoded[:60] + `\n` + encoded[60:] + `\n"}`})
	got, found, err := f.client(t, DefaultMaxPages).FileAt(context.Background(), "acme/data",
		FileRef{Ref: baseCommit, Path: ".github/workflows/forsgren.yml"})
	if err != nil || !found || got != want {
		t.Fatalf("want %q, found, got %q, %v, %v", want, got, found, err)
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
	got, found, err := f.client(t, DefaultMaxPages).FileAt(context.Background(), "acme/data", at)
	if err != nil || found || got != "" {
		t.Errorf("want not found and no error, got %q, %v, %v", got, found, err)
	}
	f.on("/repos/acme/data/contents/"+at.Path, reply{status: 500, body: `{"message": "boom"}`})
	_, _, err = f.client(t, DefaultMaxPages).FileAt(context.Background(), "acme/data", at)
	wantError(t, err, ErrStatus, "acme/data: ")
}
