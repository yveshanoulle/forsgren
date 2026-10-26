package metrics

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// Filling, NotReadable and Uncollected of the Mainline Lead Time (forsgren#463,
// step 7).

// unknownParentsData is a push of the kind in the window with a line of
// unknown parents.
func unknownParentsData(kind string) Data {
	p := pushed("p", kind, time.Hour, 1)
	c := brought(p, "c", "acme-dev", time.Minute)
	c.Parents = history.ParentsUnknown
	return Data{Pushes: []history.Push{p}, PushCommits: []history.PushCommit{c}}
}

// TestMainlineLeadTimeIsFillingWithAMergePushWithALineOfUnknownParents (#469,
// #476): a merge push lost its branch commits before the change.
func TestMainlineLeadTimeIsFillingWithAMergePushWithALineOfUnknownParents(t *testing.T) {
	if !mainLeadOf(unknownParentsData(history.PushKindPRMerge)).Filling {
		t.Error("want Filling with a pr_merge push with a line of unknown parents in the window")
	}
}

// TestMainlineLeadTimeIsNotFillingWithADirectPushWithALineOfUnknownParents
// (#476): a direct push lost nothing in the change.
func TestMainlineLeadTimeIsNotFillingWithADirectPushWithALineOfUnknownParents(t *testing.T) {
	if mainLeadOf(unknownParentsData(history.PushKindPush)).Filling {
		t.Error("want no Filling with a direct push with a line of unknown parents")
	}
}

// TestMainlineLeadTimeIsFillingWhenOneOfThePushesOfATipIsAMergePush (#476):
// several pushes can share a tip, and one merge push is enough.
func TestMainlineLeadTimeIsFillingWhenOneOfThePushesOfATipIsAMergePush(t *testing.T) {
	data := unknownParentsData(history.PushKindPRMerge)
	direct := data.Pushes[0]
	direct.Kind = history.PushKindPush
	data.Pushes = append(data.Pushes, direct)
	if !mainLeadOf(data).Filling {
		t.Error("want Filling when one of two pushes of the same tip is a pr_merge push")
	}
}

// TestMainlineLeadTimeIsFillingWithAMergedPullRequestWithoutPullCommits (#469).
func TestMainlineLeadTimeIsFillingWithAMergedPullRequestWithoutPullCommits(t *testing.T) {
	if !mainLeadOf(Data{Pulls: []history.PullRequest{pullMerging(3, "m")}}).Filling {
		t.Error("want Filling with a pull request merged in the window and no pull commits")
	}
}

// TestMainlineLeadTimeIsNotFillingOnceTheWindowLiesAfterTheChange: a pull
// request with its commits, one whose created time stood in, one merged out
// of the window, a line of unknown parents of a push out of the window, and
// a pull request of another project have no say.
func TestMainlineLeadTimeIsNotFillingOnceTheWindowLiesAfterTheChange(t *testing.T) {
	data := unknownParentsData(history.PushKindPRMerge)
	data.Pushes[0].PushedAt = now.Add(-40 * day)
	stood := pullMerging(2, "s")
	stood.CreatedStandsIn = true
	old := pullMerging(3, "o")
	old.MergedAt = now.Add(-40 * day)
	elsewhere := pullMerging(5, "e")
	elsewhere.Repository = "acme/cli"
	data.Pulls = []history.PullRequest{pullMerging(1, "m"), stood, old, elsewhere}
	data.PullCommits = []history.PullCommit{pullCommit(1, "o1", now.Add(-3*time.Hour))}
	known := pushed("k", history.PushKindPush, time.Hour, 1)
	data.Pushes = append(data.Pushes, known)
	data.PushCommits = append(data.PushCommits, brought(known, "k1", "acme-dev", time.Minute))
	if mainLeadOf(data).Filling {
		t.Error("want no Filling")
	}
}

// TestMainlineLeadTimeIsNotFillingOnceTheFillOfTheRepositoryIsDone (#470,
// decision #484 A): a repository in PullsFilled no longer sets Filling by a
// pull request without pull commits, one in PushesFilled not by a merge
// push's line of unknown parents, each fill ruling its own source, and the
// repository name compared ignoring case.
func TestMainlineLeadTimeIsNotFillingOnceTheFillOfTheRepositoryIsDone(t *testing.T) {
	done := history.Reach{"acme/app": now}
	pulls := Data{Pulls: []history.PullRequest{pullMerging(3, "m")}}
	pushes := unknownParentsData(history.PushKindPRMerge)
	for name, c := range map[string]struct {
		data Data
		want bool
	}{
		"pull fill done":              {withFilled(pulls, done, nil), false},
		"pull fill done, other case":  {withFilled(pulls, history.Reach{"ACME/App": now}, nil), false},
		"push fill done for pulls":    {withFilled(pulls, nil, done), true},
		"push fill done":              {withFilled(pushes, nil, done), false},
		"push fill done, other case":  {withFilled(pushes, nil, history.Reach{"ACME/App": now}), false},
		"pull fill done for pushes":   {withFilled(pushes, done, nil), true},
		"another repository is done":  {withFilled(pulls, history.Reach{"acme/cli": now}, nil), true},
		"another repository is done2": {withFilled(pushes, nil, history.Reach{"acme/cli": now}), true},
	} {
		t.Run(name, func(t *testing.T) {
			if got := mainLeadOf(c.data).Filling; got != c.want {
				t.Errorf("want Filling %v, got %v", c.want, got)
			}
		})
	}
}

// withFilled is data with the fill marks pulls and pushes.
func withFilled(data Data, pulls, pushes history.Reach) Data {
	data.PullsFilled, data.PushesFilled = pulls, pushes
	return data
}

// TestMainlineLeadTimeIsNotReadableOrUncollected: a project with a repository
// in PushesDenied (any case) is NotReadable, and with no pushes file every
// other project is Uncollected.
func TestMainlineLeadTimeIsNotReadableOrUncollected(t *testing.T) {
	got := MainlineLeadTimesOf(projects, Data{PushesUncollected: true, PushesDenied: history.Reach{"ACME/App": now}}, now)
	states := [4]bool{got[0].NotReadable, got[0].Uncollected, got[1].NotReadable, got[1].Uncollected}
	if states != [4]bool{true, false, false, true} {
		t.Errorf("want Acme Shop not readable and Acme Tools uncollected, got %v", states)
	}
}
