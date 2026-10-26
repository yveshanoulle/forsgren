package metrics

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// The Mainline Lead Time measure (forsgren#463, step 7).

// mainLeadOf is Acme Shop's Mainline Lead Time of data.
func mainLeadOf(data Data) MainlineLeadTime { return MainlineLeadTimesOf(projects, data, now)[0] }

// branched is the commit sha of push that is not on the first-parent chain.
func branched(push history.Push, sha string, lead time.Duration) history.PushCommit {
	c := brought(push, sha, "acme-dev", lead)
	c.FirstParent = false
	return c
}

// mergeOf is the merge commit sha of push, two parents.
func mergeOf(push history.Push, sha string) history.PushCommit {
	c := brought(push, sha, "acme-dev", 0)
	c.Parents = 2
	return c
}

// pullCommit is the commit sha of pull request number of acme/app, authored
// at.
func pullCommit(number int64, sha string, at time.Time) history.PullCommit {
	return history.PullCommit{Repository: "acme/app", Number: number, SHA: sha, Author: "acme-dev", AuthoredAt: at}
}

// pullMerging is pull request number of acme/app, merged an hour ago as sha.
func pullMerging(number int64, sha string) history.PullRequest {
	p := mergedPull("acme/app", number, time.Hour, time.Hour)
	p.MergeCommit = sha
	return p
}

// wantLead fails the test unless got counts commits with the mean lead time.
func wantLead(t *testing.T, got MainlineLeadTime, commits int, mean time.Duration) {
	t.Helper()
	if got.Commits != commits || got.Lead.Count != commits || got.Lead.Mean != mean {
		t.Errorf("want %d commits of mean %v, got %d (%d) of %v", commits, mean, got.Commits, got.Lead.Count,
			got.Lead.Mean)
	}
}

// TestMainlineLeadTimeCountsADirectPushsCommitsFromAuthorToPush: 30 and 10
// minutes between author date and push, mean 20.
func TestMainlineLeadTimeCountsADirectPushsCommitsFromAuthorToPush(t *testing.T) {
	p := pushed("p", history.PushKindPush, 2*time.Hour, 2)
	got := mainLeadOf(Data{Pushes: []history.Push{p}, PushCommits: []history.PushCommit{
		brought(p, "c1", "acme-dev", 30*time.Minute), brought(p, "c2", "acme-dev", 10*time.Minute)}})
	wantLead(t, got, 2, 20*time.Minute)
}

// TestMainlineLeadTimeLeavesAMergeCommitOutAndCountsItsBranchCommit: the
// branch commit, authored 3 hours before the merge push, counts at the
// push; the merge commit (two parents) does not (#464).
func TestMainlineLeadTimeLeavesAMergeCommitOutAndCountsItsBranchCommit(t *testing.T) {
	p := pushed("m", history.PushKindPRMerge, time.Hour, 2)
	got := mainLeadOf(Data{Pushes: []history.Push{p}, PushCommits: []history.PushCommit{
		branched(p, "b", 3*time.Hour), mergeOf(p, "mg")}})
	wantLead(t, got, 1, 3*time.Hour)
	if got.MergesLeftOut != 1 {
		t.Errorf("want 1 merge left out, got %d", got.MergesLeftOut)
	}
}

// TestMainlineLeadTimeKeepsARebasesCommitsAndNeverReadsThePullCommits: three
// first-parent single-parent commits are not a squash; the pull request's
// own commit list (100 hours) is not read.
func TestMainlineLeadTimeKeepsARebasesCommitsAndNeverReadsThePullCommits(t *testing.T) {
	p := pushed("r3", history.PushKindPRMerge, time.Hour, 3)
	got := mainLeadOf(Data{Pushes: []history.Push{p}, PushCommits: []history.PushCommit{
		brought(p, "r1", "acme-dev", 3*time.Hour), brought(p, "r2", "acme-dev", 2*time.Hour),
		brought(p, "r3", "acme-dev", time.Hour)},
		Pulls:       []history.PullRequest{pullMerging(4, "r3")},
		PullCommits: []history.PullCommit{pullCommit(4, "x1", p.PushedAt.Add(-100*time.Hour))}})
	wantLead(t, got, 3, 2*time.Hour)
	if got.Squashed != 0 {
		t.Errorf("want nothing squashed, got %d", got.Squashed)
	}
}

