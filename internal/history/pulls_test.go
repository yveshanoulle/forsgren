package history

import (
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"
)

const (
	pullsHead = "# forsgren pulls v1\nrepository,number,head_branch,created_at,merged_at,merge_commit,updated_at," +
		"first_commit_at,first_commit_cut,created_stands_in\n"
	mergeSHA   = "abcdef0123456789abcdef0123456789abcdef01"
	pullsLine1 = "acme/app,45,feature/login,2026-09-01T08:00:00Z,2026-09-02T10:00:00Z," + mergeSHA +
		",2026-09-03T12:00:00Z,2026-08-31T07:00:00Z,false,false\n"
)

var pullCreated = time.Date(2026, 9, 1, 8, 0, 0, 0, time.UTC)

// pull is merged pull request number of acme/app, merged hours after
// 2026-09-02T00:00:00Z, its first commit time complete, a day before it was
// created.
func pull(number int64, hours int) PullRequest {
	return PullRequest{
		Repository: "acme/app", Number: number, HeadBranch: "feature/login", CreatedAt: pullCreated,
		MergedAt:    time.Date(2026, 9, 2, hours, 0, 0, 0, time.UTC),
		MergeCommit: mergeSHA, UpdatedAt: time.Date(2026, 9, 3, 12, 0, 0, 0, time.UTC),
		FirstCommitAt: time.Date(2026, 8, 31, 7, 0, 0, 0, time.UTC),
	}
}

// cutPull is pull with its first commit time cut (forsgren#299): still a time,
// a lower bound of the lead time.
func cutPull(number int64, hours int) PullRequest {
	p := pull(number, hours)
	p.FirstCommitCut = true
	return p
}

// standInPull is pull whose commit list gave no usable date (forsgren#300):
// no first commit time, the created time stands in.
func standInPull(number int64, hours int) PullRequest {
	p := pull(number, hours)
	p.FirstCommitAt, p.CreatedStandsIn = time.Time{}, true
	return p
}

// wantFile fails unless the file at path holds want.
func wantFile(t *testing.T, path, want string) {
	t.Helper()
	raw, err := os.ReadFile(filepath.Clean(path))
	if err != nil || string(raw) != want {
		t.Errorf("want the file\n%q\ngot\n%q, %v", want, raw, err)
	}
}

// wantPulls fails unless the pull requests at path are want, in file order.
func wantPulls(t *testing.T, path string, want []PullRequest) {
	t.Helper()
	got, err := LoadPullRequests(path)
	if err != nil || !slices.Equal(got, want) {
		t.Errorf("want %v, got %v, %v", want, got, err)
	}
}

// TestAPullRequestIsWrittenOnceByRepositoryAndNumber (forsgren#255, step 3):
// data/pulls.csv is created, directory included, with its version and column
// lines; a pull request already held (repository ignoring case, and number)
// is not written again, whatever else it says, so the first line stays.
func TestAPullRequestIsWrittenOnceByRepositoryAndNumber(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data", "pulls.csv")
	if n, err := AppendPullRequests(path, []PullRequest{pull(45, 10)}); err != nil || n != 1 {
		t.Fatalf("want 1 line written, got %d, %v", n, err)
	}
	again := cutPull(45, 11)
	again.Repository = "ACME/app"
	if n, err := AppendPullRequests(path, []PullRequest{again}); err != nil || n != 0 {
		t.Errorf("want the held pull request not written again, got %d, %v", n, err)
	}
	wantFile(t, path, pullsHead+pullsLine1)
	wantPulls(t, path, []PullRequest{pull(45, 10)})
}

// TestThePullsFileKeepsHowTheFirstCommitTimeWasFound (forsgren#299, #300): a
// cut first commit time keeps its time and says it is cut; a pull request
// whose commit list gave no usable date has no first commit time and says the
// created time stands in.
func TestThePullsFileKeepsHowTheFirstCommitTimeWasFound(t *testing.T) {
	path := filepath.Join(t.TempDir(), "pulls.csv")
	in := []PullRequest{pull(45, 10), cutPull(46, 11), standInPull(47, 12)}
	if n, err := AppendPullRequests(path, in); err != nil || n != 3 {
		t.Fatalf("want 3 lines written, got %d, %v", n, err)
	}
	wantFile(t, path, pullsHead+pullsLine1+
		"acme/app,46,feature/login,2026-09-01T08:00:00Z,2026-09-02T11:00:00Z,"+mergeSHA+
		",2026-09-03T12:00:00Z,2026-08-31T07:00:00Z,true,false\n"+
		"acme/app,47,feature/login,2026-09-01T08:00:00Z,2026-09-02T12:00:00Z,"+mergeSHA+
		",2026-09-03T12:00:00Z,,false,true\n")
	wantPulls(t, path, in)
}

// TestNewPullRequestsAreWrittenInMergeOrder: given out of order, new lines
// go in merged time order, then repository, then number.
func TestNewPullRequestsAreWrittenInMergeOrder(t *testing.T) {
	path := filepath.Join(t.TempDir(), "pulls.csv")
	in := []PullRequest{pull(48, 12), pull(47, 10), pull(46, 12)}
	if n, err := AppendPullRequests(path, in); err != nil || n != 3 {
		t.Fatalf("want 3 lines written, got %d, %v", n, err)
	}
	wantPulls(t, path, []PullRequest{in[1], in[2], in[0]})
}

