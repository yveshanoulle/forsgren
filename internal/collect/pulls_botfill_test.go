package collect

import (
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/github"
)

// The fill of the opener (bot or person) of the stored merged pull requests
// whose bot status is unknown (forsgren#500): stored before the bot column,
// they count in neither PR Lead Time nor Bot PR Lead Time. Once per
// repository each gets one read of the pull request, and its user.type sets
// the status.

const pullsBotFilledHeader = "# forsgren pulls bot filled v1\nrepository,filled_at\n"

// botFilledNow is the pulls bot filled file after a run that noted acme/app
// as filled now.
const botFilledNow = pullsBotFilledHeader + "acme/app,2026-10-01T00:00:00Z\n"

// onePath is the path of the read of the pull request p alone.
func (p pull) onePath() string { return pullsPath + "/" + strconv.Itoa(p.n) }

// singleReads are the requests so far for one pull request alone, not its
// commits.
func singleReads(g *gitHub) []string {
	var out []string
	for _, r := range g.seen(pullsPath + "/") {
		if !strings.Contains(r, "/commits") {
			out = append(out, r)
		}
	}
	return out
}

// readsOf are the requests so far for pull request p alone, not its commits.
func readsOf(g *gitHub, p pull) []string {
	var out []string
	for _, r := range g.seen(p.onePath()) {
		if !strings.Contains(r, "/commits") {
			out = append(out, r)
		}
	}
	return out
}

// storedUnknown is a fake whose pull request list is empty and a pulls.csv of
// pulls 12 and 14, both with the bot column empty; the commits fill is done
// already. The fake answers pull 12 as opened by a bot and pull 14 by a person.
func storedUnknown(t *testing.T) (*gitHub, string) {
	t.Helper()
	g := pullsOnly(t)
	g.bodies[pull12.onePath()] = pull12.jsonBy(botUser)
	g.bodies[pull14.onePath()] = pull14.json()
	path := historyPath(t)
	data := dataOf(path)
	data.write(t, "pulls.csv", pullsHeader+pull12.lineBy("2026-09-20T10:00:00Z", false, "")+
		pull14.lineBy("2026-09-23T10:00:00Z", false, ""))
	data.write(t, PullCommitsFilledFile, filledNow)
	return g, path
}

// TestTheBotFillSetsTheStatusFromTheOpenersAccountType: a bot's pull request
// becomes true, a person's false, any other type stays empty; a stored pull
// request that already has a status is not asked; the repository is noted.
func TestTheBotFillSetsTheStatusFromTheOpenersAccountType(t *testing.T) {
	g, path := storedUnknown(t)
	g.bodies[newPull.onePath()] = newPull.jsonBy(`{"login": "someone", "type": "Organization"}`)
	data := dataOf(path)
	data.write(t, "pulls.csv", pullsHeader+newPull.lineBy("2025-10-01T10:00:00Z", false, "")+
		pull12.lineBy("2026-09-20T10:00:00Z", false, "")+pull14.lineBy("2026-09-23T10:00:00Z", false, "")+
		pull15.line("2026-09-24T10:00:00Z", false))
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	data.want(t, "pulls.csv", pullsHeader+newPull.lineBy("2025-10-01T10:00:00Z", false, "")+
		pull12.lineBy("2026-09-20T10:00:00Z", false, "true")+pull14.lineBy("2026-09-23T10:00:00Z", false, "false")+
		pull15.line("2026-09-24T10:00:00Z", false))
	data.want(t, PullsBotFilledFile, botFilledNow)
	if got := readsOf(g, pull15); len(got) != 0 {
		t.Errorf("want no read of pull request 15, which has a status, got %v", got)
	}
	wantNoLogin(t, string(data)+"/pulls.csv")
}

// TestTheBotFillAsksEachPullRequestOnceAndNeverAgain: the read of each unknown
// pull request is one GET with its number, and a second run, after the mark,
// asks for none, even of one that stayed unknown.
func TestTheBotFillAsksEachPullRequestOnceAndNeverAgain(t *testing.T) {
	g, path := storedUnknown(t)
	g.bodies[pull14.onePath()] = pull14.jsonBy(`{"login": "someone", "type": "Organization"}`)
	for range 2 {
		if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
			t.Fatal(r.err)
		}
	}
	for _, p := range []pull{pull12, pull14} {
		if got := readsOf(g, p); len(got) != 1 {
			t.Errorf("want pull request %d asked once over two runs, got %v", p.n, got)
		}
	}
}