// TestMainlineLeadTimeReplacesASquashCommitWithItsPullRequestsCommits: the
// originals, authored 5 and 3 hours before the squash push, count at that
// push, the squash commit (authored at the push) not (#465).
func TestMainlineLeadTimeReplacesASquashCommitWithItsPullRequestsCommits(t *testing.T) {
	p := pushed("sq", history.PushKindPRMerge, time.Hour, 1)
	got := mainLeadOf(Data{Pushes: []history.Push{p},
		PushCommits: []history.PushCommit{brought(p, "sq", "web-flow", 0)},
		Pulls:       []history.PullRequest{pullMerging(7, "sq")},
		PullCommits: []history.PullCommit{pullCommit(7, "o1", p.PushedAt.Add(-5*time.Hour)),
			pullCommit(7, "o2", p.PushedAt.Add(-3*time.Hour))}})
	wantLead(t, got, 2, 4*time.Hour)
	if got.Squashed != 2 {
		t.Errorf("want 2 squashed originals, got %d", got.Squashed)
	}
}

// TestMainlineLeadTimeCountsASquashCommitWithoutPullCommitsAsItself: data
// from before the change has none (#465).
func TestMainlineLeadTimeCountsASquashCommitWithoutPullCommitsAsItself(t *testing.T) {
	p := pushed("sq", history.PushKindPRMerge, time.Hour, 1)
	got := mainLeadOf(Data{Pushes: []history.Push{p},
		PushCommits: []history.PushCommit{brought(p, "sq", "web-flow", 0)},
		Pulls:       []history.PullRequest{pullMerging(7, "sq")}})
	wantLead(t, got, 1, 0)
	if got.Squashed != 0 {
		t.Errorf("want nothing squashed, got %d", got.Squashed)
	}
}

// TestMainlineLeadTimeGivesAOneCommitPullRequestTheSameFigureEitherWay: its
// merge commit is its only commit, 2 hours authored before the push, with or
// without the pull commits.
func TestMainlineLeadTimeGivesAOneCommitPullRequestTheSameFigureEitherWay(t *testing.T) {
	p := pushed("one", history.PushKindPRMerge, time.Hour, 1)
	data := Data{Pushes: []history.Push{p},
		PushCommits: []history.PushCommit{brought(p, "one", "acme-dev", 2*time.Hour)},
		Pulls:       []history.PullRequest{pullMerging(8, "one")}}
	wantLead(t, mainLeadOf(data), 1, 2*time.Hour)
	data.PullCommits = []history.PullCommit{pullCommit(8, "orig", p.PushedAt.Add(-2*time.Hour))}
	wantLead(t, mainLeadOf(data), 1, 2*time.Hour)
}

// TestMainlineLeadTimeCountsACommitAtItsEarliestPush: the same commit came
// by a push 2 hours ago and one an hour ago, listed in either order;
// authored 30 minutes before the earlier (#466).
func TestMainlineLeadTimeCountsACommitAtItsEarliestPush(t *testing.T) {
	early := pushed("e", history.PushKindPush, 2*time.Hour, 1)
	late := pushed("l", history.PushKindPush, time.Hour, 1)
	first := brought(early, "c", "acme-dev", 30*time.Minute)
	again := brought(late, "c", "acme-dev", 0)
	again.AuthoredAt = first.AuthoredAt
	wantLead(t, mainLeadOf(Data{Pushes: []history.Push{late, early},
		PushCommits: []history.PushCommit{again, first}}), 1, 30*time.Minute)
	wantLead(t, mainLeadOf(Data{Pushes: []history.Push{early, late},
		PushCommits: []history.PushCommit{first, again}}), 1, 30*time.Minute)
}