// refusedFor says whether err is ErrInvalidRecord and says each of words.
func refusedFor(err error, words ...string) bool {
	if !errors.Is(err, ErrInvalidRecord) {
		return false
	}
	for _, w := range words {
		if !strings.Contains(err.Error(), w) {
			return false
		}
	}
	return true
}

// malformedOn says whether err is a MalformedError on line whose reason
// says reason.
func malformedOn(err error, line int, reason string) bool {
	var m *MalformedError
	if !errors.As(err, &m) {
		return false
	}
	return m.Line == line && strings.Contains(m.Reason, reason)
}

// spoiled is pull request 45 changed by spoil, and the words of the reason
// it is refused for.
type spoiled struct {
	why   string
	spoil func(*PullRequest)
}

// TestAPullRequestThatCannotBeStoredIsRefused: only merged pull requests
// (forsgren#256) with whole-second times are stored, a first commit time
// exactly when the created time does not stand in, never cut and standing in
// at once; the refusal names the record and why, and nothing is written.
func TestAPullRequestThatCannotBeStoredIsRefused(t *testing.T) {
	for _, c := range []spoiled{
		{"merged_at is empty", func(p *PullRequest) { p.MergedAt, p.MergeCommit = time.Time{}, "" }},
		{`merge_commit ""`, func(p *PullRequest) { p.MergeCommit = "" }},
		{`merge_commit "ABC"`, func(p *PullRequest) { p.MergeCommit = "ABC" }},
		{`repository "app"`, func(p *PullRequest) { p.Repository = "app" }},
		{"line break", func(p *PullRequest) { p.Repository = "acme/a\npp" }},
		{"number is not positive", func(p *PullRequest) { p.Number = 0 }},
		{"head_branch is empty", func(p *PullRequest) { p.HeadBranch = "" }},
		{"line break", func(p *PullRequest) { p.HeadBranch = "a\nb" }},
		{"created_at", func(p *PullRequest) { p.CreatedAt = p.CreatedAt.Add(time.Millisecond) }},
		{"created_at", func(p *PullRequest) { p.CreatedAt = time.Time{} }},
		{"updated_at", func(p *PullRequest) { p.UpdatedAt = time.Time{} }},
		{"first_commit_at has", func(p *PullRequest) { p.FirstCommitAt = p.FirstCommitAt.Add(time.Millisecond) }},
		{"empty exactly when", func(p *PullRequest) { p.FirstCommitAt = time.Time{} }},
		{"empty exactly when", func(p *PullRequest) { p.CreatedStandsIn = true }},
		{"cut first commit time keeps its time", func(p *PullRequest) {
			p.FirstCommitAt, p.CreatedStandsIn, p.FirstCommitCut = time.Time{}, true, true
		}},
	} {
		p := pull(45, 10)
		c.spoil(&p)
		path := filepath.Join(t.TempDir(), "pulls.csv")
		_, err := AppendPullRequests(path, []PullRequest{pull(44, 9), p})
		if !refusedFor(err, "record 2: ", c.why) {
			t.Errorf("want ErrInvalidRecord for record 2: %s, got %v", c.why, err)
		}
		if _, err := os.Stat(path); !notExist(err) {
			t.Errorf("%s: want nothing written, got %v", c.why, err)
		}
	}
}

// pullsLineWith is the line of pullsLine1, without its newline, with the
// field at index i replaced by value.
func pullsLineWith(i int, value string) string {
	fields := strings.Split(strings.TrimSuffix(pullsLine1, "\n"), ",")
	fields[i] = value
	return strings.Join(fields, ",")
}

// TestAMalformedPullsLineIsRefused: each bad line is named by its number,
// and the reason names the column or the rule.
func TestAMalformedPullsLineIsRefused(t *testing.T) {
	for name, line := range map[string]string{
		"number":             pullsLineWith(1, "x"),
		"created_at":         pullsLineWith(3, "yesterday"),
		"merged_at":          pullsLineWith(4, ""),
		"updated_at":         pullsLineWith(6, ""),
		"first_commit_at":    pullsLineWith(7, "soon"),
		"first_commit_cut":   pullsLineWith(8, "yes"),
		"created_stands_in":  pullsLineWith(9, "no"),
		"empty exactly when": pullsLineWith(9, "true"),
		"10 comma-separated": strings.TrimSuffix(pullsLineWith(9, ""), ","),
	} {
		t.Run(name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "pulls.csv")
			if err := os.WriteFile(path, []byte(pullsHead+pullsLine1+line+"\n"), 0o600); err != nil {
				t.Fatal(err)
			}
			if _, err := LoadPullRequests(path); !malformedOn(err, 4, name) {
				t.Errorf("want a MalformedError on line 4 naming %s, got %v", name, err)
			}
		})
	}
}

// TestAnotherPullsVersionIsRefused: a pulls file of a version this forsgren
// does not know is ErrUnknownVersion, and an append leaves it as it was.
func TestAnotherPullsVersionIsRefused(t *testing.T) {
	path := filepath.Join(t.TempDir(), "pulls.csv")
	content := "# forsgren pulls v2\nrepository,number\n"
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := AppendPullRequests(path, []PullRequest{pull(45, 10)}); !errors.Is(err, ErrUnknownVersion) {
		t.Errorf("want ErrUnknownVersion, got %v", err)
	}
	wantFile(t, path, content)
}
