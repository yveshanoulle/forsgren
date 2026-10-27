package collect

// The fill of the opener of the stored merged pull requests (forsgren#500).
// A pull request stored before the bot column (forsgren#345) has its bot
// status unknown, and an unknown opener counts in neither PR Lead Time nor
// Bot PR Lead Time (forsgren#403). Once per repository, after its pull
// requests are read, the fills of forsgren#470 are done and the push read has
// run (so it never holds fresh data back), each stored
// pull request of the repository whose bot status is unknown gets one read of
// the pull request (Client.PullRequestUserType, with the request budget
// reserved first), and the account type of its opener sets the status as
// botOf does for a pull request read from the list: a bot, a person, or still
// unknown for any other type. Every stored pull request counts, not only
// those of the DORA window: an installation may widen dora_days later. A
// pull request stored by this run's read is not asked: that read judged it.
//
// The statuses are written through the history layer (history.BackfillPullBots:
// the whole file once, nothing when nothing changed).
//
// data/pulls_bot_filled.csv (a mark file, one time per repository) says which
// repositories were filled; it is noted only when the fill finished, at once,
// since what it filled is already stored. A pull request GitHub has no answer
// for (404 or 410) is named on stderr and stays unknown, and does not keep the
// repository from being noted. A fill ends as the fills of forsgren#470 do:
//
//   - a missing pull-requests: read (a 403) stores what was filled, notes no
//     fill, writes the denied mark and never fails the run;
//   - a budget stop stores what was filled, notes no fill, adds the
//     repository to the report's pulls-bot-fill-cut lines and never fails the
//     run, so the next run continues;
//   - any other error stores what was filled, notes no fill and fails the
//     repository.

import (
	"context"
	"errors"
	"path/filepath"
	"strings"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// PullsBotFilledFile is the name, next to the history, of the file that notes
// which repositories had the bot status of their stored pull requests filled
// (forsgren#500).
const PullsBotFilledFile = "pulls_bot_filled.csv"

// pullsBotFilledFile is the path of the pulls bot filled file next to o's
// history.
func (o Options) pullsBotFilledFile() string {
	return filepath.Join(filepath.Dir(o.History), PullsBotFilledFile)
}

// fillPullBots fills the bot status of repo's stored pull requests once, when
// the pull request read ended whole; see the top of this file for what ends
// it.
func (o Options) fillPullBots(ctx context.Context, h held, repo string, whole bool) error {
	if !whole || filledBefore(h.botsFilled, repo) {
		return nil
	}
	known, err := o.readPullBots(ctx, repo, h.pullsWithoutBot(repo))
	if _, serr := history.BackfillPullBots(o.pullsFile(), known); serr != nil {
		return serr
	}
	_, err = o.endPullsFill(h, repo, err, fillEnd{h.botsFilled, "pull request openers", o.reportPullBotFillCut})
	return err
}

// pullsWithoutBot is the pull requests stored when the run began, of repo
// (ignoring case), whose bot status is unknown, in the order of pulls.csv.
func (h held) pullsWithoutBot(repo string) []history.PullRequest {
	var todo []history.PullRequest
	for _, p := range h.storedPulls {
		if strings.EqualFold(p.Repository, repo) && p.Bot == history.BotUnknown {
			todo = append(todo, p)
		}
	}
	return todo
}

// readPullBots is the pull requests todo of repo with the bot status of their
// openers, up to the first error that ends the fill; one a status is not
// known for stays out.
func (o Options) readPullBots(ctx context.Context, repo string, todo []history.PullRequest,
) ([]history.PullRequest, error) {
	var known []history.PullRequest
	for _, p := range todo {
		if err := o.Client.Reserve(repo, 1); err != nil {
			return known, err
		}
		userType, err := o.Client.PullRequestUserType(ctx, repo, p.Number)
		switch {
		case errors.Is(err, github.ErrPullRequestGone):
			o.warn("collect: %v; its opener stays unknown\n", err)
		case err != nil:
			return known, err
		default:
			p.Bot = botOf(userType)
			known = append(known, p)
		}
	}
	return known, nil
}