// TestMainlineLeadTimeCountsAPushedTwiceTipAtItsEarliestPush: one tip pushed
// 2 hours ago and an hour ago, listed in either order.
func TestMainlineLeadTimeCountsAPushedTwiceTipAtItsEarliestPush(t *testing.T) {
	early := pushed("t", history.PushKindPush, 2*time.Hour, 1)
	late := pushed("t", history.PushKindPush, time.Hour, 1)
	line := brought(early, "c", "acme-dev", 30*time.Minute)
	wantLead(t, mainLeadOf(Data{Pushes: []history.Push{early, late}, PushCommits: []history.PushCommit{line}}),
		1, 30*time.Minute)
	wantLead(t, mainLeadOf(Data{Pushes: []history.Push{late, early}, PushCommits: []history.PushCommit{line}}),
		1, 30*time.Minute)
}

// TestMainlineLeadTimeCountsANegativeLeadTimeAsZero: authored 10 minutes
// after the push and 20 minutes before it: mean 10 minutes.
func TestMainlineLeadTimeCountsANegativeLeadTimeAsZero(t *testing.T) {
	p := pushed("p", history.PushKindPush, time.Hour, 2)
	got := mainLeadOf(Data{Pushes: []history.Push{p}, PushCommits: []history.PushCommit{
		brought(p, "c1", "acme-dev", -10*time.Minute), brought(p, "c2", "acme-dev", 20*time.Minute)}})
	wantLead(t, got, 2, 10*time.Minute)
}

// TestMainlineLeadTimeCountsBotsAndCommitsOfUnknownParents (#467): a bot's
// commit and a commit from before the change count.
func TestMainlineLeadTimeCountsBotsAndCommitsOfUnknownParents(t *testing.T) {
	p := pushed("p", history.PushKindPush, time.Hour, 2)
	old := brought(p, "c2", "acme-dev", 30*time.Minute)
	old.Parents = history.ParentsUnknown
	got := mainLeadOf(Data{Pushes: []history.Push{p}, PushCommits: []history.PushCommit{
		brought(p, "c1", "dependabot[bot]", 10*time.Minute), old}})
	wantLead(t, got, 2, 20*time.Minute)
}

// TestMainlineLeadTimeCountsThePushesInTheWindowWithoutAKnownCommitCount: a
// force push and a cut compare (Commits 0) bring no commits and are counted
// as unknown, one out of the window not (#468).
func TestMainlineLeadTimeCountsThePushesInTheWindowWithoutAKnownCommitCount(t *testing.T) {
	known := pushed("k", history.PushKindPush, time.Hour, 1)
	force := pushed("f", history.PushKindForcePush, 2*time.Hour, 0)
	cut := pushed("c", history.PushKindPush, 3*time.Hour, 0)
	old := pushed("o", history.PushKindPush, 40*day, 0)
	got := mainLeadOf(Data{Pushes: []history.Push{known, force, cut, old},
		PushCommits: []history.PushCommit{brought(known, "c1", "acme-dev", time.Hour)}})
	wantLead(t, got, 1, time.Hour)
	if got.UnknownPushes != 2 {
		t.Errorf("want 2 unknown pushes, got %d", got.UnknownPushes)
	}
}

// TestMainlineLeadTimeIgnoresAPushOutOfTheWindowAndOfOtherProjects: a push 40
// days old and one of acme/cli (Acme Tools) are not Acme Shop's.
func TestMainlineLeadTimeIgnoresAPushOutOfTheWindowAndOfOtherProjects(t *testing.T) {
	old := pushed("o", history.PushKindPush, 40*day, 1)
	other := pushed("x", history.PushKindPush, time.Hour, 1)
	other.Repository = "acme/cli"
	line := brought(other, "x1", "acme-dev", time.Hour)
	got := MainlineLeadTimesOf(projects, Data{Pushes: []history.Push{old, other}, PushCommits: []history.PushCommit{
		brought(old, "o1", "acme-dev", time.Hour), line}}, now)
	wantLead(t, got[0], 0, 0)
	wantLead(t, got[1], 1, time.Hour)
}

