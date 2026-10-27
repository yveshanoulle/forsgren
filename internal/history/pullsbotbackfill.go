package history

import "slices"

// BackfillPullBots sets the bot status of the stored pull requests in the
// pulls file at path from known, the same pull requests with the status read
// now (forsgren#500): a stored pull request is changed only when its status
// is unknown and known has it (repository ignoring case, number) with a
// status; every other column, every other line and the order stay as they
// are, the first line staying. It returns how many pull requests it changed.
// A missing file is nothing to fill. Nothing is written when no pull request
// changed, unless the file is of an older version, which is then written once
// in the current one; a write is the whole file through replaceWhole, so an
// interrupted run leaves the old file. A known line that cannot be stored is
// refused before anything is written (ErrInvalidRecord).
func BackfillPullBots(path string, known []PullRequest) (int, error) {
	return backfillFile(pulls, path, known, withKnownBots)
}

// withKnownBots is held with the bot status of each unknown pull request
// taken from known, and how many that changed; held is not changed.
func withKnownBots(held, known []PullRequest) ([]PullRequest, int) {
	byKey := make(map[IssueKey]BotStatus, len(known))
	for _, k := range known {
		byKey[k.Key()] = k.Bot
	}
	out, changed := slices.Clone(held), 0
	for i, p := range out {
		if bot := byKey[p.Key()]; p.Bot == BotUnknown && bot != BotUnknown {
			out[i].Bot, changed = bot, changed+1
		}
	}
	return out, changed
}
