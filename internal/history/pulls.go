package history

import (
	"cmp"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// PullRequest is one merged pull request (forsgren#255, step 3): a line of
// data/pulls.csv, for PR Lead Time, merged time minus first commit
// time (forsgren#256). Only merged pull requests are stored; one closed
// without a merge is not. No title and no author is stored: whether a bot
// opened it is, never the login (forsgren#345).
//
// The format is "# forsgren pulls v2", the column line
// "repository,number,created_at,merged_at,merge_commit,updated_at,
// first_commit_at,first_commit_cut,created_stands_in,bot" (one line, broken
// here), every time in UTC to the second, the two flags "true" or "false",
// the bot column "true", "false" or empty for unknown. No head branch is
// stored either (forsgren#305): a branch name can identify people.
type PullRequest struct {
	Repository  string // owner/name
	Number      int64  // the pull request number
	CreatedAt   time.Time
	MergedAt    time.Time
	MergeCommit string // the SHA of the commit the merge made, lower-case hex
	// UpdatedAt is GitHub's updated time when collect read the pull request;
	// the first line stays, so a later update does not move it.
	UpdatedAt time.Time
	// FirstCommitAt is the earliest git author date of the pull request's
	// commits (forsgren#298); zero exactly when CreatedStandsIn.
	FirstCommitAt time.Time
	// FirstCommitCut says the commit list was cut (forsgren#299: 250 commits
	// or more, the page limit or the request budget), so FirstCommitAt may be
	// too late and the lead time is a lower bound. Never with CreatedStandsIn.
	FirstCommitCut bool
	// CreatedStandsIn says the commit list gave no usable date, no commit or
	// one without an author date (forsgren#300), so the created time stands
	// in for the first commit time; never because the list was cut.
	CreatedStandsIn bool
	// Bot is whether a bot account opened the pull request (forsgren#345):
	// BotUnknown for a line of the pulls format v1.
	Bot BotStatus
}

// pulls is the format of data/pulls.csv, the pulls format v2 (the bot
// column, forsgren#345); v1, without it, is still read, every bot status
// unknown, and rewritten as v2 by the first append, unknown kept unknown.
var pulls = format[PullRequest, IssueKey]{
	versionLine: "# forsgren pulls v2",
	columnLine:  pullsV1.columnLine + ",bot",
	decode:      toPullRequest,
	encode:      PullRequest.fields,
	validate:    PullRequest.validate,
	key:         PullRequest.Key,
	compare:     comparePullRequests,
	legacy:      []legacyFormat{pullsV1},
}

// pullsV1 is the pulls format v1, before the bot column: its nine columns
// are the first nine of v2, the bot column empty, unknown, never a person.
var pullsV1 = legacyFormat{
	versionLine: "# forsgren pulls v1",
	columnLine: "repository,number,created_at,merged_at,merge_commit,updated_at," +
		"first_commit_at,first_commit_cut,created_stands_in",
	lift: func(fields []string) []string { return append(fields, BotUnknown.String()) },
}

// LoadPullRequests reads the pull requests at path, in file order, with
// Load's errors.
func LoadPullRequests(path string) ([]PullRequest, error) { return pulls.load(path) }

// AppendPullRequests stores the pull requests that the file at path does not
// hold yet, and returns how many it stored, by Append's rules. A pull request
// is already held when a line has the same repository, ignoring case, and
// number, whatever else it says: the first line stays. The new lines are in
// merge order (merged at, repository, number).
func AppendPullRequests(path string, records []PullRequest) (int, error) {
	return pulls.append(path, records)
}

// Key is p's pull request: GitHub numbers a repository's issues and pull
// requests from one sequence, so the issue key tells pull requests apart too.
func (p PullRequest) Key() IssueKey { return IssueKeyOf(p.Repository, p.Number) }

// comparePullRequests orders new lines by merged time, then repository, then
// number.
func comparePullRequests(a, b PullRequest) int {
	return cmp.Or(a.MergedAt.Compare(b.MergedAt), cmp.Compare(a.Repository, b.Repository),
		cmp.Compare(a.Number, b.Number))
}

// fields are the columns of p's line; a zero first commit time is an empty
// column.
func (p PullRequest) fields() []string {
	return []string{
		p.Repository, strconv.FormatInt(p.Number, 10), formatTime(p.CreatedAt),
		formatTime(p.MergedAt), p.MergeCommit, formatTime(p.UpdatedAt), formatTime(p.FirstCommitAt),
		strconv.FormatBool(p.FirstCommitCut), strconv.FormatBool(p.CreatedStandsIn), p.Bot.String(),
	}
}

// toPullRequest reads the ten fields of a line.
func toPullRequest(f []string) (PullRequest, error) {
	p := PullRequest{Repository: f[0], MergeCommit: f[4]}
	var errs [8]error
	p.Number, errs[0] = parseNumber("number", f[1])
	p.CreatedAt, errs[1] = parseTime("created_at", f[2])
	p.MergedAt, errs[2] = parseTime("merged_at", f[3])
	p.UpdatedAt, errs[3] = parseTime("updated_at", f[5])
	p.FirstCommitAt, errs[4] = parseOptionalTime("first_commit_at", f[6])
	p.FirstCommitCut, errs[5] = parseFlag("first_commit_cut", f[7])
	p.CreatedStandsIn, errs[6] = parseFlag("created_stands_in", f[8])
	p.Bot, errs[7] = parseBot(f[9])
	for _, err := range errs {
		if err != nil {
			return PullRequest{}, err
		}
	}
	return p, nil
}

// parseFlag reads a flag column named column: "true" or "false".
func parseFlag(column, s string) (bool, error) {
	if s != "true" && s != "false" {
		return false, fmt.Errorf("%s %q is not true or false", column, s)
	}
	return s == "true", nil
}

// validate says why p cannot be stored, or nil.
func (p PullRequest) validate() error {
	return firstFailure(
		check{isRepository(p.Repository), fmt.Sprintf("repository %q is not owner/name", p.Repository)},
		check{p.Number > 0, "number is not positive"},
		check{!strings.ContainsAny(p.Repository, "\r\n"), "repository has a line break"},
		check{isWholeSecond(p.CreatedAt), "created_at is empty or has a fraction of a second"},
		check{isWholeSecond(p.MergedAt), "merged_at is empty or has a fraction of a second"},
		check{isSHA(p.MergeCommit), fmt.Sprintf("merge_commit %q is not 40 or 64 lower-case hex digits", p.MergeCommit)},
		check{isWholeSecond(p.UpdatedAt), "updated_at is empty or has a fraction of a second"},
		check{isOptionalWholeSecond(p.FirstCommitAt), "first_commit_at has a fraction of a second"},
		check{p.FirstCommitAt.IsZero() == p.CreatedStandsIn,
			"first_commit_at is empty exactly when the created time stands in"},
		check{!p.FirstCommitCut || !p.CreatedStandsIn, "a cut first commit time keeps its time, no stand-in"},
		check{isBotStatus(p.Bot), fmt.Sprintf("bot status %d is not unknown, a person or a bot", p.Bot)},
	)
}