// TestTheBotFillLeavesAPullRequestStoredByThisRunAlone: a pull request the
// read of this run stored with no author named is unknown, but was judged by
// that read; the fill does not ask for it.
func TestTheBotFillLeavesAPullRequestStoredByThisRunAlone(t *testing.T) {
	g := pullsOnly(t, pull14)
	g.bodies[pullsPath] = list(pull14.jsonBy("null"))
	g.bodies[pull14.onePath()] = pull14.jsonBy(botUser)
	path := historyPath(t)
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	if got := readsOf(g, pull14); len(got) != 0 {
		t.Errorf("want no read of pull request 14, got %v", got)
	}
	dataOf(path).want(t, PullsBotFilledFile, botFilledNow)
}

// TestTheBotFillStopsWithinTheRequestBudgetAndTheNextRunContinues: at the
// margin the openers read are stored and the repository is not noted; stderr
// says so, the run does not fail, the report has its own line kind, and the
// next run reads the rest.
func TestTheBotFillStopsWithinTheRequestBudgetAndTheNextRunContinues(t *testing.T) {
	g, path := storedUnknown(t)
	g.left[pull12.onePath()] = 250
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if r.err != nil || !strings.Contains(r.stderr, "acme/app: the pull request openers were cut short") {
		t.Errorf("want stderr to say the fill was cut short and no error, got %q, %v", r.stderr, r.err)
	}
	data := dataOf(path)
	data.want(t, "pulls.csv", pullsHeader+pull12.lineBy("2026-09-20T10:00:00Z", false, "true")+
		pull14.lineBy("2026-09-23T10:00:00Z", false, ""))
	data.want(t, PullsBotFilledFile, "")
	g.wantReportOf(t, Report{PullBotFillCut: []string{"acme/app"}, Reset: g.resetAt.UTC()})
	delete(g.left, pull12.onePath())
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	data.want(t, "pulls.csv", pullsHeader+pull12.lineBy("2026-09-20T10:00:00Z", false, "true")+
		pull14.lineBy("2026-09-23T10:00:00Z", false, "false"))
	data.want(t, PullsBotFilledFile, botFilledNow)
	if got := readsOf(g, pull12); len(got) != 1 {
		t.Errorf("want pull request 12 asked once over two runs, got %v", got)
	}
}

// TestADeniedBotFillWritesTheDeniedMarkAndNeverFails: a 403 stores what was
// read, notes no fill, names the missing permission, writes the repository in
// pulls_denied.csv and does not fail the run.
func TestADeniedBotFillWritesTheDeniedMarkAndNeverFails(t *testing.T) {
	g, path := storedUnknown(t)
	g.deny(pull14.onePath())
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if r.err != nil || !strings.Contains(r.stderr, "Pull requests: Read") {
		t.Errorf("want stderr to name Pull requests: Read and no error, got %q, %v", r.stderr, r.err)
	}
	data := dataOf(path)
	data.want(t, "pulls.csv", pullsHeader+pull12.lineBy("2026-09-20T10:00:00Z", false, "true")+
		pull14.lineBy("2026-09-23T10:00:00Z", false, ""))
	data.want(t, PullsBotFilledFile, "")
	data.want(t, PullsDeniedFile,
		"# forsgren pulls denied v2\nrepository,denied_at,token\nacme/app,2026-10-01T00:00:00Z,FORSGREN_TOKEN\n")
	g.wantReportOf(t, Report{})
}

// TestABotFillOfAMissingPullRequestIsNamedAndTheFillIsNoted: a 404 names the
// pull request on stderr, leaves it unknown and does not keep the repository
// from being noted.
func TestABotFillOfAMissingPullRequestIsNamedAndTheFillIsNoted(t *testing.T) {
	g, path := storedUnknown(t)
	delete(g.bodies, pull12.onePath())
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if r.err != nil || !strings.Contains(r.stderr, "acme/app: pull request 12") {
		t.Errorf("want stderr to name pull request 12 and no error, got %q, %v", r.stderr, r.err)
	}
	data := dataOf(path)
	data.want(t, "pulls.csv", pullsHeader+pull12.lineBy("2026-09-20T10:00:00Z", false, "")+
		pull14.lineBy("2026-09-23T10:00:00Z", false, "false"))
	data.want(t, PullsBotFilledFile, botFilledNow)
}

