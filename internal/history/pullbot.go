package history

import "fmt"

// BotStatus is what is known of who opened a pull request (forsgren#345,
// step 1): a person, a bot account, or not known. It is never a login: only
// GitHub's account type of the author is read, and only this is stored. The
// zero value is BotUnknown, so a pull request nobody judged is never taken
// as a person's.
type BotStatus int

const (
	// BotUnknown is a pull request whose author's account type is not known:
	// one stored by the pulls format v1, before the bot column, one GitHub
	// named no author or no type for, or one of any type but "User" and
	// "Bot" (Yves's answer on #349).
	BotUnknown BotStatus = iota
	// ByHuman is a pull request opened by an account GitHub types as a
	// person (user.type "User").
	ByHuman
	// ByBot is a pull request opened by an account GitHub types as a bot
	// (user.type "Bot": dependabot[bot] among them).
	ByBot
)

// botColumn is the bot column's text of each status: "true", "false", and
// empty for unknown, as the commits leave an author that is not known empty.
var botColumn = map[BotStatus]string{BotUnknown: "", ByHuman: "false", ByBot: "true"}

// String is s as the bot column writes it.
func (s BotStatus) String() string { return botColumn[s] }

// isBotStatus says whether s is one of the three statuses.
func isBotStatus(s BotStatus) bool {
	_, ok := botColumn[s]
	return ok
}

// parseBot reads the bot column: "true", "false", or empty for unknown.
func parseBot(s string) (BotStatus, error) {
	for status, text := range botColumn {
		if s == text {
			return status, nil
		}
	}
	return BotUnknown, fmt.Errorf("bot %q is not true, false or empty", s)
}
