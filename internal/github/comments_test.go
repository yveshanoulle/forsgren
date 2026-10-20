package github

import (
	"context"
	"net/url"
	"slices"
	"strconv"
	"testing"
)

const commentsPath = "/repos/acme/app/issues/42/comments"

// commentItem is one item of a page of comments: body is JSON (null for none).
func commentItem(id int, body string) string {
	return `{"id": ` + strconv.Itoa(id) + `, "user": {"login": "acme-dev"}, ` +
		`"created_at": "2026-09-20T10:00:00Z", "body": ` + body + `}`
}

// commentRecords runs CommentRecords on acme/app issue 42.
func commentRecords(c *Client) ([]FailureRecord, bool, error) {
	return c.CommentRecords(context.Background(), "acme/app", 42)
}

// TestCommentRecordsReadsTheBlockOfEachComment (forsgren#37): GET
// /repos/{o}/{r}/issues/{n}/comments, 100 per page; one record per comment,
// in the order GitHub lists them (oldest first), a comment without a block
// or without a body an empty record. Fragments of different comments are
// never combined.
func TestCommentRecordsReadsTheBlockOfEachComment(t *testing.T) {
	f := newFake(t)
	f.on(commentsPath, reply{body: "[" +
		commentItem(1, `"Looking into it."`) + "," +
		commentItem(2, `"failure-start: 2026-09-20T09:12+02:00\r\nfailed-build: 12.345"`) + "," +
		commentItem(3, `null`) + "," +
		commentItem(4, `"fixed-build: 12.346"`) + "]"})
	got, truncated, err := commentRecords(f.client(t, DefaultMaxPages))
	if err != nil || truncated {
		t.Fatalf("want the records, got truncated=%v, %v", truncated, err)
	}
	want := []FailureRecord{
		{},
		{FailureStart: at(20, 7, 12, 0), FailedBuild: "12.345"},
		{},
		{FixedBuild: "12.346"},
	}
	if !slices.Equal(got, want) {
		t.Errorf("want %+v,\n got %+v", want, got)
	}
	wantQuery(t, f, url.Values{"per_page": {"100"}})
}

// twoPagesOfComments is a fake whose comments of issue 42 run over two pages.
func twoPagesOfComments(t *testing.T) *fakeGitHub {
	t.Helper()
	f := newFake(t)
	f.on(commentsPath, reply{header: next(commentsPath, "2"), body: "[" + commentItem(1, `"first"`) + "]"})
	f.onPage(commentsPath, "2", reply{body: "[" + commentItem(2, `"failure-start: 2026-09-20T07:12:00Z"`) + "]"})
	return f
}

// TestCommentRecordsFollowsTheLinkNext: every page is read, oldest first.
func TestCommentRecordsFollowsTheLinkNext(t *testing.T) {
	got, truncated, err := commentRecords(twoPagesOfComments(t).client(t, DefaultMaxPages))
	if err != nil || truncated || len(got) != 2 || got[1].FailureStart != at(20, 7, 12, 0) {
		t.Errorf("want two records from two pages, got %+v, truncated=%v, %v", got, truncated, err)
	}
}

// TestCommentRecordsSaysItStoppedAtThePageLimit.
func TestCommentRecordsSaysItStoppedAtThePageLimit(t *testing.T) {
	_, truncated, err := commentRecords(twoPagesOfComments(t).client(t, 1))
	if err != nil || !truncated {
		t.Errorf("want truncated at one page, got truncated=%v, %v", truncated, err)
	}
}

// TestCommentRecordsRefusesWhatItCannotRead: a refused read or an answer that
// is no list is an error naming the repository and the path, never an empty
// answer.
func TestCommentRecordsRefusesWhatItCannotRead(t *testing.T) {
	f := newFake(t)
	f.on(commentsPath, reply{body: `{"message": "Moved"}`})
	_, _, err := commentRecords(f.client(t, DefaultMaxPages))
	wantError(t, err, ErrAnswer, "acme/app: ", commentsPath)
	f = newFake(t)
	_, _, err = commentRecords(f.client(t, DefaultMaxPages))
	wantError(t, err, ErrAccess, "acme/app: ", commentsPath)
}
