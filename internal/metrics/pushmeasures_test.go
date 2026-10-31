package metrics

import (
	"math"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// The push measures (forsgren#397, step 4).

// pushed is a push of acme/app to main, pushedAgo before now, that ended at
// after, of kind, said to have added commits commits.
func pushed(after, kind string, pushedAgo time.Duration, commits int64) history.Push {
	return history.Push{Repository: "acme/app", PushedAt: now.Add(-pushedAgo), Before: "base", After: after,
		Kind: kind, Bot: history.ByHuman, Commits: commits}
}

// brought is the commit sha of push, made by login and authored lead before
// the push.
func brought(push history.Push, sha, login string, lead time.Duration) history.PushCommit {
	return history.PushCommit{Repository: push.Repository, After: push.After, SHA: sha, Author: login,
		AuthoredAt: push.PushedAt.Add(-lead), FirstParent: true, Parents: 1}
}

// shopPushMeasures is PushMeasuresOf for Acme Shop of data.
func shopPushMeasures(data Data) PushMeasures { return PushMeasuresOf(projects, data, now)[0] }

// pushesData is three pushes of acme/app in the window: p1 a direct push of
// three commits (30, 20 and 10 minutes old, the last by GitHub's placeholder
// login, any case), p2 a pull request merge of one commit a day old, p3 a
// direct push of two commits, x the merge commit of a pull request of the
// data and y by no login, authored after the push; c1 is by a bot.
func pushesData() Data {
	m := time.Minute
	p1 := pushed("p1", history.PushKindPush, 2*time.Hour, 3)
	p2 := pushed("p2", history.PushKindPRMerge, time.Hour, 1)
	p3 := pushed("p3", history.PushKindPush, 30*m, 2)
	return Data{
		Pushes: []history.Push{p1, p2, p3},
		PushCommits: []history.PushCommit{
			brought(p1, "c1", "dependabot[bot]", 30*m), brought(p1, "c2", "acme-dev", 20*m),
			brought(p1, "c3", "Invalid-Email-Address", 10*m), brought(p2, "m", "acme-dev", 24*time.Hour),
			brought(p3, "x", "acme-dev", 5*m), brought(p3, "y", "", -10*m),
		},
		Pulls: []history.PullRequest{pullMergedAs("x")},
	}
}

// TestPushMeasuresCountTheCommitsTheirSharesTheTimeToMainAndThePerPush
// (forsgren#397, step 4): 3 pushes, 6 distinct commits; pull requests 2 (the
// pr_merge push's commit and the pull request's merge commit), direct 4,
// unknown authors 2 (no login, placeholder), bots 1 (a login ending in [bot]); time to main per commit, push
// time minus author date, 0 for the one authored after the push: 0, 5, 10,
// 20, 30 min and 24 h, so mean 4 h 10 min 50 s and median 15 min, no p90
// under ten, and the squares of the differences from the mean add up to
// 10185125/6 min², over n-1 = 5 (forsgren#588, step 2); commits per push 3, 1
// and 2: mean 2, median 2, deviation 1.
func TestPushMeasuresCountTheCommitsTheirSharesTheTimeToMainAndThePerPush(t *testing.T) {
	got := shopPushMeasures(pushesData())
	want := PushMeasures{Project: "Acme Shop", Pushes: 3, Commits: 6, PullRequests: 2, Direct: 4,
		UnknownAuthors: 2, Bots: 1,
		TimeToMain: DurationSpread{Count: 6, Mean: 4*time.Hour + 10*time.Minute + 50*time.Second,
			Median: 15 * time.Minute, Deviation: rootOf(10185125.0/6/5, time.Minute)},
		PerPush: CountSpread{Count: 3, Mean: 2, Median: 2, Deviation: 1}}
	if got != want {
		t.Errorf("want %+v, got %+v", want, got)
	}
}

// TestPushMeasuresShareTheCommitsRoundedDown: 2, 4, 2 and 1 of 6 are 33, 66,
// 33 and 16 percent.
func TestPushMeasuresShareTheCommitsRoundedDown(t *testing.T) {
	got := shopPushMeasures(pushesData())
	shares := [4]string{got.PullRequestCell(), got.DirectCell(), got.UnknownAuthorCell(), got.BotCell()}
	if shares != [4]string{"33%", "66%", "33%", "16%"} {
		t.Errorf("want shares 33, 66, 33 and 16 percent, got %v", shares)
	}
}

// shownOf are which of the median and the p90 of the time to main and of the
// commits per push m shows.
func shownOf(m PushMeasures) [4]bool {
	return [4]bool{m.TimeToMain.HasMedian(), m.TimeToMain.HasP90(), m.PerPush.HasMedian(), m.PerPush.HasP90()}
}

// TestPushMeasuresShowOnlyTheMeanOfOnePush: one push of one commit has a mean
// and no median and no p90.
func TestPushMeasuresShowOnlyTheMeanOfOnePush(t *testing.T) {
	p := pushed("p1", history.PushKindPush, time.Hour, 1)
	one := Data{Pushes: []history.Push{p}, PushCommits: []history.PushCommit{brought(p, "c1", "acme-dev", 7*time.Minute)}}
	got := shopPushMeasures(one)
	want := PushMeasures{Project: "Acme Shop", Pushes: 1, Commits: 1, Direct: 1,
		TimeToMain: DurationSpread{Count: 1, Mean: 7 * time.Minute}, PerPush: CountSpread{Count: 1, Mean: 1}}
	if got != want || shownOf(got) != [4]bool{} {
		t.Errorf("want %+v with nothing past the mean shown, got %+v", want, got)
	}
}

// TestPushMeasuresShowTheMedianAndP90FromTen: ten pushes of 1 to 10 commits,
// one commit each timed 1 to 10 minutes, have a p90 by nearest rank, the 9th,
// a median of 5.5 and a sample standard deviation of the root of 82.5/9, the
// squares of the differences from 5.5 over n-1 (forsgren#588, step 2).
func TestPushMeasuresShowTheMedianAndP90FromTen(t *testing.T) {
	var ten Data
	for i := 1; i <= 10; i++ {
		after := string(rune('a' + i))
		p := pushed(after, history.PushKindPush, time.Hour, int64(i))
		ten.Pushes = append(ten.Pushes, p)
		ten.PushCommits = append(ten.PushCommits, brought(p, "c"+after, "acme-dev", time.Duration(i)*time.Minute))
	}
	got := shopPushMeasures(ten)
	want := PushMeasures{Project: "Acme Shop", Pushes: 10, Commits: 10, Direct: 10,
		TimeToMain: DurationSpread{Count: 10, Mean: 5*time.Minute + 30*time.Second,
			Median: 5*time.Minute + 30*time.Second, P90: 9 * time.Minute, Deviation: rootOf(82.5/9, time.Minute)},
		PerPush: CountSpread{Count: 10, Mean: 5.5, Median: 5.5, P90: 9, Deviation: math.Sqrt(82.5 / 9)}}
	if got != want || shownOf(got) != [4]bool{true, true, true, true} {
		t.Errorf("want %+v with everything shown, got %+v", want, got)
	}
}

// TestPushMeasuresCountThePushesOfTheWindowOnly: a push before the DORA
// window (30 days) and its commits are left out; a push exactly 30 days old
// is in, and both are in a 90-day window.
func TestPushMeasuresCountThePushesOfTheWindowOnly(t *testing.T) {
	old := pushed("old", history.PushKindPush, 31*24*time.Hour, 1)
	edge := pushed("edge", history.PushKindPush, 30*24*time.Hour, 1)
	data := Data{Pushes: []history.Push{old, edge},
		PushCommits: []history.PushCommit{brought(old, "o1", "acme-dev", time.Minute),
			brought(edge, "e1", "acme-dev", time.Minute)}}
	if got := shopPushMeasures(data); [3]int{got.Pushes, got.Commits, got.PerPush.Count} != [3]int{1, 1, 1} {
		t.Errorf("want the edge push alone, got %+v", got)
	}
	data.DoraDays = 90
	if got := shopPushMeasures(data); [2]int{got.Pushes, got.Commits} != [2]int{2, 2} {
		t.Errorf("want both in a 90-day window, got %+v", got)
	}
}

// TestPushMeasuresCountACommitOnceAtItsFirstPush: the same commit brought by
// two pushes is one commit, timed at the earlier push, and a pull request
// when any of its pushes was a pull request merge, whatever the order of the
// files.
func TestPushMeasuresCountACommitOnceAtItsFirstPush(t *testing.T) {
	late := pushed("late", history.PushKindPush, time.Hour, 1)
	early := pushed("early", history.PushKindPRMerge, 3*time.Hour, 1)
	early.Repository = "ACME/app"
	lateCommit := brought(late, "c1", "acme-dev", 2*time.Hour+10*time.Minute)
	earlyCommit := brought(early, "c1", "acme-dev", 10*time.Minute)
	want := PushMeasures{Project: "Acme Shop", Pushes: 2, Commits: 1, PullRequests: 1,
		TimeToMain: DurationSpread{Count: 1, Mean: 10 * time.Minute}, PerPush: CountSpread{Count: 2, Mean: 1, Median: 1}}
	for name, data := range map[string]Data{
		"late first":  {Pushes: []history.Push{late, early}, PushCommits: []history.PushCommit{lateCommit, earlyCommit}},
		"early first": {Pushes: []history.Push{early, late}, PushCommits: []history.PushCommit{earlyCommit, lateCommit}},
	} {
		if got := shopPushMeasures(data); got != want {
			t.Errorf("%s: want %+v, got %+v", name, want, got)
		}
	}
}

// TestPushMeasuresLeaveOutAPushWithoutAKnownCount: a push whose commits
// column is empty counts as a push but is not in commits per push.
func TestPushMeasuresLeaveOutAPushWithoutAKnownCount(t *testing.T) {
	data := pushesData()
	data.Pushes = append(data.Pushes, pushed("f1", history.PushKindForcePush, 10*time.Minute, 0))
	got := shopPushMeasures(data)
	if [3]int{got.Pushes, got.PerPush.Count, got.Commits} != [3]int{4, 3, 6} {
		t.Errorf("want 4 pushes, 3 with a count and 6 commits, got %+v", got)
	}
}

// TestPushMeasuresGiveEachProjectItsOwnRepositories: acme/cli is Acme Tools'
// (written in any case), acme/api Acme Shop's, and acme/other is no
// project's.
func TestPushMeasuresGiveEachProjectItsOwnRepositories(t *testing.T) {
	var data Data
	for after, repository := range map[string]string{"t1": "ACME/cli", "o1": "acme/other", "a1": "acme/api"} {
		p := pushed(after, history.PushKindPush, time.Hour, 1)
		p.Repository = repository
		data.Pushes = append(data.Pushes, p)
		data.PushCommits = append(data.PushCommits, brought(p, "c"+after, "acme-dev", time.Minute))
	}
	got := PushMeasuresOf(projects, data, now)
	if [2]int{got[0].Commits, got[1].Commits} != [2]int{1, 1} || got[1].Project != "Acme Tools" {
		t.Errorf("want one commit each, got %+v", got)
	}
}

// TestPushMeasuresHaveNoSharesWithoutACommit: no commit, no counts, and no
// state.
func TestPushMeasuresHaveNoSharesWithoutACommit(t *testing.T) {
	got := shopPushMeasures(Data{})
	if got != (PushMeasures{Project: "Acme Shop"}) {
		t.Errorf("want nothing, got %+v", got)
	}
}

// TestAProjectWithARefusedPushReadIsNotReadable: one repository of the
// project in Data.PushesDenied, written in any case, makes the project not
// readable whatever the others gave; another project is not.
func TestAProjectWithARefusedPushReadIsNotReadable(t *testing.T) {
	data := pushesData()
	data.PushesDenied = history.Reach{"ACME/Api": now}
	got := PushMeasuresOf(projects, data, now)
	if [2]bool{got[0].NotReadable, got[1].NotReadable} != [2]bool{true, false} {
		t.Errorf("want Acme Shop alone not readable, got %+v", got)
	}
}

// TestAProjectWithoutAPushesFileIsUncollected: with no data/pushes.csv every
// project is Uncollected, never a fallback to deployments; a project not
// readable is not also uncollected.
func TestAProjectWithoutAPushesFileIsUncollected(t *testing.T) {
	data := Data{PushesUncollected: true, PushesDenied: history.Reach{"acme/cli": now}}
	got := PushMeasuresOf(projects, data, now)
	states := [4]bool{got[0].Uncollected, got[0].NotReadable, got[1].Uncollected, got[1].NotReadable}
	if states != [4]bool{true, false, false, true} {
		t.Errorf("want Acme Shop uncollected and Acme Tools not readable, got %v", states)
	}
}

// TestAPushCommitOffTheFirstParentChainIsNotCounted (forsgren#463, step 4):
// a push that brought a chain commit and a branch commit (first_parent
// false, authored days earlier) has the Commits, the shares and the time to
// main of the chain commit alone.
func TestAPushCommitOffTheFirstParentChainIsNotCounted(t *testing.T) {
	p := pushed("p1", history.PushKindPush, time.Hour, 1)
	branch := brought(p, "b1", "acme-dev", 72*time.Hour)
	branch.FirstParent = false
	data := Data{Pushes: []history.Push{p},
		PushCommits: []history.PushCommit{branch, brought(p, "c1", "acme-dev", 7*time.Minute)}}
	got := shopPushMeasures(data)
	want := PushMeasures{Project: "Acme Shop", Pushes: 1, Commits: 1, Direct: 1,
		TimeToMain: DurationSpread{Count: 1, Mean: 7 * time.Minute}, PerPush: CountSpread{Count: 1, Mean: 1}}
	if got != want {
		t.Errorf("want %+v, got %+v", want, got)
	}
}