// TestMainlineLeadTimeMatchesRepositoriesIgnoringCase: the push, its line
// and the pull request name the repository in capitals.
func TestMainlineLeadTimeMatchesRepositoriesIgnoringCase(t *testing.T) {
	p := pushed("sq", history.PushKindPRMerge, time.Hour, 1)
	p.Repository = "ACME/App"
	line := brought(p, "sq", "web-flow", 0)
	pull := pullMerging(7, "sq")
	pull.Repository = "Acme/APP"
	orig := pullCommit(7, "o1", p.PushedAt.Add(-2*time.Hour))
	orig.Repository = "acme/APP"
	got := mainLeadOf(Data{Pushes: []history.Push{p}, PushCommits: []history.PushCommit{line},
		Pulls: []history.PullRequest{pull}, PullCommits: []history.PullCommit{orig}})
	wantLead(t, got, 1, 2*time.Hour)
}

// TestMainlineLeadTimeCountsAMergeCommitOnceWhateverPushesBroughtIt: the same
// merge commit in two pushes is one merge left out.
func TestMainlineLeadTimeCountsAMergeCommitOnceWhateverPushesBroughtIt(t *testing.T) {
	a := pushed("a", history.PushKindPRMerge, 2*time.Hour, 1)
	b := pushed("b", history.PushKindPRMerge, time.Hour, 1)
	got := mainLeadOf(Data{Pushes: []history.Push{a, b},
		PushCommits: []history.PushCommit{mergeOf(a, "mg"), mergeOf(b, "mg")}})
	if got.MergesLeftOut != 1 {
		t.Errorf("want 1 merge left out, got %d", got.MergesLeftOut)
	}
}

// TestMainlineLeadTimeNeverTakesALineOffTheChainOrOfUnknownParentsForASquash:
// the merge commit of a pull request that is a branch line, or a line of
// unknown parents, counts as itself although the pull request has commits.
func TestMainlineLeadTimeNeverTakesALineOffTheChainOrOfUnknownParentsForASquash(t *testing.T) {
	p := pushed("tip", history.PushKindPRMerge, time.Hour, 2)
	old := pushed("old", history.PushKindPush, time.Hour, 1)
	unknown := brought(old, "old", "acme-dev", 3*time.Hour)
	unknown.Parents = history.ParentsUnknown
	got := mainLeadOf(Data{Pushes: []history.Push{p, old},
		PushCommits: []history.PushCommit{brought(p, "tip", "acme-dev", 0), branched(p, "off", 2*time.Hour),
			unknown},
		Pulls: []history.PullRequest{pullMerging(5, "off"), pullMerging(6, "old")},
		PullCommits: []history.PullCommit{pullCommit(5, "x", p.PushedAt.Add(-50*time.Hour)),
			pullCommit(6, "y", p.PushedAt.Add(-60*time.Hour))}})
	wantLead(t, got, 3, 5*time.Hour/3)
	if got.Squashed != 0 {
		t.Errorf("want nothing squashed, got %d", got.Squashed)
	}
}

// TestMainlineLeadTimeCountsAnOriginalOnceInSquashed: a pull request commit
// listed twice is one original.
func TestMainlineLeadTimeCountsAnOriginalOnceInSquashed(t *testing.T) {
	p := pushed("sq", history.PushKindPRMerge, time.Hour, 1)
	o := pullCommit(7, "o1", p.PushedAt.Add(-2*time.Hour))
	got := mainLeadOf(Data{Pushes: []history.Push{p},
		PushCommits: []history.PushCommit{brought(p, "sq", "web-flow", 0)},
		Pulls:       []history.PullRequest{pullMerging(7, "sq")}, PullCommits: []history.PullCommit{o, o}})
	if got.Squashed != 1 {
		t.Errorf("want 1 squashed original, got %d", got.Squashed)
	}
}
