package history

import (
	"cmp"
	"fmt"
	"slices"
	"strconv"
	"strings"
	"time"
)

// Push is one push to a repository's main branch (forsgren#397, step 2): a
// line of data/pushes.csv, for time to main and batch size per push. It holds
// no login: whether a bot pushed is, never who.
//
// The format is "# forsgren pushes v1", the column line
// "repository,pushed_at,before,after,kind,bot,commits", the time in UTC to the
// second, the SHAs 40 or 64 lower-case hex digits, the kind one of "push",
// "pr_merge" and "force_push", the bot column "true", "false" or empty for
// unknown, and the commits column the number of commits the push added to the
// first-parent chain, empty when it is not known.
type Push struct {
	Repository string // owner/name
	PushedAt   time.Time
	// Before and After are the branch's tip before and after the push.
	Before, After string
	// Kind is PushKindPush, PushKindPRMerge or PushKindForcePush.
	Kind string
	// Bot is whether a bot account made the push: BotUnknown when GitHub
	// names no account type.
	Bot BotStatus
	// Commits is how many commits the push added to the first-parent chain
	// from After back to Before; 0 is not known (an empty column), never a
	// guessed number, since a real push adds one commit at least.
	Commits int64
}

// The kinds a Push can be, GitHub's activity_type.
const (
	PushKindPush      = "push"
	PushKindPRMerge   = "pr_merge"
	PushKindForcePush = "force_push"
)

// pushKinds are the kinds a Push can be.
var pushKinds = []string{PushKindPush, PushKindPRMerge, PushKindForcePush}

// pushes is the format of data/pushes.csv, the pushes format v1.
var pushes = format[Push, PushKey]{
	versionLine: "# forsgren pushes v1",
	columnLine:  "repository,pushed_at,before,after,kind,bot,commits",
	decode:      toPush,
	encode:      Push.fields,
	validate:    Push.validate,
	key:         Push.Key,
	compare:     comparePushes,
}

// LoadPushes reads the pushes at path, in file order, with Load's errors.
func LoadPushes(path string) ([]Push, error) { return pushes.load(path) }

// AppendPushes stores the pushes that the file at path does not hold yet, and
// returns how many it stored, by Append's rules. A push is already held when
// a line has the same repository, ignoring case, after SHA and time, whatever
// else it says: the first line stays. The new lines are in time order
// (pushed at, repository, after).
func AppendPushes(path string, records []Push) (int, error) { return pushes.append(path, records) }

// PushKey identifies a push; collect holds the pushes of the file by it.
type PushKey struct {
	repository string
	after      string
	at         time.Time
}

// Key is p's repository (lower-case), after SHA and time.
func (p Push) Key() PushKey { return PushKey{strings.ToLower(p.Repository), p.After, p.PushedAt} }

// comparePushes orders new lines by time, then repository, then after SHA.
func comparePushes(a, b Push) int {
	return cmp.Or(a.PushedAt.Compare(b.PushedAt), cmp.Compare(a.Repository, b.Repository),
		cmp.Compare(a.After, b.After))
}

// fields are the columns of p's line; unknown commits are an empty column.
func (p Push) fields() []string {
	commits := ""
	if p.Commits > 0 {
		commits = strconv.FormatInt(p.Commits, 10)
	}
	return []string{p.Repository, formatTime(p.PushedAt), p.Before, p.After, p.Kind, p.Bot.String(), commits}
}

// toPush reads the seven fields of a line.
func toPush(f []string) (Push, error) {
	p := Push{Repository: f[0], Before: f[2], After: f[3], Kind: f[4]}
	var err error
	if p.PushedAt, err = parseTime("pushed_at", f[1]); err != nil {
		return Push{}, err
	}
	if p.Bot, err = parseBot(f[5]); err != nil {
		return Push{}, err
	}
	if f[6] != "" {
		p.Commits, err = parseNumber("commits", f[6])
	}
	return p, err
}

// validate says why p cannot be stored, or nil.
func (p Push) validate() error {
	return firstFailure(
		check{isRepository(p.Repository), fmt.Sprintf("repository %q is not owner/name", p.Repository)},
		check{!strings.ContainsAny(p.Repository, "\r\n"), "repository has a line break"},
		check{isWholeSecond(p.PushedAt), "pushed_at is empty or has a fraction of a second"},
		check{isSHA(p.Before), fmt.Sprintf("before %q is not 40 or 64 lower-case hex digits", p.Before)},
		check{isSHA(p.After), fmt.Sprintf("after %q is not 40 or 64 lower-case hex digits", p.After)},
		check{slices.Contains(pushKinds, p.Kind), fmt.Sprintf("kind %q is not push, pr_merge or force_push", p.Kind)},
		check{isBotStatus(p.Bot), fmt.Sprintf("bot status %d is not unknown, a person or a bot", p.Bot)},
		check{p.Commits >= 0, "commits is negative"},
	)
}