// TestABotFillGitHubAnswersWronglyFailsTheRepositoryAfterStoringWhatItRead:
// any other error fails the repository, the statuses read before it are
// stored, and the repository is not noted.
func TestABotFillGitHubAnswersWronglyFailsTheRepositoryAfterStoringWhatItRead(t *testing.T) {
	g, path := storedUnknown(t)
	g.status[pull14.onePath()] = http.StatusInternalServerError
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) {
		t.Errorf("want ErrFailed, got %v (stderr %q)", r.err, r.stderr)
	}
	data := dataOf(path)
	data.want(t, "pulls.csv", pullsHeader+pull12.lineBy("2026-09-20T10:00:00Z", false, "true")+
		pull14.lineBy("2026-09-23T10:00:00Z", false, ""))
	data.want(t, PullsBotFilledFile, "")
}

// TestACutPullRequestReadIsNotFollowedByTheBotFill: the budget stops the read
// of the list; no pull request is read alone, no mark is noted and the report
// has no fill line.
func TestACutPullRequestReadIsNotFollowedByTheBotFill(t *testing.T) {
	g, path := storedUnknown(t)
	g.bodies[pullsPath] = list(pull15.json())
	g.bodies[pull15.commitsPath()] = list(commitAt("2026-09-24T10:00:00Z"))
	g.left[pullsPath] = 1
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	if got := singleReads(g); len(got) != 0 {
		t.Errorf("want no pull request read alone, got %v", got)
	}
	g.wantReportOf(t, Report{PullsCut: []string{"acme/app"}, PushesCut: []string{"acme/app"}, Reset: g.resetAt.UTC()})
	dataOf(path).want(t, PullsBotFilledFile, "")
}

// TestARefusedPullRequestReadIsNotFollowedByTheBotFill: a 403 on the list is
// warned once; no pull request is read alone and no mark is noted.
func TestARefusedPullRequestReadIsNotFollowedByTheBotFill(t *testing.T) {
	g, path := storedUnknown(t)
	g.deny(pullsPath)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if got := strings.Count(r.stderr, "its pull requests are not read"); r.err != nil || got != 1 {
		t.Fatalf("want one refused warning and no error, got %d in %q, %v", got, r.stderr, r.err)
	}
	if got := singleReads(g); len(got) != 0 {
		t.Errorf("want no pull request read alone, got %v", got)
	}
	dataOf(path).want(t, PullsBotFilledFile, "")
}

// TestABotFillThatCannotBeWrittenFailsTheRepositoryAndNotesNoFill: a
// pulls.csv that cannot be replaced fails the repository, and the repository
// is not noted, so the next run fills again.
func TestABotFillThatCannotBeWrittenFailsTheRepositoryAndNotesNoFill(t *testing.T) {
	g, path := storedUnknown(t)
	if err := os.Mkdir(filepath.Join(filepath.Dir(path), PullsFile+".tmp"), 0o700); err != nil {
		t.Fatal(err)
	}
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) || !strings.Contains(r.stderr, PullsFile) {
		t.Errorf("want ErrFailed and stderr naming %s, got %v, %q", PullsFile, r.err, r.stderr)
	}
	dataOf(path).want(t, PullsBotFilledFile, "")
}

// TestACutBotFillNeverHoldsBackThePushes: the fill runs after the push read,
// so a budget stop in it stores the pushes of the same run and reports its
// own line kind alone.
func TestACutBotFillNeverHoldsBackThePushes(t *testing.T) {
	g, path := storedUnknown(t)
	g.bodies[activityPath] = list(activityOf("force_push", pushTime1, shaA, shaB))
	g.left[pull12.onePath()] = 250
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	data := dataOf(path)
	data.want(t, PushesFile, pushesHeader+linePush(pushTime1, shaA, shaB, "force_push", "false", ""))
	data.want(t, PullsBotFilledFile, "")
	g.wantReportOf(t, Report{PullBotFillCut: []string{"acme/app"}, Reset: g.resetAt.UTC()})
}
